using System.Text.Json;
using ApiFactory.Models;
using ApiFactory.Services;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddOpenApi(options =>
{
    options.OpenApiVersion = Microsoft.OpenApi.OpenApiSpecVersion.OpenApi3_0;
});

// Use real Azure Event Hub if connection string is configured, otherwise console stub
var ehConnectionString = builder.Configuration["EventHub:ConnectionString"];
var ehName = builder.Configuration["EventHub:Name"];

if (!string.IsNullOrEmpty(ehConnectionString) && !string.IsNullOrEmpty(ehName))
{
    builder.Services.AddSingleton<IEventHubService>(sp =>
        new AzureEventHubService(
            ehConnectionString,
            ehName,
            sp.GetRequiredService<ILogger<AzureEventHubService>>()));
}
else
{
    builder.Services.AddSingleton<IEventHubService, ConsoleEventHubService>();
}

builder.Services.AddSingleton<MachineSimulatorManager>();

// Data store: Azure Files via managed identity when a storage account is configured,
// otherwise a local filesystem store (dev / fallback).
var storageAccountName = builder.Configuration["Storage:AccountName"];
var fileShareName = builder.Configuration["Storage:FileShareName"] ?? "appdata";
if (!string.IsNullOrEmpty(storageAccountName))
{
    builder.Services.AddSingleton<IDataStore>(sp =>
        new AzureFileShareDataStore(
            storageAccountName,
            fileShareName,
            sp.GetRequiredService<ILogger<AzureFileShareDataStore>>()));
}
else
{
    var dataDir = Environment.GetEnvironmentVariable("DATA_DIR") ?? AppContext.BaseDirectory;
    builder.Services.AddSingleton<IDataStore>(new LocalDataStore(dataDir));
}

var app = builder.Build();

// if (app.Environment.IsDevelopment())
// {
//     app.MapOpenApi();
// }

app.MapOpenApi();
app.UseDefaultFiles();
app.UseStaticFiles();

var simulator = app.Services.GetRequiredService<MachineSimulatorManager>();
var dataStore = app.Services.GetRequiredService<IDataStore>();

const string machinesFileName = "machines.json";
var jsonOptions = new JsonSerializerOptions { PropertyNameCaseInsensitive = true };

// Load machines.json on startup and auto-start
if (dataStore.Exists(machinesFileName))
{
    var json = dataStore.Read(machinesFileName);
    var config = json != null ? JsonSerializer.Deserialize<SimulatorConfig>(json, jsonOptions) : null;
    if (config?.Machines?.Count > 0)
    {
        simulator.UpdateConfig(config);
        simulator.StartAll();
        app.Logger.LogInformation("Loaded {Count} machines from machines.json and started", config.Machines.Count);
    }
}

// --- Health ---
app.MapGet("/health", () => Results.Ok(new { status = "ok" }));

// --- Configuration ---
app.MapPost("/simulator/config", (SimulatorConfig config) =>
{
    if (config.Machines == null || config.Machines.Count == 0)
        return Results.BadRequest(new { error = "Body must contain a non-empty 'machines' array" });

    // Save so it persists across restarts
    var json = JsonSerializer.Serialize(config, new JsonSerializerOptions { WriteIndented = true });
    dataStore.Write(machinesFileName, json);

    // Stop all, apply new config, restart (StartAll also restores persisted anomaly states)
    simulator.UpdateConfig(config);
    simulator.StartAll();
    return Results.Ok(new { status = "config_updated_and_started", machines = config.Machines.Count });
});

app.MapGet("/simulator/config", () => Results.Ok(simulator.GetConfig()));

// --- Start / Stop ---
app.MapPost("/simulator/start", () =>
{
    var config = simulator.GetConfig();
    if (config.Machines.Count == 0)
        return Results.BadRequest(new { error = "No machines configured. POST /simulator/config first" });

    simulator.StartAll();
    return Results.Ok(new { status = "started", machines = config.Machines.Count });
});

app.MapPost("/simulator/stop", () =>
{
    simulator.StopAll();
    return Results.Ok(new { status = "stopped" });
});

app.MapPost("/simulator/{machineId}/start", (string machineId) =>
{
    return simulator.StartMachine(machineId)
        ? Results.Ok(new { status = "started", machine = machineId })
        : Results.NotFound(new { error = $"Machine '{machineId}' not found or already running" });
});

app.MapPost("/simulator/{machineId}/stop", (string machineId) =>
{
    return simulator.StopMachine(machineId)
        ? Results.Ok(new { status = "stopped", machine = machineId })
        : Results.NotFound(new { error = $"Machine '{machineId}' not found or not running" });
});

// --- Anomaly injection ---
app.MapPost("/simulator/{machineId}/anomaly/{anomalyName}", (string machineId, string anomalyName) =>
{
    return simulator.TriggerAnomaly(machineId, anomalyName)
        ? Results.Ok(new { status = "anomaly_triggered", machine = machineId, anomaly = anomalyName })
        : Results.NotFound(new { error = $"Machine '{machineId}' not running or anomaly '{anomalyName}' not defined" });
});

app.MapPost("/simulator/{machineId}/clear-anomaly", (string machineId) =>
{
    return simulator.ClearAnomaly(machineId)
        ? Results.Ok(new { status = "anomaly_cleared", machine = machineId })
        : Results.NotFound(new { error = $"Machine '{machineId}' not running" });
});

// --- Status ---
app.MapGet("/simulator/status", () => Results.Ok(simulator.GetAllStatus()));

app.MapGet("/simulator/{machineId}/status", (string machineId) =>
{
    var status = simulator.GetMachineStatus(machineId);
    return status != null
        ? Results.Ok(status)
        : Results.NotFound(new { error = $"Machine '{machineId}' not found" });
});

// --- Telemetry (latest payload for UI) ---
app.MapGet("/simulator/{machineId}/telemetry", (string machineId) =>
{
    var telemetry = simulator.GetLatestTelemetry(machineId);
    return telemetry != null
        ? Results.Ok(telemetry)
        : Results.NotFound(new { error = $"No telemetry for '{machineId}'" });
});

app.Run();

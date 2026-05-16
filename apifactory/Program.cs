using ApiFactory.Models;
using ApiFactory.Services;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddOpenApi();
builder.Services.AddSingleton<IEventHubService, ConsoleEventHubService>();
builder.Services.AddSingleton<MachineSimulatorManager>();

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
}

app.UseDefaultFiles();
app.UseStaticFiles();

var simulator = app.Services.GetRequiredService<MachineSimulatorManager>();

// --- Health ---
app.MapGet("/health", () => Results.Ok(new { status = "ok" }));

// --- Configuration ---
app.MapPost("/simulator/config", (SimulatorConfig config) =>
{
    if (config.Machines == null || config.Machines.Count == 0)
        return Results.BadRequest(new { error = "Body must contain a non-empty 'machines' array" });

    simulator.UpdateConfig(config);
    return Results.Ok(new { status = "config_updated", machines = config.Machines.Count });
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

app.MapPost("/simulator/{machineId}/anomaly/clear", (string machineId) =>
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

using System.Text.Json;
using System.Text.Json.Serialization;
using ApiShop.Models;
using ApiShop.Services;
using Azure.Core;
using Azure.Identity;
using Microsoft.Data.SqlClient;

var builder = WebApplication.CreateBuilder(args);
builder.Logging.AddSimpleConsole(options => options.SingleLine = true);
builder.Services.AddOpenApi(options => options.OpenApiVersion = Microsoft.OpenApi.OpenApiSpecVersion.OpenApi3_0);
builder.Services.ConfigureHttpJsonOptions(options =>
    options.SerializerOptions.Converters.Add(new JsonStringEnumConverter()));
builder.Services.AddSingleton(TimeProvider.System);

var destination = builder.Configuration["Sales:Destination"] ?? "Sql";
if (destination.Equals("Sql", StringComparison.OrdinalIgnoreCase))
{
    var server = builder.Configuration["Sql:Server"];
    var database = builder.Configuration["Sql:Database"];
    if (string.IsNullOrWhiteSpace(server) || string.IsNullOrWhiteSpace(database))
        throw new InvalidOperationException("SQL sales require Sql:Server and Sql:Database. Use Sales:Destination=Console explicitly for local simulation.");
    var authentication = builder.Configuration["Sql:Authentication"] ?? "ManagedIdentity";
    TokenCredential credential = authentication switch
    {
        "ManagedIdentity" => new ManagedIdentityCredential(),
        "Developer" when builder.Environment.IsDevelopment() => new AzureCliCredential(),
        _ => throw new InvalidOperationException("Sql:Authentication must be ManagedIdentity, or Developer in the Development environment.")
    };
    var connectionString = new SqlConnectionStringBuilder
    {
        DataSource = server,
        InitialCatalog = database,
        Encrypt = SqlConnectionEncryptOption.Mandatory,
        TrustServerCertificate = false,
        ConnectTimeout = 15,
        ConnectRetryCount = 0
    }.ConnectionString;
    builder.Services.AddSingleton<ISalesDatabase>(new SqlSalesDatabase(connectionString, credential));
    builder.Services.AddSingleton<ISaleWriter, SqlSaleWriter>();
}
else if (destination.Equals("Console", StringComparison.OrdinalIgnoreCase))
{
    builder.Services.AddSingleton<ISaleWriter, ConsoleSaleWriter>();
}
else
    throw new InvalidOperationException("Sales:Destination must be Sql or Console.");

var storageAccount = builder.Configuration["Storage:AccountName"];
var fileShare = builder.Configuration["Storage:FileShareName"] ?? "appdata";
if (!string.IsNullOrWhiteSpace(storageAccount))
{
    builder.Services.AddSingleton<IDataStore>(services =>
        new AzureFileShareDataStore(
            storageAccount,
            fileShare,
            services.GetRequiredService<ILogger<AzureFileShareDataStore>>()));
}
else
{
    var dataDirectory = Environment.GetEnvironmentVariable("DATA_DIR") ?? AppContext.BaseDirectory;
    builder.Services.AddSingleton<IDataStore>(new LocalDataStore(dataDirectory));
}

builder.Services.AddSingleton<ShopSimulatorManager>();
var app = builder.Build();
app.MapOpenApi();
app.UseDefaultFiles();
app.UseStaticFiles();

var manager = app.Services.GetRequiredService<ShopSimulatorManager>();
app.Lifetime.ApplicationStopping.Register(manager.StopAll);
var store = app.Services.GetRequiredService<IDataStore>();
var saleWriter = app.Services.GetRequiredService<ISaleWriter>();
const string configFile = "shops.json";
var serializerOptions = new JsonSerializerOptions { PropertyNameCaseInsensitive = true };

string? configJson = null;
if (store.Exists(configFile))
{
    configJson = store.Read(configFile);
}
else
{
    var bundledConfigPath = Path.Combine(AppContext.BaseDirectory, configFile);
    if (File.Exists(bundledConfigPath))
    {
        configJson = File.ReadAllText(bundledConfigPath);
        store.Write(configFile, configJson);
    }
}

if (configJson is not null)
{
    var config = JsonSerializer.Deserialize<SimulatorConfig>(configJson, serializerOptions);
    if (config?.Shops.Count > 0)
    {
        manager.UpdateConfig(config);
        manager.StartAll();
    }
}

app.MapGet("/health", () => Results.Ok(new { status = "ok" }));
app.MapGet("/simulator/config", () => Results.Ok(manager.GetConfig()));
app.MapPost("/simulator/config", async Task<IResult> (SimulatorConfig config, CancellationToken ct) =>
{
    var error = Validate(config);
    if (error is not null) return TypedResults.BadRequest(new { error });
    var registry = await saleWriter.ValidateConfigurationAsync(config, ct);
    if (!registry.IsAvailable)
        return TypedResults.Problem(statusCode: StatusCodes.Status503ServiceUnavailable,
            title: "SQL registry unavailable", detail: "Configuration was not changed. Retry when the SQL database is available.");
    if (registry.Errors.Count > 0)
        return TypedResults.BadRequest(new { error = "Configuration does not match the SQL registry.", details = registry.Errors });
    store.Write(configFile, JsonSerializer.Serialize(config, new JsonSerializerOptions { WriteIndented = true }));
    manager.UpdateConfig(config);
    manager.StartAll();
    return TypedResults.Ok(new { status = "config_updated_and_started", shops = config.Shops.Count });
}).WithSummary("Validate, persist, and start shop configuration")
    .Produces(StatusCodes.Status200OK).Produces(StatusCodes.Status400BadRequest)
    .ProducesProblem(StatusCodes.Status503ServiceUnavailable);
app.MapGet("/simulator/status", () => Results.Ok(manager.GetAllStatus()));
app.MapGet("/simulator/{shopId}/status", (string shopId) =>
    manager.GetShopStatus(shopId) is { } status ? Results.Ok(status) : Results.NotFound());
app.MapGet("/simulator/{shopId}/sale", (string shopId) =>
    manager.GetLatestSale(shopId) is { } sale ? Results.Ok(sale) : Results.NotFound());
app.MapPost("/simulator/start", () => { manager.StartAll(); return Results.Ok(new { status = "started" }); });
app.MapPost("/simulator/stop", () => { manager.StopAll(); return Results.Ok(new { status = "stopped" }); });
app.MapPost("/simulator/{shopId}/start", (string shopId) =>
    manager.StartShop(shopId) ? Results.Ok(new { status = "started", shop = shopId }) : Results.NotFound());
app.MapPost("/simulator/{shopId}/stop", (string shopId) =>
    manager.StopShop(shopId) ? Results.Ok(new { status = "stopped", shop = shopId }) : Results.NotFound());
app.MapPost("/simulator/{shopId}/rush", (string shopId) =>
    manager.SetRush(shopId, true) ? Results.Ok(new { status = "rush", shop = shopId }) : Results.NotFound());
app.MapPost("/simulator/{shopId}/normal", (string shopId) =>
    manager.SetRush(shopId, false) ? Results.Ok(new { status = "open", shop = shopId }) : Results.NotFound());

app.Run();

static string? Validate(SimulatorConfig config)
{
    if (config.Shops.Count == 0) return "Body must contain a non-empty 'shops' array.";
    if (config.Shops.Select(shop => shop.Id).Distinct(StringComparer.OrdinalIgnoreCase).Count() != config.Shops.Count)
        return "Shop IDs must be unique.";
    foreach (var shop in config.Shops)
    {
        if (string.IsNullOrWhiteSpace(shop.Id) || string.IsNullOrWhiteSpace(shop.City) ||
            string.IsNullOrWhiteSpace(shop.Currency) || string.IsNullOrWhiteSpace(shop.TimeZoneId))
            return "Each shop requires id, city, currency, and timeZoneId.";
        if (shop.Flavors.Count < 6) return $"Shop '{shop.Id}' must define at least six flavors.";
        if (shop.Flavors.Any(string.IsNullOrWhiteSpace) ||
            shop.Flavors.Distinct(StringComparer.OrdinalIgnoreCase).Count() != shop.Flavors.Count)
            return $"Shop '{shop.Id}' must define unique, non-empty flavor names.";
        if (shop.Currency is not ("EUR" or "USD" or "JPY"))
            return $"Shop '{shop.Id}' currency must be EUR, USD, or JPY.";
        if (shop.MinItemPrice <= 0 || shop.MaxItemPrice < shop.MinItemPrice)
            return $"Shop '{shop.Id}' has an invalid price range.";
        try { _ = TimeZoneInfo.FindSystemTimeZoneById(shop.TimeZoneId); }
        catch (TimeZoneNotFoundException) { return $"Shop '{shop.Id}' has an unknown timeZoneId."; }
        catch (InvalidTimeZoneException) { return $"Shop '{shop.Id}' has an invalid timeZoneId."; }
    }
    return null;
}

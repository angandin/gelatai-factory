using System.Collections.Concurrent;
using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using ApiShop.Models;
using ApiShop.Services;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Time.Testing;

namespace EventHubCooldown.Tests;

public sealed class ShopConfigurationApiTests
{
    [Fact]
    public async Task RejectedOrUnavailableCatalogDoesNotSaveOrStopCurrentConfiguration()
    {
        var database = new TestSalesDatabase();
        var store = new MemoryShopStore();
        await using var factory = CreateFactory(database, store);
        using var client = factory.CreateClient();
        var original = store.Read("shops.json");

        var invalid = new SimulatorConfig { Shops = [SalesTestData.Shop()] };
        invalid.Shops[0].Id = "unknown";
        using var rejected = await client.PostAsJsonAsync("/simulator/config", invalid);
        Assert.Equal(HttpStatusCode.BadRequest, rejected.StatusCode);
        Assert.Equal(original, store.Read("shops.json"));

        database.Failure = new TestDatabaseException("Unavailable");
        using var unavailable = await client.PostAsJsonAsync("/simulator/config",
            new SimulatorConfig { Shops = [SalesTestData.Shop()] });
        Assert.Equal(HttpStatusCode.ServiceUnavailable, unavailable.StatusCode);
        Assert.Equal(original, store.Read("shops.json"));
        using var status = await client.GetAsync("/simulator/it-roma-001/status");
        Assert.Equal(HttpStatusCode.OK, status.StatusCode);
        Assert.Contains("Open", await status.Content.ReadAsStringAsync());
        using var health = await client.GetAsync("/health");
        Assert.Equal(HttpStatusCode.OK, health.StatusCode);
    }

    [Fact]
    public async Task SqlOutageDoesNotPreventHttpStartupOrLatestSaleAvailability()
    {
        var database = new TestSalesDatabase { Failure = new TestDatabaseException("SQL unavailable at startup") };
        await using var factory = CreateFactory(database, new MemoryShopStore());
        using var client = factory.CreateClient();
        using var health = await client.GetAsync("/health");
        Assert.Equal(HttpStatusCode.OK, health.StatusCode);
        await AssertLatestSaleAvailableAsync(client, factory.Services.GetRequiredService<TimeProvider>());
        using var status = await client.GetAsync("/simulator/it-roma-001/status");
        Assert.Equal(HttpStatusCode.OK, status.StatusCode);
        using var json = JsonDocument.Parse(await status.Content.ReadAsStringAsync());
        Assert.Equal(0, json.RootElement.GetProperty("salesSent").GetInt64());
        Assert.True(database.Attempts > 0);
    }

    [Fact]
    public async Task ValidConfigurationPreservesApiAndOpenApiContracts()
    {
        await using var factory = CreateFactory(new TestSalesDatabase(), new MemoryShopStore());
        using var client = factory.CreateClient();
        using var result = await client.PostAsJsonAsync("/simulator/config",
            new SimulatorConfig { Shops = [SalesTestData.Shop()] });
        Assert.Equal(HttpStatusCode.OK, result.StatusCode);
        using var openApi = await client.GetAsync("/openapi/v1.json");
        Assert.Equal(HttpStatusCode.OK, openApi.StatusCode);
        var json = await openApi.Content.ReadAsStringAsync();
        Assert.Contains("503", json);
        using var waiting = await client.GetAsync("/simulator/it-roma-001/sale");
        Assert.Equal(HttpStatusCode.NotFound, waiting.StatusCode);
        await AssertLatestSaleAvailableAsync(client, factory.Services.GetRequiredService<TimeProvider>());
    }

    private static async Task AssertLatestSaleAvailableAsync(HttpClient client, TimeProvider timeProvider)
    {
        Assert.IsType<FakeTimeProvider>(timeProvider).Advance(TimeSpan.FromMinutes(10));
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        while (true)
        {
            using var sale = await client.GetAsync("/simulator/it-roma-001/sale", timeout.Token);
            if (sale.StatusCode != HttpStatusCode.NotFound)
            {
                Assert.Equal(HttpStatusCode.OK, sale.StatusCode);
                return;
            }
            await Task.Delay(10, timeout.Token);
        }
    }

    private static WebApplicationFactory<ShopSimulatorManager> CreateFactory(
        TestSalesDatabase database, MemoryShopStore store) =>
        new WebApplicationFactory<ShopSimulatorManager>().WithWebHostBuilder(builder =>
        {
            builder.UseEnvironment("Development");
            builder.ConfigureAppConfiguration((_, configuration) => configuration.AddInMemoryCollection(
                new Dictionary<string, string?>
                {
                    ["Sales:Destination"] = "Sql",
                    ["Sql:Server"] = "localhost,1",
                    ["Sql:Database"] = "NotUsedByFakeDatabase",
                    ["Sql:Authentication"] = "ManagedIdentity"
                }));
            builder.ConfigureTestServices(services =>
            {
                services.RemoveAll<ISaleWriter>();
                services.RemoveAll<ISalesDatabase>();
                services.RemoveAll<IDataStore>();
                services.AddSingleton<IDataStore>(store);
                services.AddSingleton<ISalesDatabase>(database);
                services.RemoveAll<TimeProvider>();
                services.AddSingleton<TimeProvider>(new FakeTimeProvider(DateTimeOffset.Parse("2026-10-28T11:00:00Z")));
                services.AddSingleton<ISaleWriter, SqlSaleWriter>();
            });
        });

    private sealed class MemoryShopStore : IDataStore
    {
        private readonly ConcurrentDictionary<string, string> _files = new();
        public MemoryShopStore() => _files["shops.json"] = JsonSerializer.Serialize(
            new SimulatorConfig { Shops = [SalesTestData.Shop()] });
        public bool Exists(string name) => _files.ContainsKey(name);
        public string? Read(string name) => _files.GetValueOrDefault(name);
        public void Write(string name, string content) => _files[name] = content;
    }
}

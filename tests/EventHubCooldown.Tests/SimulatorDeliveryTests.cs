using System.Collections.Concurrent;
using ApiFactory.Models;
using ApiFactory.Services;
using ApiShop.Models;
using ApiShop.Services;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Time.Testing;

namespace EventHubCooldown.Tests;

public sealed class SimulatorDeliveryTests
{
    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task MachineKeepsLatestTelemetryAndCountsOnlyDeliveredEvents(bool delivered)
    {
        var publisher = new StubPublisher(delivered);
        var logs = new ConcurrentQueue<LogEntry>();
        var runner = new MachineRunner(
            new MachineDefinition { Id = "machine", Type = "scale", IntervalSeconds = 1 },
            publisher, new RecordingLogger<MachineRunner>(logs));

        try
        {
            runner.Start();
            await publisher.Called.Task.WaitAsync(TimeSpan.FromSeconds(5));
            await WaitUntilAsync(() => runner.LastPayload is not null &&
                (!delivered || runner.MessagesSent > 0));

            Assert.Equal(MachineState.Running, runner.CurrentState);
            Assert.Equal(delivered ? 1 : 0, runner.MessagesSent);
            Assert.NotNull(runner.LastPayload);
            Assert.DoesNotContain(logs, entry => entry.Level == LogLevel.Error);
        }
        finally
        {
            runner.Stop();
        }
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task ShopKeepsLatestSaleAndCountsOnlyDeliveredRevenue(bool delivered)
    {
        var publisher = new StubPublisher(delivered);
        var logs = new ConcurrentQueue<LogEntry>();
        var clock = new FakeTimeProvider(DateTimeOffset.Parse("2026-10-28T11:00:00Z"));
        var runner = new ShopRunner(new ShopDefinition
        {
            Id = "shop",
            Name = "Test shop",
            City = "Rome",
            CountryCode = "IT",
            Currency = "EUR",
            TimeZoneId = "Europe/Rome",
            MinItemPrice = 2,
            MaxItemPrice = 3,
            Flavors = ["Vanilla", "Chocolate", "Strawberry", "Lemon", "Pistachio", "Coffee"]
        }, publisher, new RecordingLogger<ShopRunner>(logs), clock);

        try
        {
            runner.Start();
            clock.Advance(TimeSpan.FromSeconds(runner.IntervalSeconds));
            await publisher.Called.Task.WaitAsync(TimeSpan.FromSeconds(5));
            await WaitUntilAsync(() => runner.LastSale is not null &&
                (!delivered || runner.SalesSent > 0 && runner.Revenue > 0));

            Assert.Equal(ShopState.Open, runner.State);
            Assert.NotNull(runner.LastSale);
            Assert.Equal(delivered ? 1 : 0, runner.SalesSent);
            Assert.Equal(delivered ? runner.LastSale.TotalPrice : 0, runner.Revenue);
            Assert.DoesNotContain(logs, entry => entry.Level == LogLevel.Error);
        }
        finally
        {
            runner.Stop();
        }
    }

    [Fact]
    public async Task ConsoleFallbackStillLogsAndReportsSuccess()
    {
        var logs = new ConcurrentQueue<LogEntry>();
        var factory = new ApiFactory.Services.ConsoleEventHubService(
            new RecordingLogger<ApiFactory.Services.ConsoleEventHubService>(logs));
        var shop = new ConsoleSaleWriter(new RecordingLogger<ConsoleSaleWriter>(logs));

        Assert.True(await factory.SendAsync("machine", new Dictionary<string, object>()));
        Assert.True(await shop.WriteAsync(SalesTestData.Shop(), new SaleEvent
        {
            EventType = "sale", TransactionId = "transaction", ShopId = "shop", ShopName = "Test",
            City = "Rome", CountryCode = "IT", Currency = "EUR", TimestampUtc = "now",
            TimestampLocal = "now", ServingType = "cup", SalesChannel = "counter",
            PaymentMethod = "card", Weather = "sunny"
        }));
        Assert.Equal(2, logs.Count);
        Assert.Contains(logs, log => log.Message.Contains("[EventHub]"));
        Assert.Contains(logs, log => log.Message.Contains("[Sale]"));
    }

    private static async Task WaitUntilAsync(Func<bool> condition)
    {
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        while (!condition())
            await Task.Delay(10, timeout.Token);
    }

    private sealed class StubPublisher(bool delivered) :
        ApiFactory.Services.IEventHubService, ISaleWriter
    {
        public TaskCompletionSource Called { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);

        public Task<bool> SendAsync(string machineId, Dictionary<string, object> payload, CancellationToken ct = default)
            => Send();

        public Task<bool> WriteAsync(ShopDefinition shop, SaleEvent sale, CancellationToken ct = default)
            => Send();

        public Task<CatalogValidationResult> ValidateConfigurationAsync(ApiShop.Models.SimulatorConfig config, CancellationToken ct = default)
            => Task.FromResult(new CatalogValidationResult(true, []));

        private Task<bool> Send()
        {
            Called.TrySetResult();
            return Task.FromResult(delivered);
        }
    }
}

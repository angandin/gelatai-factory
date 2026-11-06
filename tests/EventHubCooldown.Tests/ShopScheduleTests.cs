using System.Collections.Concurrent;
using System.Text.Json;
using ApiShop.Models;
using ApiShop.Services;
using Microsoft.Extensions.Time.Testing;

namespace EventHubCooldown.Tests;

public sealed class ShopScheduleTests
{
    [Theory]
    [InlineData("Europe/Rome", "2026-10-28T07:59:59Z", ShopState.OutsideHours)]
    [InlineData("Europe/Rome", "2026-10-28T08:00:00Z", ShopState.Open)]
    [InlineData("Europe/Rome", "2026-10-28T21:59:59Z", ShopState.Open)]
    [InlineData("Europe/Rome", "2026-10-28T22:00:00Z", ShopState.OutsideHours)]
    [InlineData("Europe/Paris", "2026-07-28T07:00:00Z", ShopState.Open)]
    [InlineData("America/New_York", "2026-10-28T12:59:59Z", ShopState.OutsideHours)]
    [InlineData("America/New_York", "2026-10-28T13:00:00Z", ShopState.Open)]
    [InlineData("America/New_York", "2026-10-29T03:00:00Z", ShopState.OutsideHours)]
    [InlineData("Asia/Tokyo", "2026-10-28T00:00:00Z", ShopState.Open)]
    [InlineData("Asia/Tokyo", "2026-10-28T14:00:00Z", ShopState.OutsideHours)]
    public void WorkHoursUseEachShopsTimeZoneAndExactBoundaries(
        string timeZoneId, string utcNow, ShopState expected)
    {
        var clock = new SchedulingClock(DateTimeOffset.Parse(utcNow));
        var shop = SalesTestData.Shop();
        shop.TimeZoneId = timeZoneId;
        var database = new TestSalesDatabase();
        var runner = CreateRunner(shop, database, clock);
        try
        {
            runner.Start();
            Assert.Equal(expected, runner.State);
            Assert.Equal(0, database.Attempts);
            Assert.Null(runner.LastSale);
            runner.SetRush(true);
            Assert.Equal(expected == ShopState.Open ? ShopState.Rush : ShopState.OutsideHours, runner.State);
        }
        finally
        {
            runner.Stop();
        }
    }

    [Theory]
    [InlineData(false, false)]
    [InlineData(true, false)]
    [InlineData(false, true)]
    public async Task EveryAttemptWaitsFiveToTenMinutesIncludingStartupRushAndFailures(bool rush, bool fail)
    {
        var clock = new SchedulingClock(DateTimeOffset.Parse("2026-10-28T09:00:00Z"));
        var database = new TestSalesDatabase
        {
            Failure = fail ? new TestDatabaseException("Unavailable") : null
        };
        var runner = CreateRunner(SalesTestData.Shop(), database, clock);
        try
        {
            runner.Start();
            runner.SetRush(rush);
            for (var attempt = 0; attempt < 20; attempt++)
            {
                var interval = runner.IntervalSeconds;
                Assert.InRange(interval, 300, 600);
                var timers = clock.TimersCreated;
                clock.Advance(TimeSpan.FromSeconds(interval) - TimeSpan.FromTicks(1));
                Assert.Equal(attempt, database.Attempts);
                clock.Advance(TimeSpan.FromTicks(1));
                await WaitUntilAsync(() => clock.TimersCreated > timers);
                Assert.Equal(attempt + 1, database.Attempts);
                Assert.Equal(fail ? 0 : attempt + 1, runner.SalesSent);
                Assert.NotNull(runner.LastSale);
                var local = DateTimeOffset.Parse(runner.LastSale.TimestampLocal);
                Assert.InRange(local.Hour, 9, 22);
            }
        }
        finally
        {
            runner.Stop();
        }
    }

    [Theory]
    [InlineData("2026-10-28T21:59:00Z", "2026-10-29T08:00:00Z")]
    [InlineData("2026-10-24T20:59:00Z", "2026-10-25T08:00:00Z")]
    [InlineData("2026-03-28T21:59:00Z", "2026-03-29T07:00:00Z")]
    public async Task ClosingSkipsPendingSaleAndReopensAtNineAcrossDaylightSavingChanges(
        string beforeClosing, string nextOpening)
    {
        var clock = new SchedulingClock(DateTimeOffset.Parse(beforeClosing));
        var database = new TestSalesDatabase();
        var runner = CreateRunner(SalesTestData.Shop(), database, clock);
        try
        {
            runner.Start();
            var timers = clock.TimersCreated;
            clock.Advance(TimeSpan.FromSeconds(runner.IntervalSeconds));
            await WaitUntilAsync(() => clock.TimersCreated > timers);
            Assert.Equal(ShopState.OutsideHours, runner.State);
            Assert.Equal(0, database.Attempts);
            Assert.Null(runner.LastSale);
            runner.SetRush(true);

            var opening = DateTimeOffset.Parse(nextOpening);
            clock.Advance(opening - clock.GetUtcNow() - TimeSpan.FromTicks(1));
            Assert.Equal(ShopState.OutsideHours, runner.State);
            Assert.Equal(0, database.Attempts);
            timers = clock.TimersCreated;
            clock.Advance(TimeSpan.FromTicks(1));
            await WaitUntilAsync(() => clock.TimersCreated > timers);
            Assert.Equal(ShopState.Rush, runner.State);
            Assert.Equal(0, database.Attempts);

            timers = clock.TimersCreated;
            clock.Advance(TimeSpan.FromSeconds(runner.IntervalSeconds));
            await WaitUntilAsync(() => clock.TimersCreated > timers);
            Assert.Equal(1, database.Attempts);
            Assert.Equal(9, DateTimeOffset.Parse(runner.LastSale!.TimestampLocal).Hour);
        }
        finally
        {
            runner.Stop();
        }
    }

    [Fact]
    public void ManualStopCancelsAnOvernightWaitAndDoesNotReopenAutomatically()
    {
        var clock = new SchedulingClock(DateTimeOffset.Parse("2026-10-28T23:00:00Z"));
        var database = new TestSalesDatabase();
        var runner = CreateRunner(SalesTestData.Shop(), database, clock);
        runner.Start();
        Assert.Equal(ShopState.OutsideHours, runner.State);
        runner.Stop();
        clock.Advance(TimeSpan.FromHours(12));
        Assert.Equal(ShopState.Closed, runner.State);
        Assert.Equal(0, database.Attempts);
    }

    [Fact]
    public void ManagerPersistsEnabledStateNotTemporaryOutsideHoursState()
    {
        var clock = new SchedulingClock(DateTimeOffset.Parse("2026-10-28T23:00:00Z"));
        var store = new StateStore();
        var logs = new ConcurrentQueue<LogEntry>();
        var writer = new SqlSaleWriter(new TestSalesDatabase(),
            new RecordingLogger<SqlSaleWriter>(logs), clock);
        var manager = new ShopSimulatorManager(writer,
            new RecordingLogger<ShopSimulatorManager>(logs), store, clock);
        manager.UpdateConfig(new SimulatorConfig { Shops = [SalesTestData.Shop()] });
        try
        {
            Assert.True(manager.StartShop("it-roma-001"));
            Assert.Equal(ShopState.OutsideHours, manager.GetShopStatus("it-roma-001")!.State);
            Assert.True(manager.SetRush("it-roma-001", true));
            var state = JsonSerializer.Deserialize<List<ShopPersistedState>>(store.Read("shop-state.json")!)!;
            Assert.Equal(ShopState.Rush, Assert.Single(state).State);
        }
        finally
        {
            manager.StopAll();
        }
    }

    private static ShopRunner CreateRunner(ShopDefinition shop, TestSalesDatabase database, TimeProvider clock)
    {
        var logs = new ConcurrentQueue<LogEntry>();
        var writer = new SqlSaleWriter(database, new RecordingLogger<SqlSaleWriter>(logs), clock);
        return new ShopRunner(shop, writer, new RecordingLogger<ShopRunner>(logs), clock);
    }

    private static async Task WaitUntilAsync(Func<bool> condition)
    {
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        while (!condition())
            await Task.Delay(1, timeout.Token);
    }

    private sealed class SchedulingClock(DateTimeOffset start) : FakeTimeProvider(start)
    {
        private int _timersCreated;
        public int TimersCreated => Volatile.Read(ref _timersCreated);

        public override ITimer CreateTimer(TimerCallback callback, object? state, TimeSpan dueTime, TimeSpan period)
        {
            var timer = base.CreateTimer(callback, state, dueTime, period);
            Interlocked.Increment(ref _timersCreated);
            return timer;
        }
    }

    private sealed class StateStore : IDataStore
    {
        private readonly Dictionary<string, string> _files = [];
        public bool Exists(string name) => _files.ContainsKey(name);
        public string? Read(string name) => _files.GetValueOrDefault(name);
        public void Write(string name, string content) => _files[name] = content;
    }
}

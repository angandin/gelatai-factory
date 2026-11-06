using System.Collections.Concurrent;
using ApiShop.Models;
using ApiShop.Services;
using Microsoft.Extensions.Logging;

namespace EventHubCooldown.Tests;

public sealed class SqlSaleWriterTests
{
    [Fact]
    public async Task EverySaleIsAttemptedWhileOnlyLogsAreThrottled()
    {
        var database = new TestSalesDatabase { Failure = new TestDatabaseException("SQL\nunavailable") };
        var logs = new ConcurrentQueue<LogEntry>();
        var clock = new ManualTimeProvider();
        var writer = new SqlSaleWriter(database, new RecordingLogger<SqlSaleWriter>(logs), clock);
        var shop = SalesTestData.Shop();
        var sale = SalesTestData.Sale();

        Assert.False(await writer.WriteAsync(shop, sale));
        clock.Advance(TimeSpan.FromMinutes(30) - TimeSpan.FromTicks(1));
        Assert.False(await writer.WriteAsync(shop, sale));
        Assert.Equal(2, database.Attempts);
        Assert.Single(logs);
        clock.Advance(TimeSpan.FromTicks(1));
        Assert.False(await writer.WriteAsync(shop, sale));
        Assert.Equal(2, logs.Count);
        database.Failure = null;
        Assert.True(await writer.WriteAsync(shop, sale));
        database.Failure = new TestDatabaseException("Off again");
        Assert.False(await writer.WriteAsync(shop, sale));
        Assert.Equal(5, database.Attempts);
        Assert.Equal(2, logs.Count);
        Assert.All(logs, entry =>
        {
            Assert.Equal(LogLevel.Error, entry.Level);
            Assert.Null(entry.Exception);
            Assert.DoesNotContain("\n", entry.Message);
        });
    }

    [Fact]
    public async Task RecoveryBeforeLogWindowExpiresDoesNotWaitOrResetTheWindow()
    {
        var database = new TestSalesDatabase { Failure = new TestDatabaseException("Offline") };
        var logs = new ConcurrentQueue<LogEntry>();
        var clock = new ManualTimeProvider();
        var writer = new SqlSaleWriter(database, new RecordingLogger<SqlSaleWriter>(logs), clock);
        var shop = SalesTestData.Shop();
        var sale = SalesTestData.Sale();

        Assert.False(await writer.WriteAsync(shop, sale));
        clock.Advance(TimeSpan.FromMinutes(1));
        database.Failure = null;
        Assert.True(await writer.WriteAsync(shop, sale));
        database.Failure = new TestDatabaseException("Offline again");
        Assert.False(await writer.WriteAsync(shop, sale));
        Assert.Equal(3, database.Attempts);
        Assert.Single(logs);
        clock.Advance(TimeSpan.FromMinutes(29));
        Assert.False(await writer.WriteAsync(shop, sale));
        Assert.Equal(2, logs.Count);
    }

    [Fact]
    public async Task ConcurrentFailedWritesAllRunAndLogOnce()
    {
        var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var database = new TestSalesDatabase
        {
            Failure = new TestDatabaseException("Offline"),
            BeforeWrite = ct => release.Task.WaitAsync(ct)
        };
        var logs = new ConcurrentQueue<LogEntry>();
        var writer = new SqlSaleWriter(database, new RecordingLogger<SqlSaleWriter>(logs), new ManualTimeProvider());
        var tasks = Enumerable.Range(0, 100)
            .Select(_ => writer.WriteAsync(SalesTestData.Shop(), SalesTestData.Sale())).ToArray();
        Assert.Equal(100, database.Attempts);
        release.SetResult();
        Assert.All(await Task.WhenAll(tasks), result => Assert.False(result));
        Assert.Single(logs);
    }

    [Fact]
    public async Task CancellationPropagatesWithoutBeingLogged()
    {
        var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var database = new TestSalesDatabase
        {
            BeforeWrite = async ct =>
            {
                entered.SetResult();
                await Task.Delay(Timeout.InfiniteTimeSpan, ct);
            }
        };
        var logs = new ConcurrentQueue<LogEntry>();
        var writer = new SqlSaleWriter(database, new RecordingLogger<SqlSaleWriter>(logs), new ManualTimeProvider());
        using var cancellation = new CancellationTokenSource();
        var task = writer.WriteAsync(SalesTestData.Shop(), SalesTestData.Sale(), cancellation.Token);
        await entered.Task.WaitAsync(TimeSpan.FromSeconds(5));
        cancellation.Cancel();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => task);
        Assert.Empty(logs);
        database.BeforeWrite = null;
        Assert.True(await writer.WriteAsync(SalesTestData.Shop(), SalesTestData.Sale()));
    }

    [Fact]
    public async Task CatalogValidationRejectsUnknownKeysAndDistinguishesUnavailability()
    {
        var database = new TestSalesDatabase();
        var logs = new ConcurrentQueue<LogEntry>();
        var writer = new SqlSaleWriter(database, new RecordingLogger<SqlSaleWriter>(logs), new ManualTimeProvider());
        var config = new SimulatorConfig { Shops = [SalesTestData.Shop()] };
        Assert.Empty((await writer.ValidateConfigurationAsync(config)).Errors);
        config.Shops[0].Flavors[0] = "Unregistered";
        Assert.Single((await writer.ValidateConfigurationAsync(config)).Errors);
        config.Shops[0].Id = "unknown";
        Assert.Single((await writer.ValidateConfigurationAsync(config)).Errors);
        database.Failure = new TestDatabaseException("SQL offline");
        Assert.False((await writer.ValidateConfigurationAsync(config)).IsAvailable);
        Assert.Single(logs);
    }
}

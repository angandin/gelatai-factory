using System.Net.Sockets;
using System.Security.Authentication;
using Microsoft.Extensions.Logging;

namespace EventHubCooldown.Tests;

public sealed class PublisherCooldownTests
{
    [Fact]
    public async Task FailureSuppressesOnlyLogsUntilExactlyThirtyMinutes()
    {
        await using var harness = new PublisherHarness();
        harness.Producer.Failure = new SocketException((int)SocketError.HostNotFound);

        Assert.False(await harness.SendAsync("failed"));
        Assert.False(await harness.SendAsync("failed-1"));
        harness.Clock.Advance(TimeSpan.FromMinutes(30) - TimeSpan.FromTicks(1));
        Assert.False(await harness.SendAsync("failed-2"));
        Assert.Equal(3, harness.Producer.CreateCalls);
        Assert.Equal(3, harness.Producer.SendCalls);
        Assert.Single(harness.Logs);

        harness.Clock.Advance(TimeSpan.FromTicks(1));
        Assert.False(await harness.SendAsync("failed-at-boundary"));
        Assert.Equal(2, harness.Logs.Count);
        harness.Producer.Failure = null;
        Assert.True(await harness.SendAsync("recovered"));
        Assert.True(await harness.SendAsync("normal"));
        Assert.Equal(6, harness.Producer.SendCalls);
        Assert.Equal(["recovered", "normal"], harness.Producer.DeliveredIds.ToArray());
        Assert.Equal(2, harness.Logs.Count);
    }

    [Fact]
    public async Task RepeatedFailuresDoNotExtendTheErrorLoggingWindow()
    {
        await using var harness = new PublisherHarness();
        harness.Producer.Failure = new TimeoutException("Event Hub is off");

        for (var attempt = 1; attempt <= 3; attempt++)
        {
            Assert.False(await harness.SendAsync());
            Assert.Equal(attempt * 2 - 1, harness.Producer.SendCalls);
            Assert.Equal(attempt, harness.Logs.Count);
            harness.Clock.Advance(TimeSpan.FromMinutes(30) - TimeSpan.FromTicks(1));
            Assert.False(await harness.SendAsync());
            Assert.Equal(attempt * 2, harness.Producer.SendCalls);
            Assert.Equal(attempt, harness.Logs.Count);
            harness.Clock.Advance(TimeSpan.FromTicks(1));
        }
    }

    [Fact]
    public async Task ConcurrentSendersAllAttemptDeliveryButLogOnlyOncePerWindow()
    {
        await using var harness = new PublisherHarness();
        harness.Producer.Failure = new IOException("Event Hub unavailable");

        for (var attempt = 1; attempt <= 2; attempt++)
        {
            var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            var enteredCount = 0;
            harness.Producer.BeforeSend = async ct =>
            {
                if (Interlocked.Increment(ref enteredCount) == 50)
                    entered.SetResult();
                await release.Task.WaitAsync(ct);
            };

            var sends = Enumerable.Range(0, 50)
                .Select(index => harness.SendAsync($"sender-{index}")).ToArray();
            await entered.Task.WaitAsync(TimeSpan.FromSeconds(5));
            Assert.Equal(attempt * 50, harness.Producer.SendCalls);
            release.SetResult();
            var results = await Task.WhenAll(sends).WaitAsync(TimeSpan.FromSeconds(5));

            Assert.All(results, result => Assert.False(result));
            Assert.Equal(attempt * 50, harness.Producer.CreateCalls);
            Assert.Equal(attempt * 50, harness.Producer.SendCalls);
            Assert.Equal(attempt, harness.Logs.Count);
            harness.Clock.Advance(TimeSpan.FromMinutes(30));
        }
    }

    [Fact]
    public async Task BatchCreationFailuresOnlyThrottleLogging()
    {
        await using var harness = new PublisherHarness();
        harness.Producer.FailOnCreate = true;
        harness.Producer.Failure = new SocketException((int)SocketError.HostNotFound);

        Assert.False(await harness.SendAsync());
        Assert.False(await harness.SendAsync());
        Assert.Equal(2, harness.Producer.CreateCalls);
        Assert.Equal(0, harness.Producer.SendCalls);
        Assert.Single(harness.Logs);

        harness.Clock.Advance(TimeSpan.FromMinutes(30));
        harness.Producer.Failure = null;
        Assert.True(await harness.SendAsync());
    }

    [Fact]
    public async Task CancellationDuringSendDoesNotLogOrThrottleErrors()
    {
        await using var harness = new PublisherHarness();
        using var cancellation = new CancellationTokenSource();
        var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        harness.Producer.BeforeSend = async ct =>
        {
            entered.SetResult();
            await Task.Delay(Timeout.InfiniteTimeSpan, ct);
        };

        var send = harness.SendAsync(ct: cancellation.Token);
        await entered.Task.WaitAsync(TimeSpan.FromSeconds(5));
        cancellation.Cancel();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => send);

        Assert.Empty(harness.Logs);
        harness.Producer.BeforeSend = null;
        Assert.True(await harness.SendAsync());
        Assert.Equal(2, harness.Producer.SendCalls);
    }

    [Fact]
    public async Task CancellationOfOneConcurrentSendDoesNotAffectOtherSenders()
    {
        await using var harness = new PublisherHarness();
        var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        harness.Producer.BeforeSend = async ct =>
        {
            entered.TrySetResult();
            await release.Task.WaitAsync(ct);
        };

        var first = harness.SendAsync("first");
        await entered.Task.WaitAsync(TimeSpan.FromSeconds(5));
        using var cancellation = new CancellationTokenSource();
        var waiting = harness.SendAsync("cancelled", cancellation.Token);
        cancellation.Cancel();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => waiting);

        release.SetResult();
        Assert.True(await first.WaitAsync(TimeSpan.FromSeconds(5)));
        Assert.True(await harness.SendAsync("next"));
        Assert.Empty(harness.Logs);
        Assert.Equal(["first", "next"], harness.Producer.DeliveredIds.ToArray());
    }

    [Fact]
    public async Task AlreadyCancelledTokenStillThrowsDuringLoggingWindow()
    {
        await using var harness = new PublisherHarness();
        harness.Producer.Failure = new TimeoutException();
        Assert.False(await harness.SendAsync());

        using var cancellation = new CancellationTokenSource();
        cancellation.Cancel();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(
            () => harness.SendAsync(ct: cancellation.Token));
        Assert.Single(harness.Logs);
        Assert.Equal(1, harness.Producer.SendCalls);
    }

    [Fact]
    public async Task UnexpectedErrorsPropagateWithoutThrottledLogging()
    {
        await using var harness = new PublisherHarness();
        harness.Producer.Failure = new InvalidOperationException("Programming error");

        await Assert.ThrowsAsync<InvalidOperationException>(() => harness.SendAsync());
        Assert.Empty(harness.Logs);
        harness.Producer.Failure = null;
        Assert.True(await harness.SendAsync());
    }

    [Fact]
    public async Task ErrorIsOneCompactLogWithoutExceptionOrNewlines()
    {
        await using var harness = new PublisherHarness();
        harness.Producer.Failure = new TimeoutException("Outer", new IOException("DNS\r\nfailure\n" + new string('x', 1000)));

        Assert.False(await harness.SendAsync());

        var log = Assert.Single(harness.Logs);
        Assert.Equal(LogLevel.Error, log.Level);
        Assert.Null(log.Exception);
        Assert.Contains("IOException", log.Message);
        Assert.Contains("DNS failure ", log.Message);
        Assert.Contains("30 minutes", log.Message);
        Assert.DoesNotContain("\r", log.Message);
        Assert.DoesNotContain("\n", log.Message);
        Assert.True(log.Message.Length < 700);
    }

    [Fact]
    public async Task SuccessfulPublishingPreservesEventProperties()
    {
        await using var harness = new PublisherHarness();

        Assert.True(await harness.SendAsync("sender"));
        var properties = Assert.Single(harness.Producer.DeliveredProperties);
        Assert.Equal("sender", properties["machine_id"]);
        Assert.Empty(harness.Logs);
    }

    [Fact]
    public async Task AuthenticationAndTimeoutFailuresOnlyThrottleLogging()
    {
        await using var harness = new PublisherHarness();
        Exception[] failures =
        [
            new Azure.Messaging.EventHubs.EventHubsException(false, "test-hub"),
            new AuthenticationException("Authentication failed"),
            new UnauthorizedAccessException("Access denied"),
            new Azure.RequestFailedException(503, "Unavailable"),
            new OperationCanceledException("Transport timeout")
        ];

        foreach (var failure in failures)
        {
            harness.Producer.Failure = failure;
            Assert.False(await harness.SendAsync());
            Assert.False(await harness.SendAsync());
            harness.Clock.Advance(TimeSpan.FromMinutes(30));
        }

        Assert.Equal(failures.Length * 2, harness.Producer.SendCalls);
        Assert.Equal(failures.Length, harness.Logs.Count);
    }

    [Fact]
    public async Task RecoveryIsImmediateAndDoesNotResetTheLoggingWindow()
    {
        await using var harness = new PublisherHarness();
        harness.Producer.Failure = new IOException("Event Hub is off");
        Assert.False(await harness.SendAsync());
        Assert.Single(harness.Logs);

        harness.Clock.Advance(TimeSpan.FromMinutes(5));
        harness.Producer.Failure = null;
        Assert.True(await harness.SendAsync("recovered-before-thirty-minutes"));
        Assert.Equal(["recovered-before-thirty-minutes"], harness.Producer.DeliveredIds.ToArray());

        harness.Producer.Failure = new IOException("Event Hub is off again");
        Assert.False(await harness.SendAsync());
        Assert.Single(harness.Logs);
        harness.Clock.Advance(TimeSpan.FromMinutes(25));
        Assert.False(await harness.SendAsync());
        Assert.Equal(2, harness.Logs.Count);
        Assert.Equal(4, harness.Producer.SendCalls);
    }
}

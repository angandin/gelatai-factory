using System.Collections.Concurrent;
using System.Text.Json;
using Azure.Messaging.EventHubs;
using Azure.Messaging.EventHubs.Producer;
using Microsoft.Extensions.Logging;
using FactoryPublisher = ApiFactory.Services.AzureEventHubService;

namespace EventHubCooldown.Tests;

internal sealed class PublisherHarness : IAsyncDisposable
{
    private readonly IAsyncDisposable _service;
    private readonly Func<string, CancellationToken, Task<bool>> _send;

    public TestProducer Producer { get; } = new();
    public ManualTimeProvider Clock { get; } = new();
    public ConcurrentQueue<LogEntry> Logs { get; } = new();

    public PublisherHarness()
    {
        var service = new FactoryPublisher(Producer, new RecordingLogger<FactoryPublisher>(Logs), Clock);
        _service = service;
        _send = (id, ct) => service.SendAsync(id, new Dictionary<string, object> { ["id"] = id }, ct);
    }

    public Task<bool> SendAsync(string id = "test", CancellationToken ct = default) => _send(id, ct);

    public ValueTask DisposeAsync() => _service.DisposeAsync();

}

internal sealed class ManualTimeProvider : TimeProvider
{
    private long _timestamp;

    public override long TimestampFrequency => TimeSpan.TicksPerSecond;
    public override long GetTimestamp() => Interlocked.Read(ref _timestamp);
    public void Advance(TimeSpan interval) => Interlocked.Add(ref _timestamp, interval.Ticks);
}

internal sealed class TestProducer : EventHubProducerClient
{
    private int _createCalls;
    private int _sendCalls;
    private readonly ConcurrentDictionary<EventDataBatch, List<EventData>> _batchEvents = new();

    public int CreateCalls => Volatile.Read(ref _createCalls);
    public int SendCalls => Volatile.Read(ref _sendCalls);
    public Exception? Failure { get; set; }
    public bool FailOnCreate { get; set; }
    public bool AcceptEvents { get; set; } = true;
    public Func<CancellationToken, Task>? BeforeSend { get; set; }
    public ConcurrentQueue<string> DeliveredIds { get; } = new();
    public ConcurrentQueue<IReadOnlyDictionary<string, object>> DeliveredProperties { get; } = new();

    public override ValueTask<EventDataBatch> CreateBatchAsync(CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        Interlocked.Increment(ref _createCalls);
        if (FailOnCreate && Failure is not null)
            throw Failure;

        var events = new List<EventData>();
        var batch = EventHubsModelFactory.EventDataBatch(
            1_000_000, events, tryAddCallback: _ => AcceptEvents);
        _batchEvents[batch] = events;
        return ValueTask.FromResult(batch);
    }

    public override async Task SendAsync(EventDataBatch eventBatch, CancellationToken cancellationToken = default)
    {
        Interlocked.Increment(ref _sendCalls);
        if (BeforeSend is not null)
            await BeforeSend(cancellationToken);

        cancellationToken.ThrowIfCancellationRequested();
        if (Failure is not null)
            throw Failure;

        foreach (var item in _batchEvents[eventBatch])
        {
            var properties = new Dictionary<string, object>(item.Properties);
            DeliveredProperties.Enqueue(properties);
            var idProperty = properties.ContainsKey("machine_id") ? "machine_id" : "shop_id";
            DeliveredIds.Enqueue((string)properties[idProperty]);
            using var json = JsonDocument.Parse(item.EventBody.ToMemory());
            Assert.Equal(JsonValueKind.Object, json.RootElement.ValueKind);
        }
    }

    public override ValueTask DisposeAsync() => ValueTask.CompletedTask;
}

internal sealed record LogEntry(LogLevel Level, string Message, Exception? Exception);

internal sealed class RecordingLogger<T>(ConcurrentQueue<LogEntry> entries) : ILogger<T>
{
    public IDisposable? BeginScope<TState>(TState state) where TState : notnull => null;
    public bool IsEnabled(LogLevel logLevel) => logLevel >= LogLevel.Information;

    public void Log<TState>(
        LogLevel logLevel, EventId eventId, TState state,
        Exception? exception, Func<TState, Exception?, string> formatter)
    {
        if (IsEnabled(logLevel))
            entries.Enqueue(new LogEntry(logLevel, formatter(state, exception), exception));
    }
}

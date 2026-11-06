using System.Net.Sockets;
using System.Security.Authentication;
using Azure.Messaging.EventHubs;
using Azure.Messaging.EventHubs.Producer;

namespace ApiFactory.Services;

/// <summary>
/// Abstraction for sending telemetry to Event Hub.
/// Implementations can target Azure Event Hubs or a local console stub.
/// </summary>
public interface IEventHubService
{
    Task<bool> SendAsync(string machineId, Dictionary<string, object> payload, CancellationToken ct = default);
}

/// <summary>
/// Stub implementation that logs payloads to console.
/// Used when no Event Hub connection string is configured.
/// </summary>
public class ConsoleEventHubService : IEventHubService
{
    private readonly ILogger<ConsoleEventHubService> _logger;

    public ConsoleEventHubService(ILogger<ConsoleEventHubService> logger)
    {
        _logger = logger;
    }

    public Task<bool> SendAsync(string machineId, Dictionary<string, object> payload, CancellationToken ct = default)
    {
        _logger.LogInformation("[EventHub] {MachineId}: {Payload}",
            machineId, System.Text.Json.JsonSerializer.Serialize(payload));
        return Task.FromResult(true);
    }
}

/// <summary>
/// Real Azure Event Hubs implementation that sends JSON payloads.
/// </summary>
public class AzureEventHubService : IEventHubService, IAsyncDisposable
{
    private static readonly TimeSpan ErrorLogCooldown = TimeSpan.FromMinutes(30);
    private readonly EventHubProducerClient _producer;
    private readonly ILogger<AzureEventHubService> _logger;
    private readonly TimeProvider _timeProvider;
    private readonly object _errorLogLock = new();
    private long? _lastErrorLoggedAt;

    public AzureEventHubService(string connectionString, string eventHubName, ILogger<AzureEventHubService> logger)
        : this(new EventHubProducerClient(connectionString, eventHubName), logger, TimeProvider.System)
    {
    }

    public AzureEventHubService(
        EventHubProducerClient producer,
        ILogger<AzureEventHubService> logger,
        TimeProvider timeProvider)
    {
        _producer = producer;
        _logger = logger;
        _timeProvider = timeProvider;
    }

    public async Task<bool> SendAsync(string machineId, Dictionary<string, object> payload, CancellationToken ct = default)
    {
        ct.ThrowIfCancellationRequested();
        var json = System.Text.Json.JsonSerializer.Serialize(payload);
        try
        {
            using var batch = await _producer.CreateBatchAsync(ct);
            var eventData = new EventData(System.Text.Encoding.UTF8.GetBytes(json));
            eventData.Properties["machine_id"] = machineId;

            if (!batch.TryAdd(eventData))
            {
                _logger.LogWarning("Event too large for batch, machine={MachineId}", machineId);
                return false;
            }

            await _producer.SendAsync(batch, ct);
            _logger.LogDebug("Sent telemetry for {MachineId} to Event Hub", machineId);
            return true;
        }
        catch (Exception ex) when (!ct.IsCancellationRequested &&
            ex is EventHubsException or SocketException or IOException or TimeoutException
                or Azure.RequestFailedException or UnauthorizedAccessException
                or AuthenticationException or OperationCanceledException)
        {
            lock (_errorLogLock)
            {
                if (_lastErrorLoggedAt is not long loggedAt ||
                    _timeProvider.GetElapsedTime(loggedAt) >= ErrorLogCooldown)
                {
                    _lastErrorLoggedAt = _timeProvider.GetTimestamp();
                    var error = ex.GetBaseException();
                    var message = error.Message.ReplaceLineEndings(" ");
                    _logger.LogError(
                        "Event Hub send failed ({ErrorType}): {Message}. Sending continues; further send errors are not logged for 30 minutes.",
                        error.GetType().Name, message.Length > 512 ? message[..512] : message);
                }
            }
            return false;
        }
    }

    public ValueTask DisposeAsync() => _producer.DisposeAsync();
}

using Azure.Messaging.EventHubs;
using Azure.Messaging.EventHubs.Producer;

namespace ApiFactory.Services;

/// <summary>
/// Abstraction for sending telemetry to Event Hub.
/// Implementations can target Azure Event Hubs or a local console stub.
/// </summary>
public interface IEventHubService
{
    Task SendAsync(string machineId, Dictionary<string, object> payload, CancellationToken ct = default);
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

    public Task SendAsync(string machineId, Dictionary<string, object> payload, CancellationToken ct = default)
    {
        _logger.LogInformation("[EventHub] {MachineId}: {Payload}",
            machineId, System.Text.Json.JsonSerializer.Serialize(payload));
        return Task.CompletedTask;
    }
}

/// <summary>
/// Real Azure Event Hubs implementation that sends JSON payloads.
/// </summary>
public class AzureEventHubService : IEventHubService, IAsyncDisposable
{
    private readonly EventHubProducerClient _producer;
    private readonly ILogger<AzureEventHubService> _logger;

    public AzureEventHubService(string connectionString, string eventHubName, ILogger<AzureEventHubService> logger)
    {
        _producer = new EventHubProducerClient(connectionString, eventHubName);
        _logger = logger;
    }

    public async Task SendAsync(string machineId, Dictionary<string, object> payload, CancellationToken ct = default)
    {
        var json = System.Text.Json.JsonSerializer.Serialize(payload);
        using var batch = await _producer.CreateBatchAsync(ct);
        var eventData = new EventData(System.Text.Encoding.UTF8.GetBytes(json));
        eventData.Properties["machine_id"] = machineId;

        if (!batch.TryAdd(eventData))
        {
            _logger.LogWarning("Event too large for batch, machine={MachineId}", machineId);
            return;
        }

        await _producer.SendAsync(batch, ct);
        _logger.LogDebug("Sent telemetry for {MachineId} to Event Hub", machineId);
    }

    public async ValueTask DisposeAsync()
    {
        await _producer.DisposeAsync();
    }
}

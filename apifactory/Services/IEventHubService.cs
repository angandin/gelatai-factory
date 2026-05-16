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
/// Replace with Azure Event Hubs SDK implementation when ready.
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

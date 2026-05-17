using ApiFactory.Models;

namespace ApiFactory.Services;

/// <summary>
/// Runs a single machine simulation loop in a background Task.
/// Generates telemetry based on parameter ranges and sends to Event Hub.
/// </summary>
public class MachineRunner
{
    private readonly MachineDefinition _definition;
    private readonly IEventHubService _eventHub;
    private readonly ILogger _logger;
    private readonly Random _random = new();
    private CancellationTokenSource? _cts;
    private Task? _task;

    public MachineState CurrentState { get; private set; } = MachineState.Stopped;
    public string? ActiveAnomaly { get; private set; }
    public long MessagesSent { get; private set; }
    public Dictionary<string, object>? LastPayload { get; private set; }

    public MachineRunner(MachineDefinition definition, IEventHubService eventHub, ILogger logger)
    {
        _definition = definition;
        _eventHub = eventHub;
        _logger = logger;
    }

    public void Start()
    {
        _cts = new CancellationTokenSource();
        CurrentState = MachineState.Running;
        _task = Task.Run(() => RunLoop(_cts.Token));
    }

    public void Stop()
    {
        _cts?.Cancel();
        _task?.Wait(TimeSpan.FromSeconds(5));
        _cts?.Dispose();
        CurrentState = MachineState.Stopped;
        ActiveAnomaly = null;
    }

    public bool TriggerAnomaly(string anomalyName)
    {
        if (!_definition.AnomalyProfiles.ContainsKey(anomalyName))
            return false;

        ActiveAnomaly = anomalyName;
        CurrentState = MachineState.Anomaly;
        return true;
    }

    public void ClearAnomaly()
    {
        ActiveAnomaly = null;
        CurrentState = MachineState.Running;
    }

    private async Task RunLoop(CancellationToken ct)
    {
        _logger.LogInformation("Machine {Id} ({Type}) started, interval={Interval}s",
            _definition.Id, _definition.Type, _definition.IntervalSeconds);

        while (!ct.IsCancellationRequested)
        {
            try
            {
                var payload = GeneratePayload();
                LastPayload = payload;
                await _eventHub.SendAsync(_definition.Id, payload, ct);
                MessagesSent++;
            }
            catch (OperationCanceledException)
            {
                break;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Machine {Id} error sending telemetry", _definition.Id);
            }

            try
            {
                await Task.Delay(TimeSpan.FromSeconds(_definition.IntervalSeconds), ct);
            }
            catch (OperationCanceledException)
            {
                break;
            }
        }

        _logger.LogInformation("Machine {Id} stopped", _definition.Id);
    }

    private Dictionary<string, object> GeneratePayload()
    {
        // Decide which parameter ranges to use (normal vs anomaly)
        var activeRanges = _definition.Parameters;
        if (ActiveAnomaly != null &&
            _definition.AnomalyProfiles.TryGetValue(ActiveAnomaly, out var anomalyRanges))
        {
            // Merge: anomaly overrides normal for matching keys
            activeRanges = new Dictionary<string, ParameterRange>(_definition.Parameters);
            foreach (var (key, range) in anomalyRanges)
            {
                activeRanges[key] = range;
            }
        }

        // Build telemetry values
        var telemetry = new Dictionary<string, object>();
        foreach (var (paramName, range) in activeRanges)
        {
            telemetry[paramName] = Math.Round(range.Min + _random.NextDouble() * (range.Max - range.Min), 2);
        }

        telemetry["anomaly"] = ActiveAnomaly ?? "none";

        // Wrap in envelope with "payload" column
        var envelope = new Dictionary<string, object>
        {
            ["machine_id"] = _definition.Id,
            ["machine_type"] = _definition.Type,
            ["timestamp"] = DateTimeOffset.UtcNow.ToString("o"),
            ["state"] = CurrentState.ToString().ToLowerInvariant(),
            ["payload"] = telemetry
        };

        return envelope;
    }
}

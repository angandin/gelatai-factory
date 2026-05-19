using System.Collections.Concurrent;
using System.Text.Json;
using ApiFactory.Models;

namespace ApiFactory.Services;

/// <summary>
/// Manages the lifecycle of all machine simulators.
/// Each machine runs as an independent Task with its own CancellationToken.
/// </summary>
public class MachineSimulatorManager
{
    private readonly ConcurrentDictionary<string, MachineRunner> _runners = new();
    private readonly IEventHubService _eventHub;
    private readonly ILogger<MachineSimulatorManager> _logger;
    private SimulatorConfig _config = new();
    private readonly object _configLock = new();
    private string? _stateFilePath;
    private bool _suppressPersist;

    public MachineSimulatorManager(IEventHubService eventHub, ILogger<MachineSimulatorManager> logger)
    {
        _eventHub = eventHub;
        _logger = logger;
    }

    /// <summary>
    /// Set the path for persisting machine state (called once at startup).
    /// </summary>
    public void SetStateFilePath(string path) => _stateFilePath = path;

    /// <summary>
    /// Replace the entire machine configuration. Stops all running machines first.
    /// </summary>
    public void UpdateConfig(SimulatorConfig config)
    {
        lock (_configLock)
        {
            _suppressPersist = true;
            StopAll();
            _suppressPersist = false;
            _config = config;
        }
    }

    /// <summary>
    /// Get the current configuration.
    /// </summary>
    public SimulatorConfig GetConfig() => _config;

    /// <summary>
    /// Start a specific machine by ID.
    /// </summary>
    public bool StartMachine(string machineId)
    {
        var definition = _config.Machines.FirstOrDefault(m => m.Id == machineId);
        if (definition == null) return false;

        if (_runners.ContainsKey(machineId))
            return false; // already running

        var runner = new MachineRunner(definition, _eventHub, _logger);
        if (_runners.TryAdd(machineId, runner))
        {
            runner.Start();
            PersistState();
            return true;
        }
        return false;
    }

    /// <summary>
    /// Stop a specific machine by ID.
    /// </summary>
    public bool StopMachine(string machineId)
    {
        if (_runners.TryRemove(machineId, out var runner))
        {
            runner.Stop();
            PersistState();
            return true;
        }
        return false;
    }

    /// <summary>
    /// Start all configured machines and restore persisted state.
    /// </summary>
    public void StartAll()
    {
        _suppressPersist = true;
        foreach (var machine in _config.Machines)
        {
            StartMachine(machine.Id);
        }
        _suppressPersist = false;
        RestoreState();
    }

    /// <summary>
    /// Stop all running machines.
    /// </summary>
    public void StopAll()
    {
        foreach (var id in _runners.Keys.ToList())
        {
            StopMachine(id);
        }
    }

    /// <summary>
    /// Trigger an anomaly on a running machine.
    /// </summary>
    public bool TriggerAnomaly(string machineId, string anomalyName)
    {
        if (_runners.TryGetValue(machineId, out var runner))
        {
            var result = runner.TriggerAnomaly(anomalyName);
            if (result) PersistState();
            return result;
        }
        return false;
    }

    /// <summary>
    /// Clear anomaly on a running machine, returning to normal operation.
    /// </summary>
    public bool ClearAnomaly(string machineId)
    {
        if (_runners.TryGetValue(machineId, out var runner))
        {
            runner.ClearAnomaly();
            PersistState();
            return true;
        }
        return false;
    }

    /// <summary>
    /// Add 30 seconds to each machine's base interval (demo slowdown).
    /// </summary>
    public void Slowdown()
    {
        foreach (var runner in _runners.Values)
        {
            runner.IntervalSeconds = runner.BaseIntervalSeconds + 30;
        }
    }

    /// <summary>
    /// Reset all machines to their original base interval.
    /// </summary>
    public void NormalSpeed()
    {
        foreach (var runner in _runners.Values)
        {
            runner.IntervalSeconds = runner.BaseIntervalSeconds;
        }
    }

    /// <summary>
    /// Check whether the simulator is currently in slowdown mode.
    /// </summary>
    public bool IsSlowedDown()
    {
        var firstRunner = _runners.Values.FirstOrDefault();
        if (firstRunner == null) return false;
        return firstRunner.IntervalSeconds > firstRunner.BaseIntervalSeconds;
    }

    /// <summary>
    /// Get status of all machines (configured + running state).
    /// </summary>
    public List<MachineStatus> GetAllStatus()
    {
        return _config.Machines.Select(m =>
        {
            var isRunning = _runners.TryGetValue(m.Id, out var runner);
            return new MachineStatus
            {
                Id = m.Id,
                Type = m.Type,
                State = isRunning ? runner!.CurrentState : MachineState.Stopped,
                ActiveAnomaly = isRunning ? runner!.ActiveAnomaly : null,
                IntervalSeconds = m.IntervalSeconds,
                MessagesSent = isRunning ? runner!.MessagesSent : 0
            };
        }).ToList();
    }

    /// <summary>
    /// Get status of a single machine.
    /// </summary>
    public MachineStatus? GetMachineStatus(string machineId)
    {
        var definition = _config.Machines.FirstOrDefault(m => m.Id == machineId);
        if (definition == null) return null;

        var isRunning = _runners.TryGetValue(machineId, out var runner);
        return new MachineStatus
        {
            Id = definition.Id,
            Type = definition.Type,
            State = isRunning ? runner!.CurrentState : MachineState.Stopped,
            ActiveAnomaly = isRunning ? runner!.ActiveAnomaly : null,
            IntervalSeconds = definition.IntervalSeconds,
            MessagesSent = isRunning ? runner!.MessagesSent : 0
        };
    }

    /// <summary>
    /// Get the latest telemetry payload for a machine.
    /// </summary>
    public Dictionary<string, object>? GetLatestTelemetry(string machineId)
    {
        if (_runners.TryGetValue(machineId, out var runner))
        {
            return runner.LastPayload;
        }
        return null;
    }

    /// <summary>
    /// Persist current machine states to disk.
    /// </summary>
    private void PersistState()
    {
        if (_stateFilePath == null || _suppressPersist) return;
        try
        {
            var states = _runners.Select(kv => new MachinePersistedState
            {
                Id = kv.Key,
                State = kv.Value.CurrentState,
                ActiveAnomaly = kv.Value.ActiveAnomaly
            }).ToList();
            var json = JsonSerializer.Serialize(states, new JsonSerializerOptions { WriteIndented = true });
            File.WriteAllText(_stateFilePath, json);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to persist machine state");
        }
    }

    /// <summary>
    /// Restore machine states from disk after StartAll.
    /// </summary>
    public void RestoreState()
    {
        if (_stateFilePath == null || !File.Exists(_stateFilePath)) return;
        try
        {
            var json = File.ReadAllText(_stateFilePath);
            var states = JsonSerializer.Deserialize<List<MachinePersistedState>>(json,
                new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
            if (states == null) return;

            foreach (var s in states)
            {
                if (s.State == MachineState.Stopped && _runners.ContainsKey(s.Id))
                {
                    StopMachine(s.Id);
                }
                else if (s.State == MachineState.Anomaly && !string.IsNullOrEmpty(s.ActiveAnomaly))
                {
                    if (_runners.TryGetValue(s.Id, out var runner))
                    {
                        runner.TriggerAnomaly(s.ActiveAnomaly);
                    }
                }
            }
            _logger.LogInformation("Restored machine states from {Path}", _stateFilePath);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to restore machine state");
        }
    }
}

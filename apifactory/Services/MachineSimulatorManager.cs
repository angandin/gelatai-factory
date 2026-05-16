using System.Collections.Concurrent;
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

    public MachineSimulatorManager(IEventHubService eventHub, ILogger<MachineSimulatorManager> logger)
    {
        _eventHub = eventHub;
        _logger = logger;
    }

    /// <summary>
    /// Replace the entire machine configuration. Stops all running machines first.
    /// </summary>
    public void UpdateConfig(SimulatorConfig config)
    {
        lock (_configLock)
        {
            StopAll();
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
            return true;
        }
        return false;
    }

    /// <summary>
    /// Start all configured machines.
    /// </summary>
    public void StartAll()
    {
        foreach (var machine in _config.Machines)
        {
            StartMachine(machine.Id);
        }
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
            return runner.TriggerAnomaly(anomalyName);
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
            return true;
        }
        return false;
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
}

namespace ApiFactory.Models;

/// <summary>
/// Definition of a single machine in the factory simulator.
/// </summary>
public class MachineDefinition
{
    public required string Id { get; set; }
    public required string Type { get; set; }
    public int IntervalSeconds { get; set; } = 5;
    public Dictionary<string, ParameterRange> Parameters { get; set; } = new();
    public Dictionary<string, Dictionary<string, ParameterRange>> AnomalyProfiles { get; set; } = new();
}

/// <summary>
/// A numeric range used for generating simulated telemetry values.
/// </summary>
public class ParameterRange
{
    public double Min { get; set; }
    public double Max { get; set; }
}

/// <summary>
/// The full simulator configuration pushed via API.
/// </summary>
public class SimulatorConfig
{
    public List<MachineDefinition> Machines { get; set; } = new();
}

/// <summary>
/// Runtime state of a single machine.
/// </summary>
public enum MachineState
{
    Stopped,
    Running,
    Anomaly
}

/// <summary>
/// Status information for a machine (returned by status endpoints).
/// </summary>
public class MachineStatus
{
    public required string Id { get; set; }
    public required string Type { get; set; }
    public MachineState State { get; set; }
    public string? ActiveAnomaly { get; set; }
    public int IntervalSeconds { get; set; }
    public long MessagesSent { get; set; }
}

/// <summary>
/// Persisted state for a machine (saved to disk for restart recovery).
/// </summary>
public class MachinePersistedState
{
    public required string Id { get; set; }
    public MachineState State { get; set; }
    public string? ActiveAnomaly { get; set; }
}

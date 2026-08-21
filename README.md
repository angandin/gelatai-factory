# Ice Cream Factory Builder

A browser-based factory builder game with a real-time telemetry simulator backend. Design ice cream production lines, place machines, and monitor their status — all served from a single .NET app deployable to Azure Container Apps.

## Architecture

- **Frontend**: HTML5 Canvas game (`apifactory/wwwroot/index.html`) — pure JavaScript, no frameworks
- **Backend**: ASP.NET Core Minimal API (.NET 10) — machine simulator with telemetry generation
- **Telemetry**: Azure Event Hubs integration (optional, falls back to console logging)
- **Persistence**: Server-side save/load via Azure Files volume mount
- **Infrastructure**: Bicep templates for Azure Container Apps deployment

## How to Run (Local)

```bash
cd apifactory
(dotnet build --no-incremental // if need to rebuild everything)
dotnet run
```

Open `http://localhost:5000` in your browser.

## Controls

| Input | Action |
|-------|--------|
| Left Click | Place selected element |
| Right Click | Delete element |
| 1-4 | Select belt direction (→ ← ↓ ↑) |
| R | Rotate belt direction |
| Space | Pause / Resume simulation |
| Scroll Wheel | Zoom in / out |
| Middle Mouse + Drag | Pan camera |
| Arrow Keys | Pan camera |

## Machine Types

Each machine has unique telemetry parameters and anomaly profiles:

| Machine | Size | Key Telemetry |
|---------|------|---------------|
| Scale | 1×1 | weight, tare, stability |
| Mixer | 2×2 | rpm, temperature, torque |
| Pasteurizer | 2×2 | temperature, pressure, flow rate |
| Mix Cooker | 2×2 | temperature, stirring rpm, viscosity |
| Homogenizer | 2×1 | pressure bar, flow rate, particle size |
| Aging Tank | 2×3 | temperature, agitation rpm, level % |
| Batch Freezer | 2×2 | temperature, dasher rpm, overrun % |
| Blast Freezer | 2×4 | temperature, air speed, core temp |
| Storage Freezer | 3×3 | temperature, humidity, door status |
| Cold Room | 4×4 | temperature, humidity, occupancy % |

When placed, each machine gets a unique ID (`type-xxxxx`, e.g. `pasteurizer-k7f2a`).

## Anomalies by Machine Type

| Machine Type | Anomaly | Affected Parameters |
|--------------|---------|---------------------|
| Scale | drift | weight_kg, stability |
| Mixer | blade_jam | rpm, torque_nm |
| Mixer | overheating | temperature |
| Mix Cooker | burn | temperature |
| Mix Cooker | stall | stirring_rpm |
| Pasteurizer | overheating | temperature |
| Pasteurizer | pressure_drop | pressure |
| Homogenizer | valve_failure | pressure_bar, particle_size_um |
| Aging Tank | temp_rise | temperature |
| Aging Tank | overflow | level_pct |
| Blast Freezer | compressor_fail | temperature, air_speed_ms |
| Storage Freezer | door_stuck | door_open, temperature |
| Cold Room | defrost_failure | temperature |
| Cold Room | overload | occupancy_pct |
| Batch Freezer | motor_failure | dasher_rpm |
| Batch Freezer | freeze_lock | temperature |

## Game Layout

- **Left panel**: Tool palette (belts, machines, start/end points) with Save/Load buttons
- **Center**: 64×64 tile canvas with zoom/pan
- **Right panel**: Live machine status from the API with Start/Stop/Anomaly controls

## How It Works

1. **Place a Start Point** — raw materials spawn here every 2 seconds
2. **Build Conveyor Belts** — materials follow belt directions with smooth movement
3. **Place Machines** — materials enter, get processed, and exit to all connected output belts
4. **Place an End Point** — finished materials are consumed here

Materials transform through 4 stages as they pass through machines:
- Stage 0: Raw milk (white)
- Stage 1: Mixed cream (yellow)
- Stage 2: Ice cream scoop (pink)
- Stage 3: Packaged product (blue box)

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/simulator/config` | Set machine configuration (auto-saved to disk) |
| GET | `/simulator/status` | All machine statuses |
| POST | `/simulator/{id}/start` | Start a machine |
| POST | `/simulator/{id}/stop` | Stop a machine |
| POST | `/simulator/{id}/anomaly/{name}` | Trigger anomaly |
| POST | `/simulator/{id}/clear-anomaly` | Clear anomaly |
| GET | `/simulator/{id}/telemetry` | Latest telemetry payload |
| POST | `/game/layout` | Save game layout |
| GET | `/game/layout` | Load game layout |

## Azure Deployment

The app deploys to Azure Container Apps with persistent storage via Azure Files.

```bash
# Build & push image
az acr build --registry <acr-name> --image apifactory:latest ./apifactory

# Deploy infrastructure
az deployment group create -g <resource-group> -f infra/main.bicep \
  --parameters containerImage='<acr-name>.azurecr.io/apifactory:latest'
```

The Bicep template (`infra/main.bicep`) provisions:
- Storage Account + File Share (mounted at `/app/data`)
- Container App Environment with Log Analytics
- Container App with Azure Files volume for persistent saves (single replica for in-memory state consistency)
- Optional Event Hub connection via secrets

## Customizing for a Different Factory Type

This solution was designed to be re-skinnable. The "ice cream factory" is just one theme — you can adapt it to manufacturing, automotive, retail, pharma, or any other domain by changing three things:

### 1. Machine Definitions (Backend)

Edit `apifactory/machines.json` to define your machine fleet. Each machine needs:

```json
{
  "Id": "robot-arm-abc12",
  "Type": "robot_arm",
  "IntervalSeconds": 5,
  "Parameters": {
    "joint_angle_deg": { "Min": 0, "Max": 180 },
    "payload_kg": { "Min": 0, "Max": 50 }
  },
  "AnomalyProfiles": {
    "servo_fault": {
      "joint_angle_deg": { "Min": 0, "Max": 5 },
      "payload_kg": { "Min": 60, "Max": 80 }
    }
  }
}
```

- **Type** — a slug used as the machine identifier (e.g. `robot_arm`, `cnc_mill`, `checkout_lane`)
- **Parameters** — the telemetry values the machine emits each interval (normal operating range)
- **AnomalyProfiles** — named failure modes; when triggered, parameter values shift to the anomaly range

### 2. Machine Templates (Frontend)

In `apifactory/wwwroot/index.html`, the `MACHINE_TEMPLATES` object defines how each machine appears in the game:

```javascript
const MACHINE_TEMPLATES = {
  [CellType.ROBOT_ARM]: {
    name: 'Robot Arm',
    typeId: 'robot_arm',        // must match the Type in machines.json
    size: [2, 2],               // grid footprint (width × height in tiles)
    interval: 5,
    color: ['#6478a0','#3c506e','#64b4b4'],  // [body, border, gear accent]
    parameters: { /* same as machines.json */ },
    anomalyProfiles: { /* same as machines.json */ }
  }
};
```

You also need to add a matching entry in the `CellType` enum and the `MACHINE_TYPES` array at the top of the file.

### 3. Visual Rendering (Frontend)

The `drawMachine()` function in `index.html` renders all machines using the same generic style: a colored rectangle with a central gear circle, a name label, and a progress bar. The three-color palette in `color` controls the look:

| Color Index | Purpose |
|-------------|---------|
| 0 | Body fill |
| 1 | Border / inner panel |
| 2 | Gear/accent circle |

If you want machine-specific icons (e.g., a robotic arm silhouette), extend `drawMachine()` with a `switch` on machine type and add custom canvas drawing.

### Quick Adaptation Checklist

1. **Choose your domain** — list the machines/stations relevant to your factory
2. **Define telemetry parameters** — what each machine measures (temperature, pressure, RPM, cycle count, etc.)
3. **Define anomaly profiles** — realistic failure modes with out-of-range parameter values
4. **Update `machines.json`** — add all machine definitions with unique IDs
5. **Update `MACHINE_TEMPLATES`** — add frontend entries with name, size, and color palette
6. **Update `CellType` and `MACHINE_TYPES`** — register new cell types in the enum and array
7. **(Optional)** Customize `drawMachine()` for domain-specific icons

### Example Domains

| Domain | Example Machines | Example Anomalies |
|--------|-----------------|-------------------|
| Automotive | Robot Arm, Paint Booth, Welding Station, Press | servo_fault, overspray, arc_failure |
| Manufacturing | CNC Mill, Lathe, 3D Printer, Conveyor | tool_wear, spindle_jam, nozzle_clog |
| Retail | Checkout Lane, Refrigerator, Shelf Scanner | scanner_error, compressor_fail, stockout |
| Pharma | Reactor, Centrifuge, Lyophilizer, Fill Line | contamination, imbalance, vacuum_loss |

## GelatAI Factory
<img width="2308" height="1409" alt="gelatai_factory" src="https://github.com/user-attachments/assets/af8e7cfd-b1f5-4b65-beb2-f5b74a83b96e" />

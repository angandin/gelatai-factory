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

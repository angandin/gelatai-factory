# Ice Cream Factory Builder

A top-down pixel art factory builder game where you design your own ice cream production line.

## How to Run

```bash
pip install pygame
python main.py
```

## Controls

| Key | Action |
|-----|--------|
| 1 | Select Conveyor Belt (Right →) |
| 2 | Select Conveyor Belt (Left ←) |
| 3 | Select Conveyor Belt (Down ↓) |
| 4 | Select Conveyor Belt (Up ↑) |
| 5 | Select Machine (2x2 block) |
| 6 | Select Start Point (spawner) |
| 7 | Select End Point (consumer) |
| R | Rotate conveyor direction |
| Left Click | Place selected element |
| Right Click | Delete element |
| Space | Pause / Resume simulation |
| Scroll Wheel | Zoom in / out |
| Middle Mouse + Drag | Pan camera |
| Arrow Keys | Pan camera |
| ESC | Quit |

## How It Works

1. **Place a Start Point** (key 6) — raw materials spawn here
2. **Build Conveyor Belts** (keys 1-4) — materials follow the belt direction with smooth movement
3. **Place Machines** (key 5) — 2x2 blocks that process materials (input from left side, output from right side)
4. **Place an End Point** (key 7) — materials disappear when they reach here

Materials transform through stages as they pass through machines:
- Stage 0: Raw milk (white blob)
- Stage 1: Mixed cream (yellow)
- Stage 2: Ice cream scoop (pink with sprinkles)
- Stage 3: Packaged ice cream (blue box)

## Grid

The factory grid is 64×64 tiles. Each tile is 32×32 pixels.

## Replacing Sprites

All sprites are generated programmatically in `sprites.py`. Replace any function with your own pixel art by returning a `pygame.Surface` of the appropriate size (32×32 for tiles, 64×64 for machines).

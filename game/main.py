"""
Ice Cream Factory - Top-down pixel art factory builder
Build conveyor belts, machines, start/end points to process materials.

Controls:
    - Left Click: Place selected element
    - Right Click: Delete element
    - 1: Select Conveyor Belt (Right)
    - 2: Select Conveyor Belt (Left)  
    - 3: Select Conveyor Belt (Down)
    - 4: Select Conveyor Belt (Up)
    - 5: Select Machine 1 (2x2)
    - 6: Select Machine 2 (2x1)
    - 7: Select Machine 3 (2x4)
    - 8: Select Start Point
    - 9: Select End Point
    - R: Rotate conveyor direction
    - Space: Pause/Resume simulation
    - Scroll: Zoom in/out
    - Middle Mouse / Arrow Keys: Pan camera
    - ESC: Quit
"""
import pygame
import sys
import asyncio
from enum import Enum, auto
from dataclasses import dataclass, field
from typing import Optional
import sprites

# --- Constants ---
TILE_SIZE = sprites.TILE_SIZE
GRID_WIDTH = 64
GRID_HEIGHT = 64
SCREEN_WIDTH = 1280
SCREEN_HEIGHT = 720
FPS = 60
MATERIAL_SPEED = 1.5  # tiles per second
MACHINE_PROCESS_TIME = 2.0  # seconds
SPAWN_INTERVAL = 2.0  # seconds between spawns

# UI Panel
UI_PANEL_WIDTH = 200


class CellType(Enum):
    EMPTY = auto()
    CONVEYOR_RIGHT = auto()
    CONVEYOR_LEFT = auto()
    CONVEYOR_DOWN = auto()
    CONVEYOR_UP = auto()
    MACHINE_1 = auto()  # 2x2 machine (top-left anchor)
    MACHINE_2 = auto()  # 2x1 machine (left anchor)
    MACHINE_3 = auto()  # 2x4 machine (top-left anchor)
    MACHINE_PART = auto()  # non-anchor cells of a multi-cell machine
    START_POINT = auto()
    END_POINT = auto()
    RECYCLE = auto()  # delete tool (not placed on grid)


# Machine dimensions (width_in_tiles, height_in_tiles)
MACHINE_SIZES = {
    CellType.MACHINE_1: (2, 2),
    CellType.MACHINE_2: (2, 1),
    CellType.MACHINE_3: (2, 4),
}

MACHINE_TYPES = (CellType.MACHINE_1, CellType.MACHINE_2, CellType.MACHINE_3)


CONVEYOR_DIRECTIONS = {
    CellType.CONVEYOR_RIGHT: (1, 0),
    CellType.CONVEYOR_LEFT: (-1, 0),
    CellType.CONVEYOR_DOWN: (0, 1),
    CellType.CONVEYOR_UP: (0, -1),
}


@dataclass
class Cell:
    cell_type: CellType = CellType.EMPTY
    machine_origin: Optional[tuple] = None  # For MACHINE_PART, points to anchor (x, y)


@dataclass
class Machine:
    x: int
    y: int
    machine_type: CellType = CellType.MACHINE_1
    input_side: str = 'left'
    output_side: str = 'right'
    processing: bool = False
    process_timer: float = 0.0
    material_stage: int = 0
    has_output_ready: bool = False


@dataclass
class Material:
    x: float  # pixel position
    y: float
    grid_x: int  # current grid cell
    grid_y: int
    stage: int = 0  # 0=raw, 1=mixed, 2=scooped, 3=packaged
    moving: bool = True
    target_x: float = 0.0
    target_y: float = 0.0
    speed: float = MATERIAL_SPEED


@dataclass
class StartPoint:
    x: int
    y: int
    timer: float = 0.0
    interval: float = SPAWN_INTERVAL


class Game:
    def __init__(self):
        pygame.init()
        self.screen = pygame.display.set_mode((SCREEN_WIDTH, SCREEN_HEIGHT))
        pygame.display.set_caption("Ice Cream Factory Builder")
        self.clock = pygame.time.Clock()
        self.font = pygame.font.Font(None, 24)
        self.small_font = pygame.font.Font(None, 18)

        # Grid
        self.grid = [[Cell() for _ in range(GRID_WIDTH)] for _ in range(GRID_HEIGHT)]

        # Game objects
        self.machines: list[Machine] = []
        self.materials: list[Material] = []
        self.start_points: list[StartPoint] = []
        self.end_points: list[tuple] = []

        # Camera
        self.camera_x = 0.0
        self.camera_y = 0.0
        self.zoom = 1.0
        self.dragging = False
        self.drag_start = (0, 0)
        self.cam_start = (0, 0)

        # UI State
        self.selected_tool = CellType.CONVEYOR_RIGHT
        self.running_simulation = True
        self.animation_frame = 0
        self.animation_timer = 0.0

        # Pre-render sprites
        self._init_sprites()

    def _init_sprites(self):
        """Initialize all sprite caches."""
        self.conveyor_sprites = {}
        for direction in ['right', 'left', 'up', 'down']:
            self.conveyor_sprites[direction] = []
            for frame in range(8):
                self.conveyor_sprites[direction].append(
                    sprites.create_conveyor_belt_sprite(direction, frame)
                )

        self.machine_sprites = {
            CellType.MACHINE_1: sprites.create_machine_sprite(2, 2),
            CellType.MACHINE_2: sprites.create_machine_sprite(2, 1),
            CellType.MACHINE_3: sprites.create_machine_sprite(2, 4),
        }
        self.start_sprites = [sprites.create_start_point_sprite(f) for f in range(4)]
        self.end_sprites = [sprites.create_end_point_sprite(f) for f in range(4)]
        self.raw_material_sprite = sprites.create_raw_material_sprite()
        self.processed_sprites = [
            sprites.create_processed_material_sprite(s) for s in range(1, 4)
        ]
        self.cursor_sprite = sprites.create_cursor_sprite()
        self.delete_cursor_sprite = sprites.create_delete_cursor_sprite()

    def screen_to_grid(self, sx, sy):
        """Convert screen coordinates to grid coordinates."""
        # Account for UI panel
        sx -= UI_PANEL_WIDTH
        world_x = (sx / self.zoom) + self.camera_x
        world_y = (sy / self.zoom) + self.camera_y
        gx = int(world_x // TILE_SIZE)
        gy = int(world_y // TILE_SIZE)
        return gx, gy

    def grid_to_screen(self, gx, gy):
        """Convert grid coordinates to screen position."""
        world_x = gx * TILE_SIZE
        world_y = gy * TILE_SIZE
        sx = (world_x - self.camera_x) * self.zoom + UI_PANEL_WIDTH
        sy = (world_y - self.camera_y) * self.zoom
        return sx, sy

    def is_valid_grid(self, gx, gy):
        return 0 <= gx < GRID_WIDTH and 0 <= gy < GRID_HEIGHT

    def place_element(self, gx, gy):
        """Place the selected element at grid position."""
        if not self.is_valid_grid(gx, gy):
            return

        if self.selected_tool == CellType.RECYCLE:
            self.delete_element(gx, gy)
            return

        if self.selected_tool in MACHINE_TYPES:
            mw, mh = MACHINE_SIZES[self.selected_tool]
            # Check bounds
            if not self.is_valid_grid(gx + mw - 1, gy + mh - 1):
                return
            # Check all cells are empty
            for dy in range(mh):
                for dx in range(mw):
                    if self.grid[gy + dy][gx + dx].cell_type != CellType.EMPTY:
                        return
            # Place anchor cell
            self.grid[gy][gx] = Cell(self.selected_tool)
            # Place part cells
            for dy in range(mh):
                for dx in range(mw):
                    if dx == 0 and dy == 0:
                        continue
                    self.grid[gy + dy][gx + dx] = Cell(CellType.MACHINE_PART, machine_origin=(gx, gy))
            machine = Machine(x=gx, y=gy, machine_type=self.selected_tool)
            self._detect_machine_io(machine)
            self.machines.append(machine)

        elif self.selected_tool == CellType.START_POINT:
            if self.grid[gy][gx].cell_type != CellType.EMPTY:
                return
            self.grid[gy][gx] = Cell(CellType.START_POINT)
            self.start_points.append(StartPoint(x=gx, y=gy))

        elif self.selected_tool == CellType.END_POINT:
            if self.grid[gy][gx].cell_type != CellType.EMPTY:
                return
            self.grid[gy][gx] = Cell(CellType.END_POINT)
            self.end_points.append((gx, gy))

        else:
            # Conveyor belt
            if self.grid[gy][gx].cell_type != CellType.EMPTY:
                return
            self.grid[gy][gx] = Cell(self.selected_tool)

    def delete_element(self, gx, gy):
        """Delete element at grid position."""
        if not self.is_valid_grid(gx, gy):
            return

        cell = self.grid[gy][gx]
        if cell.cell_type == CellType.EMPTY:
            return

        if cell.cell_type in MACHINE_TYPES:
            # This is the anchor cell
            machine = next((m for m in self.machines if m.x == gx and m.y == gy), None)
            if machine:
                mw, mh = MACHINE_SIZES[machine.machine_type]
                for dy in range(mh):
                    for dx in range(mw):
                        self.grid[gy + dy][gx + dx] = Cell()
                self.machines.remove(machine)

        elif cell.cell_type == CellType.MACHINE_PART:
            if cell.machine_origin:
                ox, oy = cell.machine_origin
                self.delete_element(ox, oy)

        elif cell.cell_type == CellType.START_POINT:
            self.grid[gy][gx] = Cell()
            self.start_points = [s for s in self.start_points if not (s.x == gx and s.y == gy)]

        elif cell.cell_type == CellType.END_POINT:
            self.grid[gy][gx] = Cell()
            self.end_points = [e for e in self.end_points if not (e[0] == gx and e[1] == gy)]

        else:
            self.grid[gy][gx] = Cell()

    def _detect_machine_io(self, machine):
        """Auto-detect input/output sides of a machine."""
        machine.input_side = 'left'
        machine.output_side = 'right'

    def get_machine_input_cells(self, machine):
        """Get the grid cells that feed into this machine's input side."""
        mx, my = machine.x, machine.y
        mw, mh = MACHINE_SIZES[machine.machine_type]
        if machine.input_side == 'left':
            return [(mx - 1, my + dy) for dy in range(mh)]
        elif machine.input_side == 'right':
            return [(mx + mw, my + dy) for dy in range(mh)]
        elif machine.input_side == 'top':
            return [(mx + dx, my - 1) for dx in range(mw)]
        else:  # bottom
            return [(mx + dx, my + mh) for dx in range(mw)]

    def get_machine_output_cells(self, machine):
        """Get the grid cells where this machine outputs."""
        mx, my = machine.x, machine.y
        mw, mh = MACHINE_SIZES[machine.machine_type]
        if machine.output_side == 'right':
            return [(mx + mw, my + dy) for dy in range(mh)]
        elif machine.output_side == 'left':
            return [(mx - 1, my + dy) for dy in range(mh)]
        elif machine.output_side == 'bottom':
            return [(mx + dx, my + mh) for dx in range(mw)]
        else:  # top
            return [(mx + dx, my - 1) for dx in range(mw)]

    def _get_next_cell_from_conveyor(self, gx, gy):
        """Get the next grid cell from a conveyor at (gx, gy)."""
        cell = self.grid[gy][gx]
        if cell.cell_type in CONVEYOR_DIRECTIONS:
            dx, dy = CONVEYOR_DIRECTIONS[cell.cell_type]
            return gx + dx, gy + dy
        return None

    def update_materials(self, dt):
        """Update all material positions with smooth movement."""
        to_remove = []

        for mat in self.materials:
            if not mat.moving:
                continue

            # Calculate target position (center of target cell)
            target_px = mat.target_x
            target_py = mat.target_y

            # Move towards target
            dx = target_px - mat.x
            dy = target_py - mat.y
            dist = (dx * dx + dy * dy) ** 0.5

            move_amount = mat.speed * TILE_SIZE * dt

            if dist <= move_amount:
                # Arrived at target cell
                mat.x = target_px
                mat.y = target_py
                mat.grid_x = int(mat.x // TILE_SIZE)
                mat.grid_y = int(mat.y // TILE_SIZE)

                # Check if at end point
                if (mat.grid_x, mat.grid_y) in self.end_points:
                    to_remove.append(mat)
                    continue

                # Check if entering machine
                current_cell = None
                if self.is_valid_grid(mat.grid_x, mat.grid_y):
                    current_cell = self.grid[mat.grid_y][mat.grid_x]

                # Check if next cell is a machine
                if current_cell and current_cell.cell_type in CONVEYOR_DIRECTIONS:
                    next_pos = self._get_next_cell_from_conveyor(mat.grid_x, mat.grid_y)
                    if next_pos:
                        nx, ny = next_pos
                        if self.is_valid_grid(nx, ny):
                            next_cell = self.grid[ny][nx]
                            if next_cell.cell_type in MACHINE_TYPES or next_cell.cell_type == CellType.MACHINE_PART:
                                # Find the machine anchor
                                if next_cell.cell_type in MACHINE_TYPES:
                                    origin = (nx, ny)
                                else:
                                    origin = next_cell.machine_origin
                                if origin:
                                    for machine in self.machines:
                                        if (machine.x, machine.y) == origin and not machine.processing:
                                            machine.processing = True
                                            machine.process_timer = MACHINE_PROCESS_TIME
                                            machine.material_stage = mat.stage
                                            to_remove.append(mat)
                                            break
                                continue

                            # Move to next conveyor
                            if next_cell.cell_type in CONVEYOR_DIRECTIONS:
                                mat.target_x = nx * TILE_SIZE + TILE_SIZE // 2
                                mat.target_y = ny * TILE_SIZE + TILE_SIZE // 2
                            elif next_cell.cell_type == CellType.END_POINT:
                                mat.target_x = nx * TILE_SIZE + TILE_SIZE // 2
                                mat.target_y = ny * TILE_SIZE + TILE_SIZE // 2
                            else:
                                mat.moving = False
                        else:
                            mat.moving = False
                    else:
                        mat.moving = False
                elif current_cell and current_cell.cell_type == CellType.END_POINT:
                    to_remove.append(mat)
                else:
                    mat.moving = False
            else:
                # Smooth interpolation toward target
                mat.x += (dx / dist) * move_amount
                mat.y += (dy / dist) * move_amount

        for mat in to_remove:
            if mat in self.materials:
                self.materials.remove(mat)

    def update_machines(self, dt):
        """Update machine processing."""
        for machine in self.machines:
            if machine.processing:
                machine.process_timer -= dt
                if machine.process_timer <= 0:
                    machine.processing = False
                    machine.has_output_ready = True

            if machine.has_output_ready:
                # Try to output material
                output_cells = self.get_machine_output_cells(machine)
                for ox, oy in output_cells:
                    if self.is_valid_grid(ox, oy):
                        cell = self.grid[oy][ox]
                        if cell.cell_type in CONVEYOR_DIRECTIONS:
                            # Check no material already there
                            occupied = any(
                                m.grid_x == ox and m.grid_y == oy
                                for m in self.materials
                            )
                            if not occupied:
                                new_stage = min(machine.material_stage + 1, 3)
                                px = ox * TILE_SIZE + TILE_SIZE // 2
                                py = oy * TILE_SIZE + TILE_SIZE // 2
                                # Find next target
                                next_pos = self._get_next_cell_from_conveyor(ox, oy)
                                if next_pos:
                                    tx = next_pos[0] * TILE_SIZE + TILE_SIZE // 2
                                    ty = next_pos[1] * TILE_SIZE + TILE_SIZE // 2
                                else:
                                    tx, ty = px, py

                                mat = Material(
                                    x=px, y=py,
                                    grid_x=ox, grid_y=oy,
                                    stage=new_stage,
                                    target_x=tx, target_y=ty
                                )
                                self.materials.append(mat)
                                machine.has_output_ready = False
                                break

    def update_spawners(self, dt):
        """Spawn materials from start points."""
        for sp in self.start_points:
            sp.timer += dt
            if sp.timer >= sp.interval:
                sp.timer = 0.0
                # Find adjacent conveyor to spawn onto
                gx, gy = sp.x, sp.y
                for dx, dy in [(1, 0), (-1, 0), (0, 1), (0, -1)]:
                    nx, ny = gx + dx, gy + dy
                    if self.is_valid_grid(nx, ny):
                        cell = self.grid[ny][nx]
                        if cell.cell_type in CONVEYOR_DIRECTIONS:
                            # Check not occupied
                            occupied = any(
                                m.grid_x == nx and m.grid_y == ny
                                for m in self.materials
                            )
                            if not occupied:
                                px = nx * TILE_SIZE + TILE_SIZE // 2
                                py = ny * TILE_SIZE + TILE_SIZE // 2
                                next_pos = self._get_next_cell_from_conveyor(nx, ny)
                                if next_pos:
                                    tx = next_pos[0] * TILE_SIZE + TILE_SIZE // 2
                                    ty = next_pos[1] * TILE_SIZE + TILE_SIZE // 2
                                else:
                                    tx, ty = px, py
                                mat = Material(
                                    x=px, y=py,
                                    grid_x=nx, grid_y=ny,
                                    stage=0,
                                    target_x=tx, target_y=ty
                                )
                                self.materials.append(mat)
                                break

    def update(self, dt):
        """Update game state."""
        # Animation
        self.animation_timer += dt
        if self.animation_timer >= 0.1:
            self.animation_timer = 0.0
            self.animation_frame = (self.animation_frame + 1) % 8

        if self.running_simulation:
            self.update_spawners(dt)
            self.update_materials(dt)
            self.update_machines(dt)

    def draw_grid(self):
        """Draw the game grid and all elements."""
        # Calculate visible area
        start_gx = max(0, int(self.camera_x // TILE_SIZE))
        start_gy = max(0, int(self.camera_y // TILE_SIZE))
        end_gx = min(GRID_WIDTH, int((self.camera_x + (SCREEN_WIDTH - UI_PANEL_WIDTH) / self.zoom) // TILE_SIZE) + 2)
        end_gy = min(GRID_HEIGHT, int((self.camera_y + SCREEN_HEIGHT / self.zoom) // TILE_SIZE) + 2)

        # Draw grid background
        for gy in range(start_gy, end_gy):
            for gx in range(start_gx, end_gx):
                sx, sy = self.grid_to_screen(gx, gy)
                tile_sz = int(TILE_SIZE * self.zoom)

                if sx + tile_sz < UI_PANEL_WIDTH or sx > SCREEN_WIDTH:
                    continue
                if sy + tile_sz < 0 or sy > SCREEN_HEIGHT:
                    continue

                cell = self.grid[gy][gx]

                # Skip MACHINE_PART cells - the anchor cell draws the full sprite
                if cell.cell_type == CellType.MACHINE_PART:
                    continue

                # Grid background
                color = (30, 30, 40) if (gx + gy) % 2 == 0 else (35, 35, 45)
                pygame.draw.rect(self.screen, color, (sx, sy, tile_sz, tile_sz))

                if cell.cell_type in CONVEYOR_DIRECTIONS:
                    direction_name = {
                        CellType.CONVEYOR_RIGHT: 'right',
                        CellType.CONVEYOR_LEFT: 'left',
                        CellType.CONVEYOR_DOWN: 'down',
                        CellType.CONVEYOR_UP: 'up',
                    }[cell.cell_type]
                    sprite = self.conveyor_sprites[direction_name][self.animation_frame]
                    scaled = pygame.transform.scale(sprite, (tile_sz, tile_sz))
                    self.screen.blit(scaled, (sx, sy))

                elif cell.cell_type in MACHINE_TYPES:
                    # Draw the full machine sprite at anchor position
                    mw, mh = MACHINE_SIZES[cell.cell_type]
                    sprite = self.machine_sprites[cell.cell_type]
                    sw = int(TILE_SIZE * mw * self.zoom)
                    sh = int(TILE_SIZE * mh * self.zoom)
                    scaled = pygame.transform.scale(sprite, (sw, sh))
                    self.screen.blit(scaled, (sx, sy))
                    # Draw processing indicator
                    for machine in self.machines:
                        if machine.x == gx and machine.y == gy and machine.processing:
                            progress = 1.0 - (machine.process_timer / MACHINE_PROCESS_TIME)
                            bar_w = int(sw * 0.8)
                            bar_h = max(4, int(6 * self.zoom))
                            bar_x = sx + int(sw * 0.1)
                            bar_y = sy + sh - bar_h - 4
                            pygame.draw.rect(self.screen, (60, 60, 60), (bar_x, bar_y, bar_w, bar_h))
                            pygame.draw.rect(self.screen, (100, 255, 100), (bar_x, bar_y, int(bar_w * progress), bar_h))

                elif cell.cell_type == CellType.START_POINT:
                    sprite = self.start_sprites[self.animation_frame % 4]
                    scaled = pygame.transform.scale(sprite, (tile_sz, tile_sz))
                    self.screen.blit(scaled, (sx, sy))

                elif cell.cell_type == CellType.END_POINT:
                    sprite = self.end_sprites[self.animation_frame % 4]
                    scaled = pygame.transform.scale(sprite, (tile_sz, tile_sz))
                    self.screen.blit(scaled, (sx, sy))

        # Draw grid lines (subtle)
        for gy in range(start_gy, end_gy + 1):
            sy = int((gy * TILE_SIZE - self.camera_y) * self.zoom) 
            pygame.draw.line(self.screen, (45, 45, 55), (UI_PANEL_WIDTH, sy), (SCREEN_WIDTH, sy), 1)
        for gx in range(start_gx, end_gx + 1):
            sx = int((gx * TILE_SIZE - self.camera_x) * self.zoom + UI_PANEL_WIDTH)
            pygame.draw.line(self.screen, (45, 45, 55), (sx, 0), (sx, SCREEN_HEIGHT), 1)

    def draw_materials(self):
        """Draw all materials with smooth positions."""
        tile_sz = int(TILE_SIZE * self.zoom)
        for mat in self.materials:
            # Convert world position to screen
            sx = (mat.x - TILE_SIZE // 2 - self.camera_x) * self.zoom + UI_PANEL_WIDTH
            sy = (mat.y - TILE_SIZE // 2 - self.camera_y) * self.zoom

            if sx + tile_sz < UI_PANEL_WIDTH or sx > SCREEN_WIDTH:
                continue
            if sy + tile_sz < 0 or sy > SCREEN_HEIGHT:
                continue

            if mat.stage == 0:
                sprite = self.raw_material_sprite
            else:
                sprite = self.processed_sprites[min(mat.stage - 1, 2)]

            scaled = pygame.transform.scale(sprite, (tile_sz, tile_sz))
            self.screen.blit(scaled, (sx, sy))

    def draw_cursor(self, mouse_pos):
        """Draw cursor at mouse grid position."""
        mx, my = mouse_pos
        if mx < UI_PANEL_WIDTH:
            return

        gx, gy = self.screen_to_grid(mx, my)
        if not self.is_valid_grid(gx, gy):
            return

        sx, sy = self.grid_to_screen(gx, gy)
        tile_sz = int(TILE_SIZE * self.zoom)

        if self.selected_tool == CellType.RECYCLE:
            cursor = pygame.transform.scale(self.delete_cursor_sprite, (tile_sz, tile_sz))
            self.screen.blit(cursor, (sx, sy))
        elif self.selected_tool in MACHINE_TYPES:
            mw, mh = MACHINE_SIZES[self.selected_tool]
            cursor = pygame.transform.scale(self.cursor_sprite, (tile_sz, tile_sz))
            for dy in range(mh):
                for dx in range(mw):
                    self.screen.blit(cursor, (sx + dx * tile_sz, sy + dy * tile_sz))
        else:
            cursor = pygame.transform.scale(self.cursor_sprite, (tile_sz, tile_sz))
            self.screen.blit(cursor, (sx, sy))

    def _get_tool_buttons(self):
        """Return list of (label, tool_type, rect) for UI buttons."""
        tools = [
            ("Recycle", CellType.RECYCLE),
            ("Belt \u2192", CellType.CONVEYOR_RIGHT),
            ("Belt \u2190", CellType.CONVEYOR_LEFT),
            ("Belt \u2193", CellType.CONVEYOR_DOWN),
            ("Belt \u2191", CellType.CONVEYOR_UP),
            ("Machine 1", CellType.MACHINE_1),
            ("Machine 2", CellType.MACHINE_2),
            ("Machine 3", CellType.MACHINE_3),
            ("Start", CellType.START_POINT),
            ("End", CellType.END_POINT),
        ]
        buttons = []
        y = 70
        for label, tool_type in tools:
            rect = pygame.Rect(10, y, UI_PANEL_WIDTH - 20, 28)
            buttons.append((label, tool_type, rect))
            y += 32
        return buttons

    def _get_tool_preview_sprite(self, tool_type):
        """Return a small sprite for the tool preview in the panel."""
        preview_size = 22
        if tool_type == CellType.RECYCLE:
            return pygame.transform.scale(self.delete_cursor_sprite, (preview_size, preview_size))
        elif tool_type == CellType.CONVEYOR_RIGHT:
            return pygame.transform.scale(self.conveyor_sprites['right'][0], (preview_size, preview_size))
        elif tool_type == CellType.CONVEYOR_LEFT:
            return pygame.transform.scale(self.conveyor_sprites['left'][0], (preview_size, preview_size))
        elif tool_type == CellType.CONVEYOR_DOWN:
            return pygame.transform.scale(self.conveyor_sprites['down'][0], (preview_size, preview_size))
        elif tool_type == CellType.CONVEYOR_UP:
            return pygame.transform.scale(self.conveyor_sprites['up'][0], (preview_size, preview_size))
        elif tool_type in MACHINE_TYPES:
            mw, mh = MACHINE_SIZES[tool_type]
            # Scale proportionally to fit in preview_size height
            aspect = mw / mh
            ph = preview_size
            pw = int(ph * aspect)
            return pygame.transform.scale(self.machine_sprites[tool_type], (pw, ph))
        elif tool_type == CellType.START_POINT:
            return pygame.transform.scale(self.start_sprites[0], (preview_size, preview_size))
        elif tool_type == CellType.END_POINT:
            return pygame.transform.scale(self.end_sprites[0], (preview_size, preview_size))
        return None

    def handle_ui_click(self, mx, my):
        """Handle clicks on the UI panel. Returns True if a button was clicked."""
        for label, tool_type, rect in self._get_tool_buttons():
            if rect.collidepoint(mx, my):
                self.selected_tool = tool_type
                return True
        return False

    def draw_ui(self):
        """Draw the side UI panel."""
        # Panel background
        pygame.draw.rect(self.screen, (20, 20, 30), (0, 0, UI_PANEL_WIDTH, SCREEN_HEIGHT))
        pygame.draw.line(self.screen, (60, 60, 80), (UI_PANEL_WIDTH - 1, 0), (UI_PANEL_WIDTH - 1, SCREEN_HEIGHT), 2)

        # Title
        title = self.font.render("ICE CREAM", True, (200, 220, 255))
        self.screen.blit(title, (20, 10))
        title2 = self.font.render("FACTORY", True, (200, 220, 255))
        self.screen.blit(title2, (20, 30))

        # Tool buttons (clickable) with sprite previews
        for label, tool_type, rect in self._get_tool_buttons():
            selected = self.selected_tool == tool_type
            color = (255, 255, 100) if selected else (150, 150, 170)
            bg_color = (50, 50, 70) if selected else (30, 30, 40)
            if tool_type == CellType.RECYCLE:
                bg_color = (70, 30, 30) if selected else (40, 25, 25)
                color = (255, 120, 120) if selected else (180, 100, 100)
            pygame.draw.rect(self.screen, bg_color, rect, border_radius=4)
            if selected:
                pygame.draw.rect(self.screen, color, rect, 2, border_radius=4)
            # Draw sprite preview
            preview = self._get_tool_preview_sprite(tool_type)
            if preview:
                preview_x = rect.x + 4
                preview_y = rect.y + (rect.height - preview.get_height()) // 2
                self.screen.blit(preview, (preview_x, preview_y))
            # Draw label after preview
            text_x = rect.x + 30
            text = self.font.render(label, True, color)
            self.screen.blit(text, (text_x, rect.y + 5))

        # Status
        y = 70 + 32 * 10 + 20
        status_color = (100, 255, 100) if self.running_simulation else (255, 100, 100)
        status_text = "\u25b6 Running" if self.running_simulation else "\u23f8 Paused"
        text = self.font.render(status_text, True, status_color)
        self.screen.blit(text, (20, y))

        y += 30
        text = self.small_font.render(f"Materials: {len(self.materials)}", True, (150, 150, 170))
        self.screen.blit(text, (20, y))

        y += 20
        text = self.small_font.render(f"Machines: {len(self.machines)}", True, (150, 150, 170))
        self.screen.blit(text, (20, y))

        y += 30
        text = self.small_font.render("SPACE: Pause/Resume", True, (100, 100, 120))
        self.screen.blit(text, (10, y))
        y += 16
        text = self.small_font.render("Scroll: Zoom", True, (100, 100, 120))
        self.screen.blit(text, (10, y))
        y += 16
        text = self.small_font.render("MidMouse: Pan", True, (100, 100, 120))
        self.screen.blit(text, (10, y))

    def handle_events(self):
        """Handle all input events."""
        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                return False
            elif event.type == pygame.KEYDOWN:
                if event.key == pygame.K_ESCAPE:
                    return False
                elif event.key == pygame.K_1:
                    self.selected_tool = CellType.CONVEYOR_RIGHT
                elif event.key == pygame.K_2:
                    self.selected_tool = CellType.CONVEYOR_LEFT
                elif event.key == pygame.K_3:
                    self.selected_tool = CellType.CONVEYOR_DOWN
                elif event.key == pygame.K_4:
                    self.selected_tool = CellType.CONVEYOR_UP
                elif event.key == pygame.K_5:
                    self.selected_tool = CellType.MACHINE_1
                elif event.key == pygame.K_6:
                    self.selected_tool = CellType.MACHINE_2
                elif event.key == pygame.K_7:
                    self.selected_tool = CellType.MACHINE_3
                elif event.key == pygame.K_8:
                    self.selected_tool = CellType.START_POINT
                elif event.key == pygame.K_9:
                    self.selected_tool = CellType.END_POINT
                elif event.key == pygame.K_SPACE:
                    self.running_simulation = not self.running_simulation
                elif event.key == pygame.K_r:
                    # Rotate conveyor direction
                    rotation = {
                        CellType.CONVEYOR_RIGHT: CellType.CONVEYOR_DOWN,
                        CellType.CONVEYOR_DOWN: CellType.CONVEYOR_LEFT,
                        CellType.CONVEYOR_LEFT: CellType.CONVEYOR_UP,
                        CellType.CONVEYOR_UP: CellType.CONVEYOR_RIGHT,
                    }
                    if self.selected_tool in rotation:
                        self.selected_tool = rotation[self.selected_tool]

            elif event.type == pygame.MOUSEBUTTONDOWN:
                mx, my = event.pos
                if event.button == 1 and mx < UI_PANEL_WIDTH:
                    self.handle_ui_click(mx, my)
                elif event.button == 1 and mx >= UI_PANEL_WIDTH:
                    gx, gy = self.screen_to_grid(mx, my)
                    self.place_element(gx, gy)
                elif event.button == 3 and mx >= UI_PANEL_WIDTH:
                    gx, gy = self.screen_to_grid(mx, my)
                    self.delete_element(gx, gy)
                elif event.button == 2:
                    self.dragging = True
                    self.drag_start = (mx, my)
                    self.cam_start = (self.camera_x, self.camera_y)
                elif event.button == 4:  # scroll up
                    # Zoom in
                    self.zoom = min(3.0, self.zoom * 1.1)
                elif event.button == 5:  # scroll down
                    # Zoom out
                    self.zoom = max(0.3, self.zoom / 1.1)

            elif event.type == pygame.MOUSEBUTTONUP:
                if event.button == 2:
                    self.dragging = False

            elif event.type == pygame.MOUSEMOTION:
                if self.dragging:
                    mx, my = event.pos
                    dx = (self.drag_start[0] - mx) / self.zoom
                    dy = (self.drag_start[1] - my) / self.zoom
                    self.camera_x = self.cam_start[0] + dx
                    self.camera_y = self.cam_start[1] + dy

        # Arrow key panning
        keys = pygame.key.get_pressed()
        pan_speed = 300 / self.zoom
        dt = self.clock.get_time() / 1000.0
        if keys[pygame.K_LEFT]:
            self.camera_x -= pan_speed * dt
        if keys[pygame.K_RIGHT]:
            self.camera_x += pan_speed * dt
        if keys[pygame.K_UP]:
            self.camera_y -= pan_speed * dt
        if keys[pygame.K_DOWN]:
            self.camera_y += pan_speed * dt

        return True

    async def run(self):
        """Main game loop."""
        running = True
        while running:
            dt = self.clock.tick(FPS) / 1000.0

            running = self.handle_events()

            self.update(dt)

            # Draw
            self.screen.fill((20, 20, 30))
            self.draw_grid()
            self.draw_materials()
            self.draw_cursor(pygame.mouse.get_pos())
            self.draw_ui()

            pygame.display.flip()
            await asyncio.sleep(0)  # Required for pygbag web support

        pygame.quit()
        sys.exit()


async def main():
    game = Game()
    await game.run()

if __name__ == '__main__':
    asyncio.run(main())

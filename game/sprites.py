"""
Programmatic pixel art sprite generation for the Ice Cream Factory game.
Replace these with your own sprite images later.
"""
import pygame

TILE_SIZE = 32


def create_conveyor_belt_sprite(direction, frame=0):
    """Create a conveyor belt sprite with animation frame.
    direction: 'right', 'left', 'up', 'down'
    frame: animation frame (0-3)
    """
    surf = pygame.Surface((TILE_SIZE, TILE_SIZE), pygame.SRCALPHA)
    # Base color - metallic gray
    surf.fill((80, 80, 90))

    # Draw belt lines (animated)
    offset = frame * 4
    if direction in ('right', 'left'):
        for y in range(0, TILE_SIZE, 8):
            shifted = (y + offset) % TILE_SIZE if direction == 'right' else (y - offset) % TILE_SIZE
            pygame.draw.line(surf, (50, 50, 60), (4, shifted), (TILE_SIZE - 4, shifted), 2)
        # Direction arrow
        cx, cy = TILE_SIZE // 2, TILE_SIZE // 2
        if direction == 'right':
            pygame.draw.polygon(surf, (200, 200, 50), [(cx + 8, cy), (cx, cy - 5), (cx, cy + 5)])
        else:
            pygame.draw.polygon(surf, (200, 200, 50), [(cx - 8, cy), (cx, cy - 5), (cx, cy + 5)])
    else:
        for x in range(0, TILE_SIZE, 8):
            shifted = (x + offset) % TILE_SIZE if direction == 'down' else (x - offset) % TILE_SIZE
            pygame.draw.line(surf, (50, 50, 60), (shifted, 4), (shifted, TILE_SIZE - 4), 2)
        cx, cy = TILE_SIZE // 2, TILE_SIZE // 2
        if direction == 'down':
            pygame.draw.polygon(surf, (200, 200, 50), [(cx, cy + 8), (cx - 5, cy), (cx + 5, cy)])
        else:
            pygame.draw.polygon(surf, (200, 200, 50), [(cx, cy - 8), (cx - 5, cy), (cx + 5, cy)])

    # Border
    pygame.draw.rect(surf, (40, 40, 50), (0, 0, TILE_SIZE, TILE_SIZE), 1)
    return surf


def create_machine_sprite(width_tiles=2, height_tiles=2):
    """Create a machine sprite spanning width_tiles x height_tiles.
    Different colors per machine size for visual distinction.
    """
    w = TILE_SIZE * width_tiles
    h = TILE_SIZE * height_tiles
    surf = pygame.Surface((w, h), pygame.SRCALPHA)

    # Color scheme per size
    if width_tiles == 2 and height_tiles == 2:
        body_color = (100, 120, 140)
        border_color = (60, 80, 100)
        panel_color = (130, 150, 170)
        gear_color = (180, 100, 100)
    elif width_tiles == 2 and height_tiles == 1:
        body_color = (120, 100, 140)
        border_color = (80, 60, 100)
        panel_color = (150, 130, 170)
        gear_color = (100, 180, 100)
    else:  # 2x4
        body_color = (140, 120, 100)
        border_color = (100, 80, 60)
        panel_color = (170, 150, 130)
        gear_color = (100, 100, 180)

    # Machine body
    pygame.draw.rect(surf, body_color, (2, 2, w - 4, h - 4))
    pygame.draw.rect(surf, border_color, (2, 2, w - 4, h - 4), 2)

    # Inner panel
    pygame.draw.rect(surf, panel_color, (5, 5, w - 10, h - 10))

    # Gear in center
    cx, cy = w // 2, h // 2
    gear_r = min(w, h) // 4
    pygame.draw.circle(surf, gear_color, (cx, cy), gear_r)
    pygame.draw.circle(surf, (gear_color[0] + 20, gear_color[1] + 20, gear_color[2] + 20), (cx, cy), gear_r - 3)
    pygame.draw.circle(surf, (gear_color[0] - 20, gear_color[1] - 20, gear_color[2] - 20), (cx, cy), 3)

    # Bolts in corners
    for bx, by in [(6, 6), (w - 6, 6), (6, h - 6), (w - 6, h - 6)]:
        pygame.draw.circle(surf, (200, 200, 210), (bx, by), 2)

    # Grid lines to show tile boundaries
    for tx in range(1, width_tiles):
        x = tx * TILE_SIZE
        pygame.draw.line(surf, border_color, (x, 3), (x, h - 3), 1)
    for ty in range(1, height_tiles):
        y = ty * TILE_SIZE
        pygame.draw.line(surf, border_color, (3, y), (w - 3, y), 1)

    return surf


def create_start_point_sprite(frame=0):
    """Create starting point sprite (raw material dispenser)."""
    surf = pygame.Surface((TILE_SIZE, TILE_SIZE), pygame.SRCALPHA)

    # Green base
    pygame.draw.rect(surf, (40, 160, 60), (2, 2, TILE_SIZE - 4, TILE_SIZE - 4))
    pygame.draw.rect(surf, (30, 120, 40), (2, 2, TILE_SIZE - 4, TILE_SIZE - 4), 2)

    # Arrow/dispenser icon
    cx, cy = TILE_SIZE // 2, TILE_SIZE // 2
    pygame.draw.rect(surf, (80, 200, 100), (cx - 6, cy - 6, 12, 12))

    # Pulsing indicator
    pulse = (frame % 4) * 2
    pygame.draw.circle(surf, (100, 255, 120), (cx, cy), 4 + pulse, 1)

    # "S" label
    pygame.draw.rect(surf, (200, 255, 200), (cx - 3, 4, 6, 8))
    return surf


def create_end_point_sprite(frame=0):
    """Create ending point sprite (material consumer)."""
    surf = pygame.Surface((TILE_SIZE, TILE_SIZE), pygame.SRCALPHA)

    # Red base
    pygame.draw.rect(surf, (160, 40, 40), (2, 2, TILE_SIZE - 4, TILE_SIZE - 4))
    pygame.draw.rect(surf, (120, 30, 30), (2, 2, TILE_SIZE - 4, TILE_SIZE - 4), 2)

    # Funnel/target icon
    cx, cy = TILE_SIZE // 2, TILE_SIZE // 2
    pygame.draw.circle(surf, (200, 80, 80), (cx, cy), 8)
    pygame.draw.circle(surf, (240, 100, 100), (cx, cy), 5)
    pygame.draw.circle(surf, (180, 60, 60), (cx, cy), 2)

    # Pulsing
    pulse = (frame % 4) * 2
    pygame.draw.circle(surf, (255, 100, 100), (cx, cy), 10 + pulse, 1)
    return surf


def create_raw_material_sprite():
    """Create raw material sprite (milk/cream blob)."""
    surf = pygame.Surface((TILE_SIZE, TILE_SIZE), pygame.SRCALPHA)

    cx, cy = TILE_SIZE // 2, TILE_SIZE // 2
    # White blob (milk)
    pygame.draw.circle(surf, (240, 240, 255), (cx, cy), 10)
    pygame.draw.circle(surf, (200, 200, 240), (cx, cy), 10, 2)
    # Highlight
    pygame.draw.circle(surf, (255, 255, 255), (cx - 3, cy - 3), 3)
    return surf


def create_processed_material_sprite(stage=1):
    """Create processed material sprite.
    stage 1: mixed cream (yellow)
    stage 2: ice cream scoop (pink)
    stage 3: packaged ice cream (boxed)
    """
    surf = pygame.Surface((TILE_SIZE, TILE_SIZE), pygame.SRCALPHA)
    cx, cy = TILE_SIZE // 2, TILE_SIZE // 2

    if stage == 1:
        # Yellow cream
        pygame.draw.circle(surf, (255, 220, 100), (cx, cy), 10)
        pygame.draw.circle(surf, (200, 170, 60), (cx, cy), 10, 2)
        pygame.draw.circle(surf, (255, 240, 150), (cx - 3, cy - 3), 3)
    elif stage == 2:
        # Pink ice cream scoop
        pygame.draw.circle(surf, (255, 150, 180), (cx, cy), 10)
        pygame.draw.circle(surf, (200, 100, 130), (cx, cy), 10, 2)
        # Sprinkles
        for sx, sy in [(-4, -4), (3, -2), (-2, 4), (4, 3)]:
            pygame.draw.rect(surf, (255, 255, 100), (cx + sx, cy + sy, 2, 2))
        pygame.draw.circle(surf, (255, 180, 200), (cx - 3, cy - 3), 3)
    else:
        # Boxed ice cream
        pygame.draw.rect(surf, (100, 180, 255), (cx - 8, cy - 8, 16, 16))
        pygame.draw.rect(surf, (60, 130, 200), (cx - 8, cy - 8, 16, 16), 2)
        # Ice cream icon on box
        pygame.draw.circle(surf, (255, 200, 220), (cx, cy - 2), 4)
        pygame.draw.rect(surf, (200, 150, 100), (cx - 2, cy + 2, 4, 5))

    return surf


def create_cursor_sprite():
    """Create a selection cursor sprite."""
    surf = pygame.Surface((TILE_SIZE, TILE_SIZE), pygame.SRCALPHA)
    # Animated border
    pygame.draw.rect(surf, (255, 255, 0, 180), (0, 0, TILE_SIZE, TILE_SIZE), 2)
    # Corner marks
    for x, y in [(0, 0), (TILE_SIZE - 6, 0), (0, TILE_SIZE - 6), (TILE_SIZE - 6, TILE_SIZE - 6)]:
        pygame.draw.rect(surf, (255, 255, 100, 200), (x, y, 6, 6), 2)
    return surf


def create_delete_cursor_sprite():
    """Create a deletion cursor sprite (red X)."""
    surf = pygame.Surface((TILE_SIZE, TILE_SIZE), pygame.SRCALPHA)
    pygame.draw.rect(surf, (255, 50, 50, 120), (0, 0, TILE_SIZE, TILE_SIZE), 2)
    pygame.draw.line(surf, (255, 50, 50, 200), (4, 4), (TILE_SIZE - 4, TILE_SIZE - 4), 3)
    pygame.draw.line(surf, (255, 50, 50, 200), (TILE_SIZE - 4, 4), (4, TILE_SIZE - 4), 3)
    return surf

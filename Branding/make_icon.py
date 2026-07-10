"""Render the Coral app icon: rounded-rect living-coral gradient + a branching
coral glyph (which doubles as the agent topology) in cream. Supersampled for
clean edges, then downscaled to each macOS icon size."""
from PIL import Image, ImageDraw
import math, os

OUT = "/home/user/StrategyForge/StrategyForge/Assets.xcassets/AppIcon.appiconset"

# Brand colors
CORAL_TOP = (255, 138, 110)   # #FF8A6E
CORAL_MID = (255, 107, 84)    # #FF6B54
CORAL_BOT = (240, 62, 39)     # #F03E27
CREAM     = (255, 243, 236)   # #FFF3EC

def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))

def grad_color(t):
    # 0..1 top->bottom through mid
    if t < 0.46:
        return lerp(CORAL_TOP, CORAL_MID, t / 0.46)
    return lerp(CORAL_MID, CORAL_BOT, (t - 0.46) / 0.54)

def rounded_mask(size, radius):
    m = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(m)
    d.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return m

def draw_branch(d, p0, p1, p2, width, color):
    """Quadratic bezier stroke as a series of thick round dots (simple, clean)."""
    steps = 64
    for i in range(steps + 1):
        t = i / steps
        x = (1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0]
        y = (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1]
        r = width / 2
        d.ellipse([x - r, y - r, x + r, y + r], fill=color)

def render(size):
    SS = 4  # supersample
    S = size * SS
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))

    # Gradient background
    bg = Image.new("RGBA", (S, S))
    bpx = bg.load()
    for y in range(S):
        c = grad_color(y / (S - 1))
        for x in range(S):
            bpx[x, y] = (c[0], c[1], c[2], 255)

    radius = int(S * 0.225)  # macOS squircle-ish
    mask = rounded_mask(S, radius)
    img.paste(bg, (0, 0), mask)

    # Glyph on a 100x100 logical space, centered/scaled
    d = ImageDraw.Draw(img)
    def P(x, y):  # logical(0..100) -> pixels
        return (x / 100 * S, y / 100 * S)
    w = S * 0.062          # branch stroke width
    # branches (root -> fork -> 4 tips), mirrors the SVG in the identity manual
    draw_branch(d, P(50, 84), P(50, 70), P(50, 60), w, CREAM)
    draw_branch(d, P(50, 60), P(40, 52), P(29, 40), w, CREAM)
    draw_branch(d, P(29, 40), P(24, 31), P(21, 24), w, CREAM)
    draw_branch(d, P(29, 40), P(34, 31), P(39, 25), w, CREAM)
    draw_branch(d, P(50, 60), P(60, 52), P(71, 40), w, CREAM)
    draw_branch(d, P(71, 40), P(76, 31), P(79, 24), w, CREAM)
    draw_branch(d, P(71, 40), P(66, 31), P(61, 25), w, CREAM)
    # nodes
    def node(x, y, rr):
        cx, cy = P(x, y)
        r = rr / 100 * S
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=CREAM)
    node(50, 84, 7.6)
    for (x, y) in [(21, 24), (39, 25), (61, 25), (79, 24)]:
        node(x, y, 5.6)

    # Downsample
    img = img.resize((size, size), Image.LANCZOS)
    return img

sizes = {
    "icon_16.png": 16, "icon_16@2x.png": 32,
    "icon_32.png": 32, "icon_32@2x.png": 64,
    "icon_128.png": 128, "icon_128@2x.png": 256,
    "icon_256.png": 256, "icon_256@2x.png": 512,
    "icon_512.png": 512, "icon_512@2x.png": 1024,
}
for name, px in sizes.items():
    render(px).save(os.path.join(OUT, name))
    print("wrote", name, px)
print("done")

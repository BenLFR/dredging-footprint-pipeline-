---
name: scientific-figure
description: >
  Recreates a scientific infographic or figure from an input image as a fully
  vectorized, independently-editable file. Analyzes the image (vision), rebuilds
  every element (boxes, arrows, text, panels, legends, formulas) as Python/matplotlib
  SVG code, then runs a perceptual SSIM verification loop — does NOT stop until the
  rendered output is perceptually identical to the original. Final export: SVG master
  + PPTX (for Canva import, where every box/arrow/label is a separate editable
  element) + preview PNG. Outputs go to output_V6/figures/.
  Triggers: "vectorize figure", "recreate infographic", "make editable",
  "convert to vector", "scientific figure", "/scientific-figure".
---

# Scientific Figure — Vectorize & Make Editable

Convert any scientific infographic or pipeline figure into a fully vectorized,
Canva-editable file. Every element (box, arrow, label, panel, legend) becomes an
independently moveable and editable object in Canva after PPTX import.

---

## When to use this skill

- You have a raster image (PNG/JPG/screenshot) of a scientific figure or infographic
- You want to edit individual elements (text, colors, arrows, boxes) in Canva
- You need a clean SVG vector master for publication or thesis figures
- You want the output to be pixel-for-pixel faithful to the original

---

## Inputs

Parse the user's invocation for:

- **image_path**: path to the source image (PNG/JPG). Required.
  If not provided, ask: "Please provide the path to the figure image."
- **name**: output filename stem (default: `figure_YYYYMMDD`).
  Derive from image filename if possible.
- **output_dir**: where to save all outputs (default: `output_V6/figures/`).
- **ssim_threshold**: minimum SSIM before stopping (default: `0.92`).
  Accept override via `--ssim=0.85` etc.

---

## Phase 0 — Environment Check

Before writing any code:

1. **Check Python dependencies** by running:
   ```bash
   python3 -c "import matplotlib, numpy, PIL, skimage, cairosvg, pptx; print('OK')"
   ```
   If any import fails, install the missing package(s):
   ```bash
   pip install matplotlib numpy Pillow scikit-image cairosvg python-pptx
   ```
   `cairosvg` requires `cairo` system library. If install fails on Windows, fall back
   to using `svglib` + `reportlab` for SVG→PNG rendering, or `inkscape --export-png`
   if Inkscape is available (`where inkscape`).

2. **Create output directory**:
   ```bash
   mkdir -p output_V6/figures
   ```

3. **Record git state**:
   ```bash
   git log -1 --oneline
   ```
   Embed commit hash and date as comments in the generated Python script.

4. **Get image dimensions** so the reconstructed figure uses the same aspect ratio:
   ```bash
   python3 -c "from PIL import Image; img=Image.open('<image_path>'); print(img.size)"
   ```

---

## Phase 1 — Deep Image Analysis

Use the Read tool to load and display the image. Then perform a rigorous,
**panel-by-panel analysis**. Do NOT write any code yet — analyse first, code second.

### 1a — Top-level layout

Identify:
- Figure title (text, font size, position)
- Number of top-level panels and their labels (A, B, C, D…)
- Panel arrangement (grid layout, approximate relative widths/heights)
- Figure caption (if present)
- Overall background color and border style

### 1b — Per-panel inventory

For **each panel**, record:

| Field | What to note |
|-------|-------------|
| Panel label | Letter, position (top-left / top-right), font, bold? |
| Panel title | Text, font size, background color if any |
| Sub-panels | Any nested labeled sub-sections (B1, B2… D1, D2…) |
| Element types | Boxes (rounded/square?), arrows, bullet lists, maps, formulas, tables, legends |
| Box styles | Fill color (sample exact hex), border color, border width, corner radius |
| Text content | All text verbatim, including mathematical notation (LaTeX where applicable) |
| Arrows | Source element, target element, arrowhead style (→, ⇒, dashed?), color |
| Color scheme | All unique colors used (use eyedropper logic: sample from center of each element) |
| Icons/rasters | Any embedded photographic or raster element that cannot be reproduced as vector |

### 1c — Typography audit

- Primary font family (Arial / Helvetica / sans-serif)
- Title font size (pt)
- Panel label font size (pt)
- Body text font size (pt)
- Bold / italic usage patterns
- Line spacing

### 1d — Color inventory

List every unique color as hex. For each:
- `background_panel`: panel background fill
- `box_fill_N`: fill color of distinct box types (use descriptive names from figure)
- `text_color`: main text color
- `arrow_color`: arrow / connector color
- `border_color`: box border color

---

## Phase 2 — Python Script Generation

Write a complete, self-contained Python script at:
`output_V6/figures/<name>_generate.py`

### Required imports

```python
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import matplotlib.patheffects as pe
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch
import matplotlib.gridspec as gridspec
import numpy as np
```

### Script structure

```python
#!/usr/bin/env python3
"""
Reconstructed figure: <name>
Source: <original image path>
Generated by /scientific-figure skill
Git: <commit hash> | <date>
SSIM loop: auto-iterates until perceptual match >= <ssim_threshold>
"""

# ── 0. Global style ──────────────────────────────────────────────────────────
import matplotlib as mpl
mpl.rcParams.update({
    'font.family': 'sans-serif',
    'font.sans-serif': ['Arial', 'Helvetica', 'DejaVu Sans'],
    'font.size': 8,
    'text.usetex': False,  # Use mathtext, not full LaTeX (for portability)
    'svg.fonttype': 'none', # Keep text as text in SVG (NOT converted to paths)
                             # CRITICAL: allows Canva/Inkscape to edit text
})

# ── 1. Figure canvas ─────────────────────────────────────────────────────────
# Match original aspect ratio exactly
FIG_WIDTH  = <width_inches>   # derived from image dimensions
FIG_HEIGHT = <height_inches>  # derived from image dimensions

fig = plt.figure(figsize=(FIG_WIDTH, FIG_HEIGHT), facecolor='white')

# ── 2. Overall title ─────────────────────────────────────────────────────────
fig.text(0.5, 0.97, '<figure title>', ha='center', va='top',
         fontsize=<title_fontsize>, fontweight='bold')

# ── 3. Panel grid ────────────────────────────────────────────────────────────
# Use GridSpec with ratios matching observed panel widths
gs = gridspec.GridSpec(
    <nrows>, <ncols>,
    left=<left>, right=<right>, top=<top>, bottom=<bottom>,
    hspace=<hspace>, wspace=<wspace>,
    width_ratios=[<w1>, <w2>, ...],
    height_ratios=[<h1>, <h2>, ...]
)

# ── 4. Helper functions ───────────────────────────────────────────────────────

def add_panel_label(ax, letter, x=-0.05, y=1.02):
    """Add bold uppercase panel label (A, B, C…) to axis corner."""
    ax.text(x, y, letter, transform=ax.transAxes,
            fontsize=11, fontweight='bold', va='bottom', ha='right')

def add_box(ax, x, y, w, h, text, fill_color, text_color='black',
            edgecolor='#333333', linewidth=0.8, corner_radius=0.02,
            fontsize=7, text_align='center', bold=False):
    """
    Add a rounded rectangle with centered text.
    x, y, w, h are in axes-fraction coordinates (0–1).
    """
    box = FancyBboxPatch(
        (x, y), w, h,
        boxstyle=f'round,pad=0,rounding_size={corner_radius}',
        facecolor=fill_color,
        edgecolor=edgecolor,
        linewidth=linewidth,
        transform=ax.transAxes,
        clip_on=False
    )
    ax.add_patch(box)
    ax.text(x + w/2, y + h/2, text,
            ha=text_align, va='center',
            transform=ax.transAxes,
            fontsize=fontsize,
            fontweight='bold' if bold else 'normal',
            color=text_color,
            wrap=True,
            multialignment='center')

def add_arrow(ax, x1, y1, x2, y2, color='#333333', lw=1.0, style='->', dashed=False):
    """Draw an arrow between two axes-fraction coordinates."""
    props = dict(
        arrowstyle=style,
        color=color,
        lw=lw,
        linestyle='dashed' if dashed else 'solid'
    )
    ax.annotate('', xy=(x2, y2), xytext=(x1, y1),
                xycoords='axes fraction', textcoords='axes fraction',
                arrowprops=props)

# ── 5. Draw each panel ────────────────────────────────────────────────────────
# [GENERATED CODE PER PANEL — see Phase 2 instructions]

# ── 6. Figure caption ─────────────────────────────────────────────────────────
fig.text(0.02, 0.01, '<caption text>', ha='left', va='bottom',
         fontsize=7, style='italic', wrap=True)

# ── 7. Export ─────────────────────────────────────────────────────────────────
out_svg = 'output_V6/figures/<name>.svg'
fig.savefig(out_svg, format='svg', bbox_inches='tight', dpi=150)
print(f'SVG saved: {out_svg}')
plt.close()
```

### Critical SVG settings

**Always set `svg.fonttype: 'none'`** in rcParams. This keeps text as `<text>` SVG
elements rather than converting to `<path>` outlines. Without this, text becomes
uneditable in Canva/Inkscape.

### Element reconstruction rules

**Boxes (FancyBboxPatch)**:
- Sample fill_color from original image pixel center of each box
- Set `rounding_size` proportional to observed corner radius
- For titled sub-panels (e.g. "C1 — Texture normalization"): draw two boxes — a
  title bar (colored) on top, a white/light body below
- All text wrapping: use `\n` in text strings, not matplotlib `wrap=True`
  (which is unreliable at small sizes)

**Arrows (FancyArrowPatch / annotate)**:
- Horizontal/vertical only preferred (use waypoints for L-shaped connectors)
- Reproduce arrowhead style: `->`(simple), `-|>`(filled triangle), `<->`(bidirectional)
- For dashed arrows: `linestyle='dashed'`

**Mathematical formulas**:
- Use matplotlib mathtext: `r'$H_{blend} = \max(0, \frac{\min(H,1) - H_0}{1 - H_0})$'`
- Do NOT use `text.usetex=True` (requires full LaTeX install — fragile)
- Set `fontsize` small enough to fit inside the box

**Maps / geographic panels**:
- If the panel contains a raster map that cannot be recreated as vector:
  - Embed it as a `matplotlib.image.AxesImage` (`ax.imshow(...)`)
  - Load from the original image file by cropping to that panel region
  - Annotate on top with vector elements (points, labels, boxes)
  - Note in the script: `# RASTER EMBED — map background not vectorized`

**Legends / color swatches**:
- Use `matplotlib.patches.Rectangle` for color swatches
- Place with `ax.add_patch()` and paired `ax.text()` for labels
- Do NOT use `ax.legend()` — manual placement gives exact control

---

## Phase 3 — SSIM Verification Loop

After writing and running the generation script, execute this verification
loop. **Do not declare success without completing at least one iteration.**

### Step 3a — Render SVG to PNG

```python
# verify_figure.py — run this after each generation
import cairosvg, sys
from PIL import Image
import numpy as np
from skimage.metrics import structural_similarity as ssim

svg_path    = 'output_V6/figures/<name>.svg'
orig_path   = '<original_image_path>'
preview_png = 'output_V6/figures/<name>_render.png'

# Render SVG at same pixel dimensions as original
orig = Image.open(orig_path).convert('RGB')
W, H = orig.size
cairosvg.svg2png(url=svg_path, write_to=preview_png, output_width=W, output_height=H)

# Load render
render = Image.open(preview_png).convert('RGB')

# Resize render to match original if needed
if render.size != orig.size:
    render = render.resize(orig.size, Image.LANCZOS)

# Compute SSIM
orig_arr   = np.array(orig)
render_arr = np.array(render)
score, diff = ssim(orig_arr, render_arr, full=True, channel_axis=2,
                   data_range=255)

print(f'SSIM: {score:.4f}  (threshold: <ssim_threshold>)')

# Find worst panel region
diff_gray = (1 - diff.mean(axis=2))  # higher = more different
# Divide into panel grid and report worst
h, w = diff_gray.shape
for label, (r0,r1,c0,c1) in panel_regions.items():
    region_score = diff_gray[int(r0*h):int(r1*h), int(c0*w):int(c1*w)].mean()
    print(f'  Panel {label}: diff={region_score:.4f}')

sys.exit(0 if score >= <ssim_threshold> else 1)
```

### Step 3b — cairosvg unavailable fallback

If cairosvg fails (Windows cairo library missing), use Inkscape CLI:
```bash
inkscape --export-type=png --export-width=<W> --export-filename="output_V6/figures/<name>_render.png" "output_V6/figures/<name>.svg"
```
If neither is available, use matplotlib's PNG backend directly:
```bash
python3 -c "
import matplotlib.pyplot as plt
# re-run generate script with savefig format='png' instead of 'svg'
"
```

### Step 3c — Iteration protocol

After each SSIM measurement:

1. If `score >= ssim_threshold` → proceed to Phase 4 (export PPTX)
2. If `score < ssim_threshold` → identify the panel(s) with highest diff score, then:
   - Re-analyse that panel in the original image (zoom in with Read tool)
   - Identify the specific mismatch: wrong color? wrong text? wrong box position? missing arrow?
   - Fix exactly that element in `<name>_generate.py`
   - Re-run the generation script
   - Re-run the verification script
   - Repeat

**Maximum iterations before pausing**: 10. After 10 iterations without reaching
`ssim_threshold`, pause and report:
- Current SSIM score
- Which panel is responsible for the remaining gap
- The specific element(s) that cannot be matched exactly (e.g. raster map, complex icon)
- Ask the user: "Current SSIM = X. The remaining difference is in [panel]. Shall I accept
  this score and proceed, or continue iterating?"

### What counts as perceptually identical

The following differences are acceptable and do NOT require iteration:
- Font rendering differences (anti-aliasing, sub-pixel hinting) < 1 px
- Sub-pixel arrow endpoint differences
- JPEG compression artifacts in the original image

The following differences MUST be fixed before stopping:
- Any text that is wrong, missing, or truncated
- Any box that has the wrong fill color (> 10 ΔE in Lab space)
- Any panel that is missing entirely
- Any arrow that points the wrong direction or connects wrong elements
- Panel labels (A, B, C, D) in wrong position

---

## Phase 4 — PPTX Export (for Canva)

Once SSIM is verified, convert the SVG to PPTX so every element is independently
editable in Canva.

Write and run `output_V6/figures/<name>_to_pptx.py`:

```python
"""
Convert verified SVG to Canva-editable PPTX.
Each SVG element → separate PPTX shape (text boxes, rectangles, connectors).

Strategy: parse SVG XML directly and map elements to python-pptx objects.
This gives per-element editability in Canva, unlike importing SVG as-is.
"""
import xml.etree.ElementTree as ET
from pptx import Presentation
from pptx.util import Inches, Pt, Emu
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN
from PIL import Image

# Slide dimensions = original image aspect ratio
orig = Image.open('<original_image_path>')
W_px, H_px = orig.size
ASPECT = W_px / H_px

# Standard widescreen slide: 13.33 × 7.5 inches
SLIDE_W = Inches(13.33)
SLIDE_H = Inches(13.33 / ASPECT)

prs = Presentation()
prs.slide_width  = SLIDE_W
prs.slide_height = SLIDE_H

blank_layout = prs.slide_layouts[6]  # blank
slide = prs.slides.add_slide(blank_layout)

# Parse SVG
tree = ET.parse('output_V6/figures/<name>.svg')
root = tree.getroot()
ns = {'svg': 'http://www.w3.org/2000/svg'}

SVG_W = float(root.get('width',  '1000').replace('pt','').replace('px',''))
SVG_H = float(root.get('height', '600').replace('pt','').replace('px',''))

def svg_to_emu(val, total_svg, total_slide_emu):
    return int(float(val) / total_svg * total_slide_emu)

def hex_to_rgb(hex_str):
    hex_str = hex_str.lstrip('#')
    if len(hex_str) == 3:
        hex_str = ''.join(c*2 for c in hex_str)
    return RGBColor(int(hex_str[0:2],16), int(hex_str[2:4],16), int(hex_str[4:6],16))

# Walk SVG elements and map to PPTX shapes
for elem in root.iter():
    tag = elem.tag.split('}')[-1]  # strip namespace

    if tag == 'rect':
        x = svg_to_emu(elem.get('x','0'), SVG_W, int(SLIDE_W))
        y = svg_to_emu(elem.get('y','0'), SVG_H, int(SLIDE_H))
        w = svg_to_emu(elem.get('width','0'), SVG_W, int(SLIDE_W))
        h = svg_to_emu(elem.get('height','0'), SVG_H, int(SLIDE_H))
        fill = elem.get('fill', '#FFFFFF')
        shape = slide.shapes.add_shape(1, x, y, w, h)  # MSO_SHAPE_TYPE.RECTANGLE
        shape.fill.solid()
        shape.fill.fore_color.rgb = hex_to_rgb(fill)
        shape.line.color.rgb = hex_to_rgb(elem.get('stroke','#000000'))
        shape.line.width = Pt(float(elem.get('stroke-width','1')))

    elif tag == 'text':
        x = svg_to_emu(elem.get('x','0'), SVG_W, int(SLIDE_W))
        y = svg_to_emu(elem.get('y','0'), SVG_H, int(SLIDE_H))
        text = ''.join(elem.itertext())
        fs   = float(elem.get('font-size','8').replace('px','').replace('pt',''))
        tb = slide.shapes.add_textbox(x, y, Inches(3), Inches(0.5))
        tf = tb.text_frame
        tf.word_wrap = True
        p = tf.paragraphs[0]
        run = p.add_run()
        run.text = text
        run.font.size = Pt(fs)
        fill_str = elem.get('fill', '#000000')
        if fill_str not in ('none', ''):
            run.font.color.rgb = hex_to_rgb(fill_str)

    # arrows / paths: embed as grouped image (cannot trivially convert bezier → pptx)
    # They remain visible but as a background image patch

# Fallback: embed full figure as background image for any element not mapped above
# (ensures the PPTX always looks correct even if some SVG paths were skipped)
from pptx.util import Inches
from io import BytesIO
img_buf = BytesIO()
Image.open('output_V6/figures/<name>_render.png').save(img_buf, format='PNG')
img_buf.seek(0)
slide.shapes.add_picture(img_buf, 0, 0, SLIDE_W, SLIDE_H)
# Move picture to back
slide.shapes._spTree.remove(slide.shapes[-1]._element)
slide.shapes._spTree.insert(2, slide.shapes[-1]._element)

prs.save('output_V6/figures/<name>.pptx')
print('PPTX saved: output_V6/figures/<name>.pptx')
print('Import into Canva via: Create design → Import file → select .pptx')
```

**Note on PPTX SVG mapping limitations**: Complex bezier `<path>` elements
(arrows with curves, map outlines) cannot be mapped to native PPTX shapes.
These are embedded as a background image layer. All rectangular boxes, text labels,
and straight-line connectors ARE mapped to native editable PPTX shapes.

---

## Phase 5 — Output Summary

After all phases complete, print:

```
✓ Scientific figure vectorized: output_V6/figures/<name>

  Files created:
    <name>_generate.py      — Python source (edit this to regenerate)
    <name>.svg              — Vector master (edit in Inkscape, Illustrator)
    <name>_render.png       — Raster preview at original resolution
    <name>.pptx             — Canva-editable PPTX (see import instructions)

  Verification:
    SSIM score: X.XXXX (threshold was <ssim_threshold>)
    Iterations needed: N

  How to import into Canva:
    1. Go to canva.com → Create a design
    2. Click "Import file" → select <name>.pptx
    3. Canva opens it as a page — every box, label, and arrow is
       a separate editable element
    4. Click any element to move, resize, recolor, or retype it

  Notes on non-vectorized elements:
    [list any raster embeds, e.g. "Panel B map background: raster embed"]
```

---

## Safety rules

- **Never skip the SSIM loop** — not even on the first attempt
- **Never export PPTX from an unverified SVG**
- **`svg.fonttype: 'none'` is mandatory** — text must stay editable
- **Do not use `text.usetex=True`** — requires full LaTeX, breaks portability
- **Do not invent text** — if text in the original is illegible, mark it as
  `# TODO: verify text` in the script and ask the user
- **Raster embeds**: always note which elements are raster vs vector in the summary
- **Max 10 iterations before pausing** for user input

---

## Project-specific context

- Working directory: `Beluga/` (dredging footprint pipeline, master thesis)
- Figures live in `output_V6/figures/` (per CLAUDE.md)
- Generation scripts live alongside outputs in same directory (for reproducibility)
- Git branch: check `git branch --show-current` before saving
- Typical figures: pipeline infographics (Steps 0–7), SAR/CRI maps, OCIM diagnostics,
  lithology enrichment diagrams
- Domain vocabulary: SAR, CRI, AIS, TSHD, OCIM2-48L, Jdredge, H_index, pl_base,
  dbSEABED — these appear as labels in figures; spell them exactly as in the original

# Cell Biology Image Analysis Scripts

A practical code library written and maintained by **ther** for processing and analyzing experimental images in cell biology research. The library includes automated macro scripts for **ImageJ (Fiji)** and Python-based **deep learning / image processing** scripts, covering wound healing assays, Transwell migration/invasion assays, Western blot quantification, and batch image format unification.

---

## 📂 Table of Contents

- [1. Cell Scratch — Wound Healing Assay](#1-cell-scratch--wound-healing-assay)
- [2. Transwell — Cell Migration/Invasion Counting](#2-transwell--cell-migrationinvasion-counting)
- [3. Western Blot — Band Quantification](#3-western-blot--band-quantification)
- [4. Unify Images — Batch Color & DPI Processing](#4-unify-images--batch-color--dpi-processing)
- [Installation & Dependencies](#-installation--dependencies)
- [License](#-license)

---

## 1. Cell Scratch — Wound Healing Assay

**Scripts**: `Cell Scratch/scratch_0h.ijm`, `Cell Scratch/scratch_48h.ijm`

**Biological Context**: The wound healing (scratch) assay is used to study cell migration. A "scratch" is created in a confluent cell monolayer, and the remaining wound area is measured at different time points (typically 0h and 48h). The relative migration rate is calculated as: `(Area_0h − Area_48h) / Area_0h × 100%`.

### Algorithm Overview

Both scripts use a **Variance filter → Threshold → Morphological Open → Particle Analysis** pipeline:

1. **Variance filter** enhances edges and texture features, making the scratch boundary more distinct from the cell monolayer.
2. **Thresholding** converts the grayscale image into a binary mask where scratches appear white and cells appear black.
3. **Edge masking brushes** paint black rectangles on the left/right margins to exclude non-biological edge interference.
4. **Center white brush** (0h only) bridges physical scratch discontinuities by painting a white band in the center region.
5. **Morphological Open** smooths the binary mask by removing small white noise speckles within the scratch.
6. **Analyze Particles** detects connected white regions above a minimum area threshold.
7. If multiple disconnected scratch regions exist, they are combined into a single ROI before measuring total area.

### scratch_0h.ijm — 0-Hour Baseline

**Use case**: Quantify the initial wound area right after scratching.

#### Tunable Parameters

| Parameter | Default | Description |
|---|---|---|
| `xMin` | `370` | Left black brush boundary. Everything to the left is masked out (black) to exclude edge artifacts. |
| `xMax` | `880` | Right black brush boundary. Everything to the right is masked out. |
| `centerStart` | `510` | Start X of the center white brush — paints a white stripe to repair physical scratch gaps. |
| `centerEnd` | `760` | End X of the center white brush. |
| `MINIMAL_SIZE` | `100000` | Minimum particle area (px²). Smaller regions are treated as noise and filtered out. |
| `VARIANCE_FILTER_RADIUS` | `3` | Radius for the variance filter. Larger values enhance broader features. |
| `THRESHOLD` | `50` | Upper threshold (0–255) for binary mask conversion. Lower values are stricter. |
| `RADIUS_CLOSE` | `5` | Iterations for the morphological Open operation. Higher values remove more noise but may erode the scratch boundary. |

#### How to Use

1. Open **Fiji (ImageJ)**.
2. Go to `Plugins → Macros → Run...` and select `scratch_0h.ijm`.
3. In the first dialog, select the **input folder** containing your 0h scratch images (`.jpg` or `.tif`).
4. In the second dialog, select an **output folder** for processed results.
5. The script runs in batch mode. For each image, it will:
   - Generate a `*_processed.jpg` file showing the detected scratch area outlined in yellow.
   - Record the image name and measured scratch area (px²) in a custom table.
6. When all images are processed, a `Summary_Results.csv` file is saved to the output folder with columns: `Image_Name`, `Total_Area`.
7. Use the `Total_Area` values as your 0h baseline for migration rate calculation.

#### When to Adjust Parameters

| Symptom | Likely Fix |
|---|---|
| Scratch area is over-segmented (too many small fragments) | Increase `RADIUS_CLOSE` or decrease `VARIANCE_FILTER_RADIUS` |
| Scratch boundary is not fully detected | Decrease `THRESHOLD` (e.g., to 30) or increase `VARIANCE_FILTER_RADIUS` |
| Edge debris is being counted as scratch | Adjust `xMin`/`xMax` to clip the affected margins |
| Scratch has physical breaks/gaps causing multiple ROIs | Activate and adjust `centerStart`/`centerEnd` to bridge the gap with white paint |
| Small noise speckles being detected | Increase `MINIMAL_SIZE` |

---

### scratch_48h.ijm — 48-Hour Endpoint

**Use case**: Quantify the remaining wound area at the experimental endpoint (typically 48h). This is structurally identical to `scratch_0h.ijm` but tuned for larger micrographs at a later time point.

#### Tunable Parameters

| Parameter | Default | Description |
|---|---|---|
| `xMin` | `1000` | Left black brush boundary. |
| `xMax` | `4400` | Right black brush boundary. |
| `centerStart` / `centerEnd` | Commented out | Center brush disabled — usually not needed at 48h since the scratch has partially healed. |
| `MINIMAL_SIZE` | `10000` | Minimum particle area. Lower than 0h to capture partially healed, smaller scratch regions. |
| `VARIANCE_FILTER_RADIUS` | `5` | Larger radius for broader scratch features at the endpoint. |
| `THRESHOLD` | `25` | Lower threshold (stricter) to handle weaker contrast at 48h. |
| `RADIUS_CLOSE` | `6` | More aggressive noise removal for the noisier endpoint images. |

#### How to Use

Same workflow as `scratch_0h.ijm` — run via `Plugins → Macros → Run...`, select input/output folders. Results are saved in `Summary_Results.csv` with image name and total scratch area.

#### Migration Rate Calculation

After running both 0h and 48h scripts on corresponding image pairs:

```
Relative Migration Rate (%) = (Area_0h − Area_48h) / Area_0h × 100
```

Combine the two CSV files in Excel/Prism to perform this calculation per image pair.

---

## 2. Transwell — Cell Migration/Invasion Counting

**Script**: `Transwell/cellpose_count.py`

**Biological Context**: Transwell assays measure the ability of cells to migrate through a porous membrane. After staining, cells on the bottom side of the membrane are imaged and counted. Manual counting is tedious and subjective; this script automates it with deep learning.

### Algorithm Overview

Uses **Cellpose 3.0** (`cyto3` model) — a state-of-the-art deep learning model for cell segmentation. Key design decisions:

| Feature | Implementation | Rationale |
|---|---|---|
| **Input channel** | Green channel only (index 1), inverted | Most nuclear/cytoplasmic stains (e.g., crystal violet, DAPI) have strongest signal in green or are converted to grayscale |
| **Cell diameter** | Auto-calculated per image: `d = max(20, round(0.04525 × diagonal − 51.44))` | Empirically derived formula that maps image size to typical cell size |
| **Flow threshold** | `0.8` (raised from default 0.4) | Relaxes shape constraints to accommodate round and square-ish regular cells |
| **Cellprob threshold** | `−0.1` (lowered from default 0.0) | Prevents edge pixels from being discarded on regular-shaped cells |
| **Min size filter** | `π × (d/2)² × 0.2` | Automatically filters objects smaller than 20% of the expected cell area |
| **Centroid calculation** | Geometric moments (with distance-transform fallback) | More accurate center for regular shapes than distance-transform alone |
| **Boundary smoothing** | Polygon approximation (`epsilon = 0.005 × perimeter`) | Removes pixel jaggies for journal-quality outlines |

### Output Files

For each input image, three output images are generated inside `{diameter}pixel/{image_name}/`:

| File | Description |
|---|---|
| `*_Outlines.*` | Original image with each cell outlined in a unique color and numbered with its Cell ID |
| `*_LabelMaps.*` | Pseudo-color segmentation map (each cell randomly colored, black background) |
| `*_Combined.*` | Side-by-side horizontal concatenation of Outlines (left) and LabelMaps (right) |

Two CSV files are saved to the input folder:

**AI_Result.csv** (summary per image):

| Column | Description |
|---|---|
| `File Name` | Original image filename |
| `Auto Diam (px)` | Cell diameter used for this image |
| `Count` | Number of cells detected |
| `Total Area` | Sum of all cell areas (px²) |
| `Average Size` | Mean cell area (px²) |
| `% Area` | (Total Area / Image Area) × 100 |
| `Image Area` | Total image area (px²) |

**AI_Detail_Result.csv** (per-cell data):

| Column | Description |
|---|---|
| `File Name` | Source image |
| `Auto Diam (px)` | Diameter used |
| `Cell ID` | Unique cell number (matches labels on Outlines image) |
| `Area` | Individual cell area (px²) |
| `Centroid_X` | X coordinate of cell center |
| `Centroid_Y` | Y coordinate of cell center |

### How to Use

1. **Install dependencies** (see [Installation](#-installation--dependencies)).
2. Place all Transwell images (`.tif`, `.png`, `.jpg`, `.jpeg`) in a single folder.
3. Run the script:
   ```bash
   cd Transwell
   python cellpose_count.py
   ```
4. In the GUI dialog, select the folder containing your images.
5. **First run only**: Cellpose will download the `cyto3` model weights (~100 MB). This only happens once.
6. A dialog pops up showing **auto-calculated cell diameters** grouped by image size. For each group, you can:
   - Accept the auto-calculated value (default).
   - Manually enter a different pixel diameter.
7. Click **OK** to start batch processing. Progress is printed to the terminal.
8. Results are saved inside the input folder under `{diameter}pixel/` subdirectories.

#### Tips for Best Results

- **Check a few Outline images first**: Verify that cells are correctly segmented. If cells are being missed or merged, re-run and adjust the diameter in the GUI.
- **Choosing the right diameter**: If cells are under-segmented (multiple cells merged into one), try a smaller diameter. If over-segmented (one cell split into pieces), try a larger diameter.
- **GPU acceleration**: The script enables GPU by default (`gpu=True`). If you lack a CUDA-capable GPU, change to `gpu=False` (much slower).
- **Multi-resolution datasets**: If your images have different magnifications, the auto-grouping by diagonal size will present separate diameter entries for each resolution group.

---

## 3. Western Blot — Band Quantification

**Script**: `Western Blot/wb1.0.ijm`

**Biological Context**: Western blotting detects specific proteins via antibody staining. The intensity (optical density) of each band is proportional to protein abundance. This script automates band detection and quantification from gel/blot images.

### Two Analysis Modes

The script offers two modes for defining band positions:

| Mode | How It Works | Best For |
|---|---|---|
| **Line Method** | Draw a horizontal line across the lane. The script automatically detects bands, matches the count to your expected lane number, and generates measurement boxes. | Standard blots with clear, regularly spaced bands |
| **Dual-Point Method** | Manually click the left and right edges of each individual band. The script uses these points to precisely center measurement boxes. | Irregular blots, unequal band widths, tilted bands, or when you need per-band manual control |

### Step-by-Step Usage

#### Step 1: Open Image & Draw Line

1. Open your Western blot image in Fiji.
2. Select the **Straight Line** tool (or Segmented/Freehand Line).
3. Draw a horizontal line across all lanes, perpendicular to the band migration direction.
4. Run the script via `Plugins → Macros → Run...` → select `wb1.0.ijm`.

#### Step 2: Configure Parameters

| Parameter | Default | Description |
|---|---|---|
| **Execution Mode** | Line Method | Choose the band detection strategy (see table above). |
| **Target Lane Count** | `4` | (Line Method only) The expected number of lanes/bands. The script will merge or split detected regions to match this count. |
| **Lane Height H (px)** | `60` | Height of the line used for straightening. Should roughly match the band thickness. |
| **Height Multiplier** | `1.1` | Multiplies the detected band height to create the measurement rectangle. Use 1.5× for Dual-Point Method to capture more background for normalization. |
| **Auto-adaptive Width** | Off | If enabled, each lane's measurement box uses its own detected band width rather than a uniform width. |
| **Expand Width by 5%** | Off | If enabled, each box is horizontally expanded by 5% to ensure full band coverage. |

#### Step 3: Band Delimitation

**If using Line Method**: The script proceeds automatically — no further user input needed for band detection.

**If using Dual-Point Method**: A dialog instructs you to click on the image:
- Click the **left edge**, then the **right edge** of **each band** in sequence.
- This gives each band its own biological width (bands may differ in size).
- Click **OK** when all bands are marked.
- The number of points must be even (2 per band).

#### Step 4: Calibration & Review

After automatic/manual box generation:
- All measurement rectangles appear as yellow boxes overlaid on the image.
- **Review each box**: If any box is slightly misaligned, you can manually drag its edges on the image, then click the corresponding `Lane_N` entry in the ROI Manager and press **Update**.
- Click **OK** when satisfied to proceed with measurement.

#### Step 5: Results

The script quantifies the straightened image with:
- **Measurement**: `Area`, `Mean` (mean gray value), `Integrated Density` (area × mean), to 3 decimal places.

Three output files are saved (auto-incremented to avoid overwriting):

| File | Content |
|---|---|
| `*_{LineMode/DualPointMode}_{100%/105%}.csv` | Quantification results table |
| `*_{LineMode/DualPointMode}_{100%/105%}.tif` | Straightened image at 600 DPI |
| `*_{LineMode/DualPointMode}_{100%/105%}.png` | Flattened image with ROI boxes overlaid |

#### Step 6: Batch Processing

After one image is complete, a dialog asks: **"Single analysis workflow complete! Load the next band?"**

- Click **Yes** to select another image and repeat the workflow.
- Click **No** to exit.

### Technical Details

The **Line Method** uses a sophisticated lane-count matching algorithm:

1. **Preprocessing**: Straighten → 8-bit → Invert → Subtract Background (rolling=40) → Median (r=2) → Enhance Contrast → Otsu Auto-threshold → Mask → Fill Holes → Watershed.
2. **Particle detection**: `Analyze Particles` (size ≥ 5 px).
3. **If too many ROIs**: Iteratively removes or merges the poorest-fitting ROI based on a cost function that considers area deviation, pitch alignment, and gap patterns.
4. **If too few ROIs**: Splits wide ROIs, fills large gaps, and adds edge lanes to reach the target count.
5. **Sector assignment**: Divides the image into N equal horizontal sectors and selects the best ROI per sector. Sectors without a clear band ("shallow") fall back to median-based estimates.
6. **Box generation**: Creates measurement rectangles at each ROI center with configurable width and height.

---

## 4. Unify Images — Batch Color & DPI Processing

**Scripts**: `Unify Images/jpg.py`, `Unify Images/dpi.py`

**Biological Context**: Microscopy images from different sessions or microscopes often have inconsistent brightness, color balance, and resolution. Journals typically require images at **300–600 DPI** in **TIFF** format. These scripts standardize entire image sets using the **Reinhard color transfer algorithm**.

### Algorithm: Reinhard L*a*b* Color Transfer

Both scripts implement the classic Reinhard et al. (2001) color transfer method:

1. Convert both the reference image and target image from BGR to **CIE L\*a\*b\*** color space (float32).
2. For each of the three channels — **L** (lightness), **a** (green–red), **b** (blue–yellow):
   - Compute the mean and standard deviation of the reference image: `μ_ref`, `σ_ref`.
   - Compute the mean and standard deviation of the target image: `μ_tgt`, `σ_tgt`.
   - Transform the target channel: `new_value = (old_value − μ_tgt) × (σ_ref / σ_tgt) + μ_ref`
3. Clip all values to the safe **[0, 255]** range (prevents the "black image" bug common in ImageJ implementations).
4. Convert back from L\*a\*b\* to BGR.

**Why L\*a\*b\*?** Unlike RGB, L\*a\*b\* separates lightness from color information, allowing brightness and color tone to be matched independently without distorting cellular structures.

### jpg.py — Color Unification (Original Format)

Use when you want to harmonize colors across images while keeping the original format and resolution.

#### How to Use

1. Run:
   ```bash
   cd "Unify Images"
   python jpg.py
   ```
2. **Step 1**: Select a **reference image** — the image whose brightness and color you want all other images to match.
3. **Step 2**: Select the **input folder** containing images to be unified.
4. **Step 3**: Select the **output folder** where processed images will be saved.
5. The script batch-processes all `.png`, `.jpg`, `.jpeg`, `.tif`, `.tiff` files.
6. Each output file keeps its **original filename and extension**.

#### Supported Formats
`.png`, `.jpg`, `.jpeg`, `.tif`, `.tiff`

---

### dpi.py — Color Unification + 600 DPI TIFF

Use for **journal submission** preparation: color unification + DPI standardization + lossless TIFF output.

#### How to Use

1. Run:
   ```bash
   cd "Unify Images"
   python dpi.py
   ```
2. **Steps 1–3**: Same as `jpg.py` — select reference image, input folder, output folder.
3. Every output file is:
   - **Format**: TIFF (`.tif`)
   - **DPI**: 600 (suitable for all major journals, can be changed in the code)
   - **Compression**: LZW lossless (reduces file size without quality loss)

#### Key Differences from jpg.py

| Feature | `jpg.py` | `dpi.py` |
|---|---|---|
| Output format | Original format preserved | Always `.tif` |
| DPI metadata | Not modified | Forced to 600 DPI |
| Compression | Original | LZW lossless |
| Use case | General color normalization | Journal submission preparation |

#### Changing DPI

To target a different DPI value, edit [dpi.py:30](Unify Images/dpi.py#L30):
```python
pil_img.save(out_path, format="TIFF", dpi=(600, 600), compression="tiff_lzw")
```
Change `(600, 600)` to your desired DPI (e.g., `(300, 300)` for journals requiring 300 DPI).

#### Choosing a Reference Image

The reference image determines the target brightness and color tone for all processed images. Tips:
- Choose an image with **representative staining intensity** from your experiment.
- The reference should be the best-quality image in the batch (no over/under-exposure).
- For multi-condition experiments, consider using a control group image as reference.
- The algorithm is **gentle** — it only shifts brightness and color balance, preserving all cellular details and local contrast.

---

## 🛠️ Installation & Dependencies

### ImageJ Macros (`.ijm`)

1. Download and install **[Fiji](https://imagej.net/Fiji/Downloads)** (includes all required plugins).
2. No additional dependencies needed — all functions use built-in ImageJ commands.
3. Minimum ImageJ version: **1.53** (for `wb1.0.ijm`).

### Python Scripts (`.py`)

**Python 3.8+** required.

```bash
# Core dependencies for all Python scripts
pip install opencv-python pandas scikit-image numpy Pillow

# Additional dependency for cellpose_count.py only
pip install cellpose

# Optional: GPU acceleration for Cellpose (CUDA 12.4)
# pip install torch torchvision --index-url https://download.pytorch.org/whl/cu124
```

If the Cellpose import fails, the script prints the exact install command and exits gracefully.

---

## 📄 License

This project is open-sourced under the [MIT License](LICENSE). Anyone is free to use, modify, and distribute, but please retain the original author (**ther**) attribution.

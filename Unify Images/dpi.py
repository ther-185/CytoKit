import os
import tkinter as tk
from tkinter import filedialog
import cv2
import numpy as np
from PIL import Image  # [New]: Library specifically for writing DPI and TIFF metadata

def read_image(path):
    # Use Pillow to read, compatible with tif, png, and various formats
    img = Image.open(path)
    # Uniformly convert to RGB format, then to BGR format required by OpenCV
    img_rgb = img.convert('RGB')
    return cv2.cvtColor(np.array(img_rgb), cv2.COLOR_RGB2BGR)

def save_image(path, img):
    """
    [Core Change]: Abandon OpenCV saving, use PIL to force 600 DPI and save as lossless TIFF
    """
    # 1. OpenCV reads colors in BGR order, Pillow requires standard RGB, must flip channels first!
    img_rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)

    # 2. Convert to Pillow image object
    pil_img = Image.fromarray(img_rgb)

    # 3. Force change extension to .tif, the lossless format required by all high-quality journals
    base, _ = os.path.splitext(path)
    out_path = base + ".tif"

    # 4. Save! Force-stamp 600 DPI academic-grade metadata, and use LZW lossless compression to reduce file size
    pil_img.save(out_path, format="TIFF", dpi=(600, 600), compression="tiff_lzw")

def lab_color_transfer(target_img, ref_img):
    # Convert source and reference images from standard BGR to L*a*b* color space
    ref_lab = cv2.cvtColor(ref_img, cv2.COLOR_BGR2LAB).astype(np.float32)
    tgt_lab = cv2.cvtColor(target_img, cv2.COLOR_BGR2LAB).astype(np.float32)

    for i in range(3):
        ref_mean, ref_std = ref_lab[:, :, i].mean(), ref_lab[:, :, i].std()
        tgt_mean, tgt_std = tgt_lab[:, :, i].mean(), tgt_lab[:, :, i].std()

        if tgt_std != 0:
            tgt_lab[:, :, i] = ((tgt_lab[:, :, i] - tgt_mean) * (ref_std / tgt_std)) + ref_mean

    # Force numerical clipping to prevent blackening
    tgt_lab = np.clip(tgt_lab, 0, 255).astype(np.uint8)

    # Convert back to BGR
    result_bgr = cv2.cvtColor(tgt_lab, cv2.COLOR_LAB2BGR)
    return result_bgr

def main():
    try:
        root = tk.Tk()
        root.withdraw()

        print("==================================================")
        print("   Cell Image L*a*b* Academic-Grade Color Unification Tool (600 DPI)   ")
        print("==================================================")

        print("Step 1/3: Please select the [Reference Image]...")
        ref_path = filedialog.askopenfilename(title="Select a standard brightness and color reference image")
        if not ref_path: return

        print("Step 2/3: Please select the [Images to Process] folder...")
        input_dir = filedialog.askdirectory(title="Select input folder")
        if not input_dir: return

        print("Step 3/3: Please select the [Save Results] folder...")
        output_dir = filedialog.askdirectory(title="Select output folder")
        if not output_dir: return

        print("\nReading reference image features...")
        reference = read_image(ref_path)

        valid_exts = ('.png', '.jpg', '.jpeg', '.tif', '.tiff')
        files = [f for f in os.listdir(input_dir) if f.lower().endswith(valid_exts)]

        print(f"\nStarting batch processing, {len(files)} images total, all will be output as 600 DPI TIFF format...")

        for i, filename in enumerate(files):
            img_path = os.path.join(input_dir, filename)
            out_path = os.path.join(output_dir, filename)

            try:
                image = read_image(img_path)
                matched_img = lab_color_transfer(image, reference)
                save_image(out_path, matched_img)
                print(f"[{i+1}/{len(files)}] Success -> {filename.split('.')[0]}.tif")

            except Exception as e:
                print(f"[{i+1}/{len(files)}] Failed -> {filename}: Error {e}")

        print("\n🎉 Processing complete! Right-click and check the output image properties, DPI is locked at 600.")
    except Exception as e:
        import traceback
        traceback.print_exc()
        print(f"\nAn unexpected error occurred: {e}")
    finally:
        input("\nPress Enter to exit...")

if __name__ == "__main__":
    main()

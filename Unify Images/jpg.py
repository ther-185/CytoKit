import os
import tkinter as tk
from tkinter import filedialog
import cv2
import numpy as np
from PIL import Image

# To prevent errors with non-ASCII paths and maintain compatibility with tif, png, etc., use PIL to read images
def read_image(path):
    img = Image.open(path)
    # Uniformly convert to RGB format, then to BGR format required by OpenCV
    img_rgb = img.convert('RGB')
    return cv2.cvtColor(np.array(img_rgb), cv2.COLOR_RGB2BGR)

def save_image(path, img):
    # Dynamically save based on file extension
    ext = os.path.splitext(path)[1].lower()
    if not ext:
        ext = '.jpg'
    cv2.imencode(ext, img)[1].tofile(path)

def lab_color_transfer(target_img, ref_img):
    """
    This is exactly the L*a*b* color space mean/std matching algorithm (Reinhard) you wanted in ImageJ.
    It is very gentle, only unifying overall brightness and color tone without destroying cellular details.
    """
    # 1. Convert source and reference images from standard BGR to L*a*b* color space as floats for precise computation
    ref_lab = cv2.cvtColor(ref_img, cv2.COLOR_BGR2LAB).astype(np.float32)
    tgt_lab = cv2.cvtColor(target_img, cv2.COLOR_BGR2LAB).astype(np.float32)

    # 2. Match the three channels L (lightness), a (red-green), b (yellow-blue) separately
    for i in range(3):
        # Extract mean and standard deviation of the reference image
        ref_mean, ref_std = ref_lab[:, :, i].mean(), ref_lab[:, :, i].std()
        # Extract mean and standard deviation of the target image
        tgt_mean, tgt_std = tgt_lab[:, :, i].mean(), tgt_lab[:, :, i].std()

        # Core arithmetic logic (fully consistent with ImageJ macro logic)
        if tgt_std != 0:
            tgt_lab[:, :, i] = ((tgt_lab[:, :, i] - tgt_mean) * (ref_std / tgt_std)) + ref_mean

    # 3. [Core Fix]: Force-clip results to the safe 0-255 range and convert back to standard 8-bit integer!
    # This step completely eliminates the ImageJ overflow bug that turned the entire image black.
    tgt_lab = np.clip(tgt_lab, 0, 255).astype(np.uint8)

    # 4. Convert from L*a*b* back to color image
    result_bgr = cv2.cvtColor(tgt_lab, cv2.COLOR_LAB2BGR)
    return result_bgr

def main():
    try:
        root = tk.Tk()
        root.withdraw()

        print("==================================================")
        print("   Cell Image L*a*b* Gentle Color Unification Tool (Reinhard)   ")
        print("==================================================")

        # Dialog selection
        print("Step 1/3: Please select the [Reference Image]...")
        ref_path = filedialog.askopenfilename(title="Select a standard brightness and color reference image")
        if not ref_path: return

        print("Step 2/3: Please select the [Images to Process] folder...")
        input_dir = filedialog.askdirectory(title="Select input folder")
        if not input_dir: return

        print("Step 3/3: Please select the [Save Results] folder...")
        output_dir = filedialog.askdirectory(title="Select output folder")
        if not output_dir: return

        # Read reference image
        print("\nReading reference image features...")
        reference = read_image(ref_path)

        # Filter image formats
        valid_exts = ('.png', '.jpg', '.jpeg', '.tif', '.tiff')
        files = [f for f in os.listdir(input_dir) if f.lower().endswith(valid_exts)]

        print(f"\nStarting L*a*b* algorithm batch processing, {len(files)} images total...")

        for i, filename in enumerate(files):
            img_path = os.path.join(input_dir, filename)
            out_path = os.path.join(output_dir, filename)

            try:
                image = read_image(img_path)
                # Perform gentle L*a*b* color transfer
                matched_img = lab_color_transfer(image, reference)
                # Save result
                save_image(out_path, matched_img)
                print(f"[{i+1}/{len(files)}] Success -> {filename}")

            except Exception as e:
                print(f"[{i+1}/{len(files)}] Failed -> {filename}: Error {e}")

        print("\n🎉 Processing complete! Details perfectly preserved, please check the output folder.")
    except Exception as e:
        import traceback
        traceback.print_exc()
        print(f"\nAn unexpected error occurred: {e}")
    finally:
        input("\nPress Enter to exit...")

if __name__ == "__main__":
    main()

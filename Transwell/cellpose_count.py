import os
import warnings
warnings.filterwarnings('ignore')
os.environ["PYTHONWARNINGS"] = "ignore"

import cv2
import numpy as np
import pandas as pd
import tkinter as tk
from tkinter import filedialog, messagebox, simpledialog
from skimage import measure, color

try:
    from cellpose import models, utils
except ImportError:
    print("Error: cellpose library not found!")
    print("Please run the following command in the VS Code terminal to install:")
    print("pip install cellpose opencv-python pandas scikit-image numpy")
    exit()

def main():
    root = tk.Tk()
    root.withdraw()
    messagebox.showinfo("Info", "Please select the image folder to process")
    input_dir = filedialog.askdirectory(title="Select image folder")

    if not input_dir:
        print("No folder selected, program exited.")
        return

    csv_path = os.path.join(input_dir, "AI_Result.csv")
    detail_csv_path = os.path.join(input_dir, "AI_Detail_Result.csv")

    print("Loading pretrained model (first run may need to download model weights)...")
    # Enable GPU acceleration
    model = models.CellposeModel(gpu=True, model_type='cyto3')
    #pip install torch torchvision --index-url https://download.pytorch.org/whl/cu124
    results = []
    detail_results = []
    valid_extensions = ('.tif', '.png', '.jpg', '.jpeg')
    file_list = [f for f in os.listdir(input_dir) if f.lower().endswith(valid_extensions)]

    if not file_list:
        print("No supported image formats found in the specified folder.")
        return

    print("Pre-scanning image size distribution...")
    diam_counts = {}
    for f in file_list:
        img_test = cv2.imread(os.path.join(input_dir, f), cv2.IMREAD_UNCHANGED)
        if img_test is not None:
            h, w = img_test.shape[:2]
            diag = (w**2 + h**2)**0.5
            d = int(max(20, round(0.04525 * diag - 51.44)))
            diam_counts[d] = diam_counts.get(d, 0) + 1

    user_diam_overrides = {}
    if diam_counts:
        diag_win = tk.Toplevel(root)
        diag_win.title("Set Cell Diameter")
        tk.Label(diag_win, text="The following cell diameter groups have been calculated. Please confirm or modify:").grid(row=0, column=0, columnspan=2, padx=10, pady=10)

        entries = {}
        for idx, (d, c) in enumerate(diam_counts.items(), start=1):
            tk.Label(diag_win, text=f"Auto-calculated: {d}px ({c} images) -> Modify to:").grid(row=idx, column=0, sticky='e', padx=5, pady=5)
            ent = tk.Entry(diag_win, width=10)
            ent.insert(0, str(d))
            ent.grid(row=idx, column=1, sticky='w', padx=5, pady=5)
            entries[d] = ent

        def on_ok():
            for d, ent in entries.items():
                try:
                    user_diam_overrides[d] = int(ent.get())
                except ValueError:
                    user_diam_overrides[d] = d
            diag_win.destroy()

        tk.Button(diag_win, text="OK", command=on_ok, width=15).grid(row=len(diam_counts)+1, column=0, columnspan=2, pady=10)

        diag_win.update_idletasks()
        w = diag_win.winfo_width()
        h = diag_win.winfo_height()
        ws = diag_win.winfo_screenwidth()
        hs = diag_win.winfo_screenheight()
        x = (ws//2) - (w//2)
        y = (hs//2) - (h//2)
        diag_win.geometry('+%d+%d' % (x, y))

        diag_win.attributes("-topmost", True)
        diag_win.focus_force()
        diag_win.grab_set()
        root.wait_window(diag_win)

    print(f"Found {len(file_list)} images, starting batch segmentation...")

    for i, file_name in enumerate(file_list, 1):
        print(f"[{i}/{len(file_list)}] Processing: {file_name}")
        img_path = os.path.join(input_dir, file_name)

        # Read image using OpenCV
        img = cv2.imread(img_path)
        if img is None:
            continue

        img_height, img_width = img.shape[:2]

        # Determine final diameter based on dynamic mapping table
        diag_len = (img_width**2 + img_height**2)**0.5
        orig_diam = int(max(20, round(0.04525 * diag_len - 51.44)))

        ai_diam = user_diam_overrides.get(orig_diam, orig_diam)
        log_diam_name = str(ai_diam)
        auto_min_size = int(3.14159 * ((ai_diam / 2) ** 2) * 0.2)
        print(f"     => Image size {img_width}x{img_height}, using diameter: {ai_diam}px")

        # Prepare image-specific three-level folder layout
        base_name, ext = os.path.splitext(file_name)
        diam_folder = os.path.join(input_dir, f"{log_diam_name}pixel")
        img_folder = os.path.join(diam_folder, base_name)
        os.makedirs(img_folder, exist_ok=True)

        green_channel = img[:, :, 1]
        img_inv = cv2.bitwise_not(green_channel)


        masks, flows, styles = model.eval(
            img_inv,
            diameter=ai_diam,
            flow_threshold=0.8,       # [Modification] Increase flow_threshold to relax shape constraints, perfectly adapting to round-ish, square regular cells
            cellprob_threshold=-0.1,  # [Modification] Fine-tune probability threshold to prevent regular edge pixels from being accidentally discarded
            min_size=auto_min_size
        )

        props = measure.regionprops(masks)
        count = len(props)
        total_area = sum(p.area for p in props)
        image_area = img_width * img_height

        avg_size = total_area / count if count > 0 else 0
        percent_area = (total_area / image_area) * 100

        outline_img = img.copy()

        # Fix random seed to ensure consistent pseudo-color assignment across multiple runs on the same image set
        np.random.seed(42)

        for prop in props:
            c_id = prop.label    # Get individual cell ID
            c_area = prop.area   # Get individual area

            # Generate a random high-contrast bright BGR color for each cell
            bgr_color = (int(np.random.randint(50, 255)), int(np.random.randint(50, 255)), int(np.random.randint(150, 255)))

            cell_mask = (masks == c_id).astype(np.uint8)

            # [Modification] For round-ish, square shapes, distance transform may cause slight center offset due to plateau effect
            # Use connected component geometric moments to compute the most perfect absolute visual center inside regular shapes
            M = cv2.moments(cell_mask)
            if M["m00"] != 0:
                cx = int(M["m10"] / M["m00"])
                cy = int(M["m01"] / M["m00"])
            else:
                dist_transform = cv2.distanceTransform(cell_mask, cv2.DIST_L2, 5)
                _, max_val, _, max_loc = cv2.minMaxLoc(dist_transform)
                cx, cy = max_loc  # This cx, cy is guaranteed to be at the most central position inside the cell body!

            # Get text dimensions to precisely center the entire string on this core point
            text_str = str(c_id)
            font_scale = 0.3
            thickness = 1
            font = cv2.FONT_HERSHEY_SIMPLEX
            (text_width, text_height), _ = cv2.getTextSize(text_str, font, font_scale, thickness)

            # Correct starting coordinates so the number is drawn perfectly centered at (cx, cy)
            text_x = int(cx - text_width / 2)
            text_y = int(cy + text_height / 2)


            contours, _ = cv2.findContours(cell_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)

            # [Modification] Use polygon approximation to remove pixel jaggies from predicted edges
            # Thus perfectly smoothing and restoring the external curvature of roundish shapes and straight contours of squares
            if contours:
                epsilon = 0.005 * cv2.arcLength(contours[0], True)
                approx = cv2.approxPolyDP(contours[0], epsilon, True)
                # Draw the cell's individually colored outline boundary on the original image
                cv2.drawContours(outline_img, [approx], -1, bgr_color, 2)

            # Draw the number at the center point of the deepest inscribed circle
            cv2.putText(outline_img, text_str, (text_x, text_y),
                        font, font_scale, (0, 0, 0), thickness, cv2.LINE_AA)

            # Append to detailed results list
            detail_results.append({
                "File Name": file_name,
                "Auto Diam (px)": ai_diam,
                "Cell ID": c_id,
                "Area": c_area,
                "Centroid_X": round(cx, 1),
                "Centroid_Y": round(cy, 1)
            })

        cv2.imwrite(os.path.join(img_folder, f"{base_name}_Outlines{ext}"), outline_img)


        label_rgb = color.label2rgb(masks, bg_label=0, bg_color=(0, 0, 0))
        # skimage outputs 0.0~1.0 RGB floats, convert to 0-255 BGR format for saving
        label_bgr = (label_rgb[:, :, ::-1] * 255).astype(np.uint8)

        cv2.imwrite(os.path.join(img_folder, f"{base_name}_LabelMaps{ext}"), label_bgr)


        # Use numpy.hstack to horizontally concatenate outline and pseudo-color images (left: outline, right: label)
        combined_img = np.hstack((outline_img, label_bgr))
        cv2.imwrite(os.path.join(img_folder, f"{base_name}_Combined{ext}"), combined_img)


        results.append({
            "File Name": file_name,
            "Auto Diam (px)": ai_diam,
            "Count": count,
            "Total Area": total_area,
            "Average Size": round(avg_size, 3),
            "% Area": round(percent_area, 3),
            "Image Area": image_area
        })


    if results:
        # Save: summary statistics table for all photos
        df = pd.DataFrame(results)
        df.to_csv(csv_path, index=False, encoding='utf-8-sig')


        detail_csv_path = os.path.join(input_dir, "AI_Detail_Result.csv")
        df_details = pd.DataFrame(detail_results)
        df_details.to_csv(detail_csv_path, index=False, encoding='utf-8-sig')

        print(f"\nProcessing complete! Results saved to:\nSummary: {csv_path}\nDetails: {detail_csv_path}")
        messagebox.showinfo("Done", f"Processed {len(results)} images in total.")

if __name__ == '__main__':
    main()

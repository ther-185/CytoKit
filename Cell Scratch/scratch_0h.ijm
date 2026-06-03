// === ⚙️ Parameter Configuration ===
// 1. Range & Mask Settings (X-axis coordinates)
xMin = 370;           // Left black brush boundary: everything to the left is painted black (exclude edge interference)
xMax = 880;           // Right black brush boundary: everything to the right is painted black (exclude edge interference)
centerStart = 510;    // Center white brush start: forced white to eliminate physical scratch interference
centerEnd = 760;      // Center white brush end: forced white to eliminate physical scratch interference

// 2. Core Algorithm Parameters
MINIMAL_SIZE = 100000; // Minimum area threshold
VARIANCE_FILTER_RADIUS = 3;
THRESHOLD = 50;
RADIUS_CLOSE = 5;
// =====================

inputDir = getDirectory("Please select the [Input] folder containing scratch images");
outputDir = getDirectory("Please select the [Output] folder to save processed results");
fileList = getFileList(inputDir);

// 📊 Core fix: create a completely independent custom table to prevent system auto-clearing
tableName = "Scratch_Data_Final";
Table.create(tableName);
rowIndex = 0; // Track the current row being written

roiManager("reset");
setBatchMode(true);

for (i = 0; i < fileList.length; i++) {
    file = fileList[i];
    if (endsWith(toLowerCase(file), ".jpg") || endsWith(toLowerCase(file), ".tif")) {

        open(inputDir + file);
        originalTitle = getTitle();
        run("Duplicate...", "title=Processing");

        // --- 🎯 Core Algorithm Processing ---
        run("8-bit");
        run("Variance...", "radius=" + VARIANCE_FILTER_RADIUS);
        run("8-bit");

        setThreshold(0, THRESHOLD);
        setOption("BlackBackground", true);
        run("Convert to Mask", " black"); // Scratches are white, cells are black

        // --- 🧱 [Edge Black Brush]: clip X-axis range ---
        setColor(0); // Set color to black (cells)
        fillRect(0, 0, xMin, getHeight());
        fillRect(xMax, 0, getWidth() - xMax, getHeight());

        // --- 🖌️ [Center White Brush]: forcibly fix breaks caused by physical scratches ---
        setColor(255); // Set color to white (scratches)
        fillRect(centerStart, 0, centerEnd - centerStart, getHeight());

        // Morphological repair
        run("Options...", "iterations=" + RADIUS_CLOSE + " count=1 pad black do=Open");
        run("Options...", "iterations=1 count=1 black do=Nothing");

        // Note: removed the 'clear' command that was causing the table to be emptied
        run("Analyze Particles...", "size=" + MINIMAL_SIZE + "-Infinity circularity=0.00-1.00 add");

        close(); // Close the processed image
        selectWindow(originalTitle); // Return to original image

        count = roiManager("count");
        area = 0; // Initialize area to 0

        if (count > 0) {
            if (count > 1) {
                roiManager("Select All");
                roiManager("Combine");
            } else {
                roiManager("Select", 0);
            }

            getStatistics(area); // Extract actual area

            roiManager("Set Color", "yellow");
            roiManager("Set Line Width", 5);
            run("Draw");
        }

        // 📊 Safely write data to our independently created table
        Table.set("Image_Name", rowIndex, originalTitle, tableName);
        Table.set("Total_Area", rowIndex, area, tableName);
        rowIndex++; // Increment row count, prepare for next image

        // Flatten and save image
        run("Flatten");
        newName = file;
        newName = replace(newName, ".tif", "");
        newName = replace(newName, ".TIF", "");
        newName = replace(newName, ".jpg", "");
        newName = replace(newName, ".JPG", "");
        saveAs("Jpeg", outputDir + newName + "_processed.jpg");

        close(); close();
        roiManager("reset");
    }
}

setBatchMode(false);
// After the loop, save the table as a CSV file at once
Table.save(outputDir + "Summary_Results.csv", tableName);
Table.update(tableName); // Display the final results on screen
print("🎉 Batch processing complete! All data has been safely accumulated, physical scratches excluded.");
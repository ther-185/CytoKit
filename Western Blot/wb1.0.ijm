requires("1.53");

while (true) {
    if (nImages == 0) exit("Please open an image with bands first!");

    sType = selectionType();
    if (sType != 5 && sType != 6 && sType != 7) {
        exit("Please first use the 'Straight/Segmented/Freehand Line' tool to draw across the bands to be analyzed!");
    }

    Dialog.create("Western Blot");
    Dialog.addChoice("Execution Mode:", newArray("Line Method", "Dual-Point Method"));
    Dialog.addNumber("Target Lane Count (manually input for Line Method only):", 4);
    Dialog.addNumber("Lane Height H (pixels):", 60);
    Dialog.addNumber("Rectangle height multiplier (1.5x recommended for Dual-Point Method):", 1.1);
    Dialog.addCheckbox("Auto-adaptive Width", false);
    Dialog.addCheckbox("Expand rectangle width by 5%", false);

    Dialog.show();
    pointMode = Dialog.getChoice();
    expectedLanes = Dialog.getNumber();
    laneHeight = Dialog.getNumber();
    heightMultiplier = Dialog.getNumber();
    useAdaptiveWidth = Dialog.getCheckbox();
    useExpansion = Dialog.getCheckbox();

    originalTitle = getTitle();
    originalDir = getDirectory("image");
    if (originalDir == "") originalDir = getDirectory("home");

    run("Line Width...", "line=" + laneHeight);
    run("Straighten...", "title=[" + originalTitle + "_Straightened] line=" + laneHeight);
    straightID = getImageID();
    imgW = getWidth();
    imgH = getHeight();
    run("Line Width...", "line=1");

    if (pointMode != "Line Method") {
        selectImage(straightID);
        setTool("multipoint");

        waitForUser("Dual-Point Delimitation Method", "Please click the [Left Edge] and [Right Edge] for each band in sequence.\nMechanism: Based on the actual biological size of each individual band (allows unequal band widths).\nClick [OK] when done.");

        if (selectionType() != 10) exit("Aborted: No point beacon array acquired.");
        getSelectionCoordinates(navX, navY);
        fastSortPointsByX(navX, navY);
        run("Select None");

        if (navX.length % 2 != 0) exit("Dual-Point Method requires an even number of points!");
        expectedLanes = navX.length / 2;
        pointCx = newArray(expectedLanes);
        pointCy = newArray(expectedLanes);
        pointW = newArray(expectedLanes);
        for(i=0; i < expectedLanes; i++) {
            p1x = navX[i*2];   p2x = navX[i*2 + 1];
            p1y = navY[i*2];   p2y = navY[i*2 + 1];
            pointCx[i] = (p1x + p2x) / 2.0;
            pointCy[i] = (p1y + p2y) / 2.0;
            pointW[i] = abs(p2x - p1x);
        }
    } else {
        if (expectedLanes < 1) exit("Lane count must be at least 1.");
    }

    run("Duplicate...", "title=Detect_Temp");
    if (bitDepth() != 8) run("8-bit");
    run("Invert");
    run("Subtract Background...", "rolling=40");
    run("Median...", "radius=2");
    run("Enhance Contrast...", "saturated=0.1 normalize");
    setAutoThreshold("Otsu dark");
    setOption("BlackBackground", true);
    run("Convert to Mask");
    run("Fill Holes");
    run("Watershed");
    roiManager("reset");

    // ==========================================
    if (pointMode == "Line Method") {

        run("Analyze Particles...", "size=5-Infinity pixel show=Nothing add");
        close();
        selectImage(straightID);
        count = roiManager("count");
        if (count == 0) exit("Extraction failed, noise processing anomaly.");

        xs = newArray(count); ys = newArray(count);
        ws = newArray(count); hs = newArray(count);
        for (i = 0; i < count; i++) {
            roiManager("select", i);
            Roi.getBounds(bx, by, bw, bh);
            xs[i] = bx; ys[i] = by; ws[i] = bw; hs[i] = bh;
        }
        fastSortByX(xs, ys, ws, hs);

        while (count > expectedLanes) {
            cx = newArray(count);
            for(i=0; i<count; i++) cx[i] = xs[i] + ws[i]/2.0;
            medW = getMedian(ws);
            areas = newArray(count);
            for(i=0; i<count; i++) areas[i] = ws[i]*hs[i];
            medA = getMedian(areas);

            if (medA <= 0) medA = 1.0;
            if (medW <= 0) medW = 1.0;

            validD = newArray(0);
            for(i=0; i<count-1; i++) {
                d = cx[i+1] - cx[i];
                if (d > medW * 0.5) validD = push(validD, d);
            }
            pitch = getMedian(validD);
            if(pitch <= 0 || isNaN(pitch)) pitch = medW * 1.5;

            bestCost = 999999999.0;
            bestAction = -1;
            bestIdx = -1;

            for(i=0; i<count; i++) {
                area = ws[i] * hs[i];
                cost = (area / medA) * 1000.0;
                if (i > 0) LG = cx[i] - cx[i-1]; else LG = 999999;
                if (i < count-1) RG = cx[i+1] - cx[i]; else RG = 999999;

                isAlignedL = abs(LG - pitch) < pitch * 0.35;
                isAlignedR = abs(RG - pitch) < pitch * 0.35;
                if (isAlignedL || isAlignedR) cost += 40000.0;

                if (i > 0 && i < count-1) {
                    newGap = cx[i+1] - cx[i-1];
                    if (abs(newGap - 2.0 * pitch) < pitch * 0.4) cost += 40000.0;
                }

                span = cx[count-1] - cx[0];
                reqSpan = (expectedLanes - 1) * pitch;
                if ((i == 0 || i == count-1) && span <= reqSpan + pitch * 0.5) {
                    if (isAlignedL || isAlignedR) cost += 40000.0;
                }
                if(cost < bestCost) { bestCost = cost; bestAction = 0; bestIdx = i; }
            }

            for(i=0; i<count-1; i++) {
                gap = xs[i+1] - (xs[i] + ws[i]);
                if(gap < 0) gap = 0;
                mW = (xs[i+1] + ws[i+1]) - xs[i];
                mH = maxOf(ys[i]+hs[i], ys[i+1]+hs[i+1]) - minOf(ys[i], ys[i+1]);
                mA = mW * mH;
                cost = (abs(mW - medW) / medW + abs(mA - medA) / medA + (gap / medW) * 3.0) * 250.0;
                if (cost < bestCost) { bestCost = cost; bestAction = 1; bestIdx = i; }
            }

            if (bestAction == 0) {
                xs = removeExt(xs, bestIdx); ys = removeExt(ys, bestIdx);
                ws = removeExt(ws, bestIdx); hs = removeExt(hs, bestIdx);
                count--;
            } else if (bestAction == 1) {
                idx = bestIdx;
                mergedW = (xs[idx+1] + ws[idx+1]) - xs[idx];
                mergedH = maxOf(ys[idx]+hs[idx], ys[idx+1]+hs[idx+1]) - minOf(ys[idx], ys[idx+1]);
                mergedY = minOf(ys[idx], ys[idx+1]);
                xs[idx] = xs[idx]; ys[idx] = mergedY;
                ws[idx] = mergedW; hs[idx] = mergedH;
                xs = removeExt(xs, idx+1); ys = removeExt(ys, idx+1);
                ws = removeExt(ws, idx+1); hs = removeExt(hs, idx+1);
                count--;
            }
        }

        while (count < expectedLanes) {
            cx = newArray(count);
            for(i=0; i<count; i++) cx[i] = xs[i] + ws[i]/2.0;
            medW = getMedian(ws);

            validD = newArray(0);
            for(i=0; i<count-1; i++) {
                d = cx[i+1] - cx[i];
                if (d > medW * 0.5) validD = push(validD, d);
            }
            pitch = getMedian(validD);
            if(pitch <= 0 || isNaN(pitch)) pitch = medW * 1.5;

            bestScore = -1.0;
            bestAction = -1;
            bestIdx = -1;

            for(i=0; i<count; i++) {
                ratio = ws[i] / medW;
                if (ratio > 1.3) {
                    score = ratio * 150.0;
                    if(score > bestScore) { bestScore = score; bestAction = 0; bestIdx = i; }
                }
            }
            for(i=0; i<count-1; i++) {
                gap = cx[i+1] - cx[i];
                ratio = gap / pitch;
                if (ratio > 1.5) {
                    score = ratio * 120.0;
                    if(score > bestScore) { bestScore = score; bestAction = 1; bestIdx = i; }
                }
            }

            expectedSpan = (expectedLanes - 1) * pitch;
            currentSpan = cx[count-1] - cx[0];
            deficitSpan = expectedSpan - currentSpan;
            distLeft = cx[0];
            distRight = imgW - cx[count-1];

            if (deficitSpan > pitch * 0.5) {
                score = (deficitSpan / pitch) * 110.0;
                if (score > bestScore) {
                    bestScore = score;
                    if (distRight > distLeft) bestAction = 3; else bestAction = 2;
                }
            }
            if (bestAction == -1) {
                if (distRight > distLeft) bestAction = 3; else bestAction = 2;
            }

            if (bestAction == 0) {
                i = bestIdx;
                oldX = xs[i]; oldW = ws[i]; oldY = ys[i]; oldH = hs[i];
                w1 = oldW / 2.0; w2 = oldW / 2.0;
                xs[i] = oldX; ws[i] = w1;
                xs = insertExt(xs, i+1, oldX + w1); ys = insertExt(ys, i+1, oldY);
                ws = insertExt(ws, i+1, w2); hs = insertExt(hs, i+1, oldH);
                count++;
            } else if (bestAction == 1) {
                i = bestIdx;
                newX = xs[i] + ws[i] + (xs[i+1] - (xs[i] + ws[i])) / 2.0 - medW/2.0;
                xs = insertExt(xs, i+1, newX); ys = insertExt(ys, i+1, ys[i]);
                ws = insertExt(ws, i+1, medW); hs = insertExt(hs, i+1, hs[i]);
                count++;
            } else if (bestAction == 2) {
                newX = cx[0] - pitch - medW/2.0;
                if (newX < 0) newX = 0;
                xs = insertExt(xs, 0, newX); ys = insertExt(ys, 0, ys[0]);
                ws = insertExt(ws, 0, medW); hs = insertExt(hs, 0, hs[0]);
                count++;
            } else if (bestAction == 3) {
                newX = cx[count-1] + pitch - medW/2.0;
                if (newX + medW > imgW) newX = imgW - medW;
                xs = insertExt(xs, count, newX); ys = insertExt(ys, count, ys[count-1]);
                ws = insertExt(ws, count, medW); hs = insertExt(hs, count, hs[count-1]);
                count++;
            }
            fastSortByX(xs, ys, ws, hs);
        }

        finalXs = xs; finalYs = ys; finalWs = ws; finalHs = hs;
        finalCount = count;
        finalCenterX = newArray(finalCount);
        finalCenterY = newArray(finalCount);
        for (i = 0; i < finalCount; i++) {
            finalCenterX[i] = finalXs[i] + finalWs[i]/2.0;
            finalCenterY[i] = finalYs[i] + finalHs[i]/2.0;
        }

        medFinalW = getMedian(finalWs);
        medFinalY = getMedian(finalCenterY);
        maxH = 0;
        targetW = 0;
        for (i = 0; i < finalCount; i++) {
            if (finalHs[i] > maxH) maxH = finalHs[i];
            if (finalWs[i] > targetW) targetW = finalWs[i];
        }
        targetH = maxH * heightMultiplier;

        roiManager("reset");
        S = imgW / expectedLanes;

        for (k = 0; k < expectedLanes; k++) {
            t_start = k * S;
            t_end = (k+1) * S;
            seg_cx = t_start + S / 2.0;

            bestIdx = -1;
            maxW = -1.0;
            for (i=0; i < finalCount; i++) {
                if (finalCenterX[i] >= t_start && finalCenterX[i] < t_end) {
                    if (finalWs[i] > maxW) {
                        maxW = finalWs[i];
                        bestIdx = i;
                    }
                }
            }

            isShallow = false;
            if (bestIdx == -1) {
                isShallow = true;
            } else {
                if (finalWs[bestIdx] < medFinalW * 0.6) {
                    isShallow = true;
                }
            }

            if (useAdaptiveWidth) {
                if (isShallow) currentW = medFinalW;
                else currentW = finalWs[bestIdx];
            } else {
                currentW = targetW;
            }

            if (useExpansion) currentW = currentW * 1.05;

            if (isShallow) {
                makeRectangle(seg_cx - currentW/2.0, medFinalY - targetH/2.0, currentW, targetH);
                roiManager("Add");
                roiManager("select", k);
                roiManager("Rename", "Lane_" + (k+1) + " (Sector Gen)");
            } else {
                makeRectangle(finalCenterX[bestIdx] - currentW/2.0, finalCenterY[bestIdx] - targetH/2.0, currentW, targetH);
                roiManager("Add");
                roiManager("select", k);
                roiManager("Rename", "Lane_" + (k+1));
            }
        }

    } else {

        pitchD = newArray(0);
        for(i=0; i<expectedLanes-1; i++) pitchD = push(pitchD, pointCx[i+1] - pointCx[i]);
        pitch = getMedian(pitchD);
        if (pitch <= 0 || isNaN(pitch)) pitch = imgW / expectedLanes;

        validHs = newArray(0);
        for (k = 0; k < expectedLanes; k++) {
            doWand(pointCx[k], pointCy[k]);
            if (selectionType() != -1) {
                Roi.getBounds(bx, by, bw, bh);
                if (bh < imgH) validHs = push(validHs, bh);
            }
        }

        run("Select None");
        close();
        selectImage(straightID);

        maxH = 0;
        for(i=0; i<validHs.length; i++) { if(validHs[i] > maxH) maxH = validHs[i]; }
        if (maxH <= 0 || isNaN(maxH)) maxH = imgH * 0.8;
        targetH = maxH * heightMultiplier;
        if (targetH > imgH) targetH = imgH;

        if (!useAdaptiveWidth) {
            targetW = 0;
            for(i=0; i<expectedLanes; i++) { if(pointW[i] > targetW) targetW = pointW[i]; }
            if (targetW <= 0 || isNaN(targetW)) targetW = imgW / expectedLanes * 0.5;

            if (expectedLanes > 1) {
                minGlobalGap = 999999;
                for(k=0; k<expectedLanes-1; k++) {
                    gap = pointCx[k+1] - pointCx[k];
                    if (gap > 0 && gap < minGlobalGap) minGlobalGap = gap;
                }
                if (targetW > minGlobalGap * 0.95) {
                    targetW = minGlobalGap * 0.95;
                }
            }
        }

        roiManager("reset");

        for (k = 0; k < expectedLanes; k++) {
            seg_cx = pointCx[k];
            seg_cy = pointCy[k];

            if (useAdaptiveWidth) {
                currentW = pointW[k];
                if (useExpansion) currentW = currentW * 1.05;

                if (expectedLanes > 1) {
                    gapLeft = 999999; gapRight = 999999;
                    if (k > 0) gapLeft = pointCx[k] - pointCx[k-1];
                    if (k < expectedLanes - 1) gapRight = pointCx[k+1] - pointCx[k];
                    minLocalGap = minOf(gapLeft, gapRight);
                    if (currentW > minLocalGap * 0.95) {
                        currentW = minLocalGap * 0.95;
                    }
                }
            } else {
                currentW = targetW;
                if (useExpansion) currentW = currentW * 1.05;
            }

            makeRectangle(seg_cx - currentW/2.0, seg_cy - targetH/2.0, currentW, targetH);
            roiManager("Add");
            roiManager("select", k);
            roiManager("Rename", "Lane_" + (k+1));
        }
    }

    roiManager("Show All with labels");
    waitForUser("Calibration", "\nAll individual lane tracking capture boxes have been generated!\n[Correction Tips]:\nIf any box appears slightly larger or smaller than expected, please directly drag and stretch the edges of that yellow box on the image, then click the corresponding Lane number in the ROI Manager list and click [Update] to save!\nOnce confirmed correct, click [OK] to begin quantitative measurement.");

    finalCount2 = roiManager("count");
    if (finalCount2 == 0) exit("Extraction aborted!");

    finalXs2 = newArray(finalCount2); finalYs2 = newArray(finalCount2);
    finalWs2 = newArray(finalCount2); finalHs2 = newArray(finalCount2);
    for (i = 0; i < finalCount2; i++) {
        roiManager("select", i);
        Roi.getBounds(bx, by, bw, bh);
        finalXs2[i] = bx; finalYs2[i] = by; finalWs2[i] = bw; finalHs2[i] = bh;
    }

    fastSortByX(finalXs2, finalYs2, finalWs2, finalHs2);

    roiManager("reset");
    for (i = 0; i < finalCount2; i++) {
        makeRectangle(finalXs2[i], finalYs2[i], finalWs2[i], finalHs2[i]);
        roiManager("Add");
        roiManager("select", i);
        roiManager("Rename", "Lane_" + (i+1));
    }

    run("Select None");
    run("Set Measurements...", "area mean integrated redirect=None decimal=3");
    run("Clear Results");

    selectImage(straightID);
    run("Duplicate...", "title=Measure_Temp");

    if (bitDepth() == 24) { run("8-bit"); }
    run("Invert");
    run("Subtract Background...", "rolling=" + (targetH * 1.5));

    roiManager("Show All with labels");
    roiManager("Measure");
    close();
    selectImage(straightID);
    run("Select None");

    suffix = "";
    if (pointMode == "Line Method") suffix = "_LineMode";
    else suffix = "_DualPointMode";

    if (useExpansion) suffix = suffix + "_105%";
    else suffix = suffix + "_100%";

    baseName = originalTitle + suffix;
    counter = 0;
    csvPath = ""; imgPath = ""; tifPath = "";
    do {
        ext = "";
        if (counter > 0) ext = "_" + counter;
        csvPath = originalDir + baseName + ext + ".csv";
        imgPath = originalDir + baseName + ext + ".png";
        tifPath = originalDir + baseName + ext + ".tif";
        counter++;
    } while (File.exists(csvPath) || File.exists(imgPath));

    saveAs("Results", csvPath);

    selectImage(straightID);
    resetMinAndMax();
    setVoxelSize(1/600, 1/600, 1, "inch");
    saveAs("Tiff", tifPath);

    roiManager("Show All with labels");
    run("Flatten");
    saveAs("PNG", imgPath);
    close();
    close(straightID);

    print("[" + originalTitle + "] " + pointMode + " quantitative analysis complete!");

    if (!getBoolean("Single analysis workflow complete!\n\nLoad the next band?")) {
        break;
    }

    nextImgPath = File.openDialog("Please select the band to process");
    run("Close All");
    if (isOpen("ROI Manager")) {
        selectWindow("ROI Manager");
        run("Close");
    }
    if (isOpen("Results")) {
        selectWindow("Results");
        run("Close");
    }
    open(nextImgPath);
    setTool("line");
    waitForUser("Measure Along Markers", "Please draw a straight line to confirm the analysis cross-section range.");
}


function fastSortByX(ax, ay, aw, ah) {
    if (ax.length == 0) return;
    ranks = Array.rankPositions(ax);
    tx = newArray(ax.length); ty = newArray(ax.length);
    tw = newArray(ax.length); th = newArray(ax.length);
    for (i = 0; i < ax.length; i++) {
        idx = ranks[i];
        tx[i] = ax[idx]; ty[i] = ay[idx];
        tw[i] = aw[idx]; th[i] = ah[idx];
    }
    for (i = 0; i < ax.length; i++) {
        ax[i] = tx[i]; ay[i] = ty[i];
        aw[i] = tw[i]; ah[i] = th[i];
    }
}

function fastSortPointsByX(ax, ay) {
    if (ax.length == 0) return;
    ranks = Array.rankPositions(ax);
    tx = newArray(ax.length); ty = newArray(ax.length);
    for (i = 0; i < ax.length; i++) {
        idx = ranks[i];
        tx[i] = ax[idx]; ty[i] = ay[idx];
    }
    for (i = 0; i < ax.length; i++) {
        ax[i] = tx[i]; ay[i] = ty[i];
    }
}

function push(arr, val) {
    n = lengthOf(arr);
    out = newArray(n+1);
    for(i=0; i<n; i++) out[i] = arr[i];
    out[n] = val;
    return out;
}

function removeExt(arr, idx) {
    n = lengthOf(arr);
    out = newArray(n-1);
    k = 0;
    for (i = 0; i < n; i++) {
        if (i != idx) {
            out[k] = arr[i];
            k++;
        }
    }
    return out;
}

function insertExt(arr, idx, val) {
    n = lengthOf(arr);
    out = newArray(n+1);
    for(i=0; i<idx; i++) out[i] = arr[i];
    out[idx] = val;
    for(i=idx; i<n; i++) out[i+1] = arr[i];
    return out;
}

function getMedian(arr) {
    if (arr.length == 0) return 0;
    tmp = newArray(arr.length);
    for(i=0; i<arr.length; i++) tmp[i]=arr[i];
    Array.sort(tmp);
    len = tmp.length;
    if (len % 2 == 1) {
        return tmp[floor(len/2)];
    } else {
        return (tmp[len/2 - 1] + tmp[len/2]) / 2.0;
    }
}

@echo off
REM Post-Reboot GPU Diagnostic & Fix Script
REM Run as Administrator!
REM ===========================================

echo ============================================
echo  GPU Force Boost - Post-Reboot Diagnostic
echo ============================================
echo.

REM 1. Check driver communication
echo [1] Checking nvidia-smi communication...
nvidia-smi --query-gpu=name,driver_version,driver_model.current --format=csv,noheader
if errorlevel 1 (
    echo FAIL: nvidia-smi cannot communicate with GPU.
    echo NOTE: A2000 should be in WDDM mode (monitor is connected to it).
    echo Check Device Manager for driver status.
    pause
    exit /b 1
)
echo.

REM 2. Check PCIe link speed (THE KEY DIAGNOSTIC)
echo [2] Checking PCIe link speed...
nvidia-smi --query-gpu=pcie.link.gen.current,pcie.link.gen.max,pcie.link.width.current,pcie.link.width.max --format=csv
echo.

REM 3. Check current state at idle
echo [3] Idle GPU state:
nvidia-smi --query-gpu=pstate,clocks.gr,clocks.mem,power.draw,utilization.gpu --format=csv
echo.

REM 4. Apply clock locks
echo [4] Applying clock locks...
nvidia-smi -rgc
nvidia-smi -rmc
nvidia-smi -lgc 210,2100
nvidia-smi -lmc 6001
echo.

REM 5. Start load test in background
echo [5] Starting GPU load test (30 second matmul)...
start /b python C:\Users\akbon\Downloads\files\gpu-load-test.py
timeout /t 8 /nobreak >nul

REM 6. Check state under load
echo [6] GPU state UNDER LOAD:
nvidia-smi --query-gpu=pstate,clocks.gr,clocks.mem,pcie.link.gen.current,pcie.link.width.current,power.draw,utilization.gpu --format=csv
echo.

REM 7. Full nvidia-smi snapshot
echo [7] Full nvidia-smi output:
nvidia-smi
echo.

REM 8. Check PCIe under load specifically
echo [8] PCIe link speed under load:
nvidia-smi --query-gpu=pcie.link.gen.current,pcie.link.gen.gpumax --format=csv,noheader
echo.

echo ============================================
echo  RESULTS ANALYSIS:
echo ============================================
echo  If PCIe shows Gen1 under load: BIOS issue!
echo    Fix: Enter BIOS ^> Advanced ^> PCI Subsystem
echo    Set "PCIe Slot Speed" to Gen3 (not Auto)
echo.
echo  If PCIe shows Gen3 but still P8:
echo    Driver power management issue.
echo.
echo  If clocks are above 1000 MHz: SUCCESS!
echo ============================================

pause

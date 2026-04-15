<#
.SYNOPSIS
    GPU Force Boost - tunes NVIDIA RTX A2000 for high sustained performance under LLM load.
    
.DESCRIPTION
    Monitors and controls NVIDIA GPU performance states. Can lock clocks, enable persistence mode,
    and auto-detect LM Studio to prepare the GPU for sustained boost during active workload.

.NOTES
    Requires Administrator rights. Will auto-relaunch as admin if not elevated.
    RTX A2000 Desktop: Base 562 MHz / Boost 1200 MHz / Memory 6144 MHz (GDDR6)
    RTX A2000 Laptop:  Base 562 MHz / Boost 1552 MHz / Memory 6001 MHz (GDDR6)
#>

param(
    [ValidateSet("boost", "reset", "monitor", "auto", "status", "fix")]
    [string]$Mode = "status",

    # Registry profile (for -Mode fix only):
    # - tcc:    EnableDriverControlledPMM=0, remove PowerMizer keys (DEFAULT -- correct for TCC mode)
    # - legacy: EnableDriverControlledPMM=1 + PowerMizer keys (WDDM only, breaks TCC boost)
    [ValidateSet("tcc", "legacy")]
    [string]$RegProfile = "tcc",
    
    [string]$WatchProcess = "LM Studio",
    
    [int]$PollIntervalSeconds = 5,
    
    # Override max GPU clock if auto-detect is wrong (MHz)
    [int]$MaxGpuClock = 0,
    
    # Override max memory clock (MHz)  
    [int]$MaxMemClock = 0,

    # GPU index (if you have multiple NVIDIA GPUs)
    [int]$GpuIndex = -1
)

# -- Auto-elevate if not running as Administrator --
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    Write-Host "  Not running as Administrator - relaunching elevated..." -ForegroundColor Yellow
    $argList = @('-NoExit', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Mode', $Mode, '-WatchProcess', "`"$WatchProcess`"", '-PollIntervalSeconds', $PollIntervalSeconds, '-GpuIndex', $GpuIndex)
    if ($MaxGpuClock -gt 0) { $argList += @('-MaxGpuClock', $MaxGpuClock) }
    if ($MaxMemClock  -gt 0) { $argList += @('-MaxMemClock',  $MaxMemClock)  }
    Start-Process powershell -Verb RunAs -ArgumentList $argList
    exit
}

# -- Helpers --

$ESC = [char]27

function Write-Color($Text, $Color) {
    $colors = @{
        Red     = "31"; Green  = "32"; Yellow = "33"
        Blue    = "34"; Cyan   = "36"; White  = "37"
        BrightGreen  = "92"; BrightYellow = "93"
        BrightCyan   = "96"; BrightRed    = "91"
        Gray    = "90"
    }
    $c = $colors[$Color]
    if ($c) { Write-Host "$ESC[${c}m${Text}$ESC[0m" -NoNewline } 
    else    { Write-Host $Text -NoNewline }
}

function Write-ColorLine($Text, $Color) {
    Write-Color $Text $Color
    Write-Host ""
}

function Write-Banner {
    Write-Host ""
    Write-ColorLine "  +----------------------------------------------+" "Cyan"
    Write-ColorLine "  |       GPU FORCE BOOST - RTX A2000           |" "Cyan"
    Write-ColorLine "  |       Performance State Controller          |" "Cyan"
    Write-ColorLine "  +----------------------------------------------+" "Cyan"
    Write-Host ""
}

function Get-NvidiaSmiPath {
    $smiPath = Get-Command nvidia-smi -ErrorAction SilentlyContinue
    if ($smiPath) { return $smiPath.Source }
    
    $defaultPath = "C:\Windows\System32\nvidia-smi.exe"
    if (Test-Path $defaultPath) { return $defaultPath }
    
    $progPath = "C:\Program Files\NVIDIA Corporation\NVSMI\nvidia-smi.exe"
    if (Test-Path $progPath) { return $progPath }
    
    Write-ColorLine "  ERROR: nvidia-smi not found. Install NVIDIA drivers." "Red"
    exit 1
}

$NVIDIA_SMI = Get-NvidiaSmiPath

function Find-A2000GpuIndex {
    if ($GpuIndex -ge 0) { return $GpuIndex }
    
    $output = & $NVIDIA_SMI --query-gpu=index,name --format=csv,noheader 2>&1
    $lines = $output -split "`n" | Where-Object { $_.Trim() -ne "" }
    
    foreach ($line in $lines) {
        $parts = $line -split ","
        $idx  = $parts[0].Trim()
        $name = $parts[1].Trim()
        if ($name -match "A2000") {
            Write-Color "  Found: " "Gray"
            Write-ColorLine "$name at index $idx" "Green"
            return [int]$idx
        }
    }
    
    # Fallback: if only one GPU, use it
    if ($lines.Count -eq 1) {
        $idx = ($lines[0] -split ",")[0].Trim()
        $name = ($lines[0] -split ",")[1].Trim()
        Write-Color "  Using only GPU: " "Gray"
        Write-ColorLine "$name at index $idx" "Yellow"
        return [int]$idx
    }
    
    Write-ColorLine "  ERROR: Could not find RTX A2000. Use -GpuIndex parameter." "Red"
    exit 1
}

function Get-GpuClockLimits {
    param([int]$Idx)
    
    $output = & $NVIDIA_SMI -i $Idx --query-supported-clocks=gr,mem --format=csv,noheader 2>&1
    $maxGpu = 0
    $maxMem = 0
    
    foreach ($line in ($output -split "`n")) {
        if ($line -match "(\d+)\s*MHz\s*,\s*(\d+)\s*MHz") {
            $gpu = [int]$Matches[1]
            $mem = [int]$Matches[2]
            if ($gpu -gt $maxGpu) { $maxGpu = $gpu }
            if ($mem -gt $maxMem) { $maxMem = $mem }
        }
    }
    
    # Fallback to query if supported-clocks didn't work
    if ($maxGpu -eq 0) {
        $info = & $NVIDIA_SMI -i $Idx --query-gpu=clocks.max.gr,clocks.max.mem --format=csv,noheader,nounits 2>&1
        if ($info -match "(\d+)\s*,\s*(\d+)") {
            $maxGpu = [int]$Matches[1]
            $maxMem = [int]$Matches[2]
        }
    }
    
    # Allow user overrides
    if ($MaxGpuClock -gt 0) { $maxGpu = $MaxGpuClock }
    if ($MaxMemClock -gt 0) { $maxMem = $MaxMemClock }
    
    return @{ Gpu = $maxGpu; Mem = $maxMem }
}

function Get-GpuStatus {
    param([int]$Idx)

    $query = "pstate,clocks.gr,clocks.mem,clocks.max.gr,clocks.max.mem," +
             "utilization.gpu,utilization.memory,temperature.gpu," +
             "power.draw,power.limit,memory.used,memory.total," +
             "persistence_mode,name,driver_model.current,clocks_throttle_reasons.active"

    $raw = & $NVIDIA_SMI -i $Idx --query-gpu=$query --format=csv,noheader,nounits 2>&1
    $parts = ($raw -split ",") | ForEach-Object { $_.Trim() }

    return @{
        PState          = $parts[0]
        GpuClockMHz     = $parts[1]
        MemClockMHz     = $parts[2]
        MaxGpuClock     = $parts[3]
        MaxMemClock     = $parts[4]
        GpuUtil         = $parts[5]
        MemUtil         = $parts[6]
        TempC           = $parts[7]
        PowerDraw       = $parts[8]
        PowerLimit      = $parts[9]
        MemUsedMB       = $parts[10]
        MemTotalMB      = $parts[11]
        Persistence     = $parts[12]
        Name            = $parts[13]
        DriverModel     = $parts[14]
        ThrottleReasons = $parts[15]
    }
}

function Invoke-NvidiaSmi {
    param(
        [string[]]$Arguments
    )
    $output = & $NVIDIA_SMI @Arguments 2>&1
    $text = ($output | Out-String).Trim()
    return @{ Ok = ($LASTEXITCODE -eq 0); Text = $text }
}

function Confirm-LockState {
    param([int]$Idx)
    $s = Get-GpuStatus $Idx
    $gpuOk = [int]$s.GpuClockMHz -ge 900
    $memOk = [int]$s.MemClockMHz -ge 5000
    return @{ GpuOk = $gpuOk; MemOk = $memOk; Status = $s }
}

function Format-PState {
    param([string]$PState)
    switch ($PState) {
        "P0" { Write-Color "P0 (MAX BOOST)" "BrightGreen" }
        "P1" { Write-Color "P1 (High)"      "Green" }
        "P2" { Write-Color "P2 (SUSTAINED COMPUTE)" "Green" }
        "P3" { Write-Color "P3 (Medium-Low)" "Yellow" }
        "P5" { Write-Color "P5 (Low)"        "BrightYellow" }
        "P8" { Write-Color "P8 (IDLE)"       "BrightRed" }
        default { Write-Color "$PState"      "Gray" }
    }
}

function Show-Status {
    param([int]$Idx)
    
    $s = Get-GpuStatus $Idx

    $isComputePstate = $s.PState -in @("P0", "P1", "P2")
    $isHighMemClock = [int]$s.MemClockMHz -ge 5000
    $isHighGpuClock = [int]$s.GpuClockMHz -ge 900
    $isLoaded = [int]$s.GpuUtil -ge 20
    $boostHealthy = $isComputePstate -and $isHighMemClock -and $isHighGpuClock
    
    Write-Host ""
    Write-Color "  GPU:          " "Gray"; Write-ColorLine $s.Name "White"
    Write-Color "  P-State:      " "Gray"; Format-PState $s.PState; Write-Host ""
    Write-Color "  GPU Clock:    " "Gray"; Write-ColorLine "$($s.GpuClockMHz) / $($s.MaxGpuClock) MHz" "White"
    Write-Color "  Mem Clock:    " "Gray"; Write-ColorLine "$($s.MemClockMHz) / $($s.MaxMemClock) MHz" "White"
    Write-Color "  GPU Util:     " "Gray"; Write-ColorLine "$($s.GpuUtil)%" "White"
    Write-Color "  Mem Util:     " "Gray"; Write-ColorLine "$($s.MemUtil)%" "White"
    Write-Color "  VRAM:         " "Gray"; Write-ColorLine "$($s.MemUsedMB) / $($s.MemTotalMB) MB" "White"
    Write-Color "  Temperature:  " "Gray"; Write-ColorLine "$($s.TempC) C" "White"
    Write-Color "  Power:        " "Gray"; Write-ColorLine "$($s.PowerDraw) / $($s.PowerLimit) W" "White"
    Write-Color "  Persistence:  " "Gray"
    if ($s.Persistence -match "Enabled") {
        Write-ColorLine "Enabled" "Green"
    } else {
        Write-ColorLine "Disabled" "Red"
    }
    Write-Color "  Driver Model: " "Gray"
    if ($s.DriverModel -eq "TCC") {
        Write-ColorLine "TCC  (clock locks honored)" "BrightGreen"
    } elseif ($s.DriverModel) {
        Write-ColorLine "$($s.DriverModel)  (!!! clock locks ignored in WDDM -- run: -Mode fix)" "BrightRed"
    } else {
        Write-ColorLine "unknown" "Gray"
    }
    Write-Color "  Throttle:     " "Gray"
    $throttleHex = $s.ThrottleReasons
    if ($throttleHex -and $throttleHex -ne "0x0000000000000000" -and $throttleHex -ne "N/A") {
        # Decode the common throttle reason bits
        $reasons = @()
        $bits = [Convert]::ToInt64($throttleHex, 16)
        if ($bits -band 0x0000000000000002) { $reasons += "HW_Slowdown" }
        if ($bits -band 0x0000000000000008) { $reasons += "SW_PowerCap" }
        if ($bits -band 0x0000000000000010) { $reasons += "HW_PowerBrake" }
        if ($bits -band 0x0000000000000020) { $reasons += "Sync_Boost" }
        if ($bits -band 0x0000000000000040) { $reasons += "SW_ThermalSlowdown" }
        if ($bits -band 0x0000000000000080) { $reasons += "HW_ThermalSlowdown" }
        if ($bits -band 0x0000000000000100) { $reasons += "DisplayClocks" }
        $label = if ($reasons) { $reasons -join ", " } else { "other ($throttleHex)" }
        Write-ColorLine "$label" "BrightRed"
    } else {
        Write-ColorLine "None  ($throttleHex)" "Green"
    }

    Write-Color "  Boost Health: " "Gray"
    if ($boostHealthy) {
        Write-ColorLine "GOOD (compute clocks active)" "BrightGreen"
    } elseif ($isLoaded) {
        Write-ColorLine "LIMITED (load present, but clocks below target)" "Yellow"
    } else {
        Write-ColorLine "IDLE (run workload to validate boost)" "Gray"
    }
    Write-Host ""
    
    return $s
}

# -- Core Actions ---------------------------------------------------------------

function Ensure-TccMode {
    param([int]$Idx)
    # TCC mode is required for nvidia-smi clock locks (-lgc/-lmc) to be honored on Windows.
    # WDDM mode accepts the commands but silently ignores them, leaving clocks at P8/minimum.
    # A new driver install resets the GPU back to WDDM -- this function detects and corrects that.

    $model = (& $NVIDIA_SMI -i $Idx --query-gpu=driver_model.current --format=csv,noheader,nounits 2>&1).Trim()

    Write-Color "  [TCC]  Current driver model: " "Gray"
    if ($model -eq "TCC") {
        Write-ColorLine "TCC  (clock locks will be honored)" "BrightGreen"
        return $true
    }

    Write-ColorLine "$model  -- clock locks WILL NOT work in WDDM" "BrightRed"
    Write-Color "  [TCC]  Switching to TCC mode... " "Gray"
    $res = Invoke-NvidiaSmi -Arguments @('-i', "$Idx", '-dm', '1')
    if ($res.Ok) {
        Write-ColorLine "DONE" "BrightGreen"
        Write-ColorLine "  [TCC]  REBOOT REQUIRED for TCC mode to activate." "BrightYellow"
        Write-ColorLine "         After reboot, re-run: .\gpu-force-boost.ps1 -Mode fix" "Yellow"
    } else {
        Write-ColorLine "FAILED" "BrightRed"
        Write-ColorLine "  [TCC]  Output: $($res.Text)" "Gray"
        Write-ColorLine "  [TCC]  TCC mode may not be available on this GPU/driver combination." "Yellow"
        Write-ColorLine "         Try running nvidia-smi -i $Idx -dm 1 manually as Administrator." "Yellow"
    }
    return $false   # Caller should not proceed with clock lock -- reboot required
}

function Ensure-RegistryKeys {
    # Re-applies performance registry keys that Windows Update wipes on each NVIDIA driver install.
    # These keys make EnableDriverControlledPMM=1 so the driver respects nvidia-smi lock commands.
    # Finds the A2000 registry path dynamically in case the device index has shifted.

    $classBase = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
    $regBase = $null
    Get-ChildItem $classBase -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^\d{4}$' } | ForEach-Object {
        $desc = (Get-ItemProperty $_.PSPath -Name 'DriverDesc' -ErrorAction SilentlyContinue).DriverDesc
        if ($desc -match 'A2000') { $regBase = $_.PSPath }
    }

    if (-not $regBase) {
        Write-ColorLine "  WARNING: Could not find A2000 registry path -- skipping reg keys" "Yellow"
        return $false
    }

    if ($RegProfile -eq "tcc") {
        # TCC mode: EnableDriverControlledPMM=0 lets the TCC subsystem manage P-states natively.
        # Setting it to 1 enables the driver's conservative PMM which applies SW_POWER_CAP
        # prematurely (at ~20W instead of 70W), preventing clock boost during inference.
        $current = (Get-ItemProperty $regBase -Name 'EnableDriverControlledPMM' -ErrorAction SilentlyContinue).EnableDriverControlledPMM
        $legacyPerf = (Get-ItemProperty $regBase -Name 'PerfLevelSrc' -ErrorAction SilentlyContinue).PerfLevelSrc

        if (($current -eq 0) -and ($null -eq $legacyPerf)) {
            Write-Color   "  [Reg]  TCC profile: " "Gray"
            Write-ColorLine "ALREADY SET" "Green"
            return $false   # no changes made
        }

        Write-Color "  [Reg]  Applying TCC registry profile... " "Gray"
        Set-ItemProperty -Path $regBase -Name "EnableDriverControlledPMM" -Value 0 -Type DWord
        @('PerfLevelSrc','PowerMizerEnable','PowerMizerLevel','PowerMizerDefault','PowerMizerDefaultAC') | ForEach-Object {
            Remove-ItemProperty -Path $regBase -Name $_ -ErrorAction SilentlyContinue
        }
        Write-ColorLine "DONE" "BrightGreen"
    }
    else {
        $current = (Get-ItemProperty $regBase -Name 'EnableDriverControlledPMM' -ErrorAction SilentlyContinue).EnableDriverControlledPMM
        $allPresent = ($null -ne $current) -and
                      ($null -ne (Get-ItemProperty $regBase -Name 'PerfLevelSrc' -ErrorAction SilentlyContinue).PerfLevelSrc)

        if ($allPresent -and $current -eq 1) {
            Write-Color   "  [Reg]  Legacy profile: " "Gray"
            Write-ColorLine "ALREADY SET" "Green"
            return $false   # no changes made
        }

        Write-Color "  [Reg]  Applying legacy registry profile... " "Gray"
        Set-ItemProperty -Path $regBase -Name "EnableDriverControlledPMM" -Value 1      -Type DWord
        Set-ItemProperty -Path $regBase -Name "PerfLevelSrc"              -Value 0x2222 -Type DWord
        Set-ItemProperty -Path $regBase -Name "PowerMizerEnable"          -Value 1      -Type DWord
        Set-ItemProperty -Path $regBase -Name "PowerMizerLevel"           -Value 1      -Type DWord
        Set-ItemProperty -Path $regBase -Name "PowerMizerDefault"         -Value 1      -Type DWord
        Set-ItemProperty -Path $regBase -Name "PowerMizerDefaultAC"       -Value 1      -Type DWord
        Write-ColorLine "DONE" "BrightGreen"
    }
    Write-ColorLine "  [Reg]  NOTE: A GPU driver restart is needed for these to take effect." "Yellow"
    Write-ColorLine "         Run with -Mode fix to apply reg + bounce driver + lock clocks." "Yellow"
    return $true   # changes were made, driver restart needed
}

function Invoke-GpuDriverRestart {
    # Soft driver restart via PnP disable/enable. Faster than a full reboot.
    # After this, nvidia-smi clock locks applied in the same session will be honoured.
    $dev = Get-PnpDevice | Where-Object { $_.FriendlyName -match 'A2000' } | Select-Object -First 1
    if (-not $dev) {
        Write-ColorLine "  WARNING: A2000 PnP device not found -- skipping driver restart" "Yellow"
        return $false
    }
    Write-Color "  [Drv]  Disabling A2000 device... " "Gray"
    Disable-PnpDevice -InstanceId $dev.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 4
    Write-ColorLine "done" "Gray"
    Write-Color "  [Drv]  Re-enabling A2000 device... " "Gray"
    Enable-PnpDevice  -InstanceId $dev.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 5
    Write-ColorLine "done" "Gray"
    # Quick sanity check
    $test = nvidia-smi -i 0 --query-gpu=pstate --format=csv,noheader 2>&1
    if ($test -match 'P\d') {
        Write-ColorLine "  [Drv]  Driver responded OK (P-state: $($test.Trim()))" "Green"
        return $true
    } else {
        Write-ColorLine "  [Drv]  WARNING: nvidia-smi did not respond after PnP restart." "Yellow"
        Write-ColorLine "         A full system reboot may be required." "Yellow"
        return $false
    }
}

function Enable-MaxPerformance {
    param([int]$Idx)

    Write-ColorLine "  >> Forcing maximum performance state..." "Cyan"
    Write-Host ""

    # Pre-check: warn if WDDM (clock locks will silently fail)
    $currentModel = (& $NVIDIA_SMI -i $Idx --query-gpu=driver_model.current --format=csv,noheader,nounits 2>&1).Trim()
    if ($currentModel -and $currentModel -ne "TCC") {
        Write-ColorLine "  [WARN] Driver model is $currentModel -- clock locks will be IGNORED." "BrightRed"
        Write-ColorLine "         Run -Mode fix first to switch to TCC and unlock clock control." "Yellow"
        Write-Host ""
    }

    $limits = Get-GpuClockLimits $Idx
    
    # 1. Enable persistence mode (keeps driver loaded)
    Write-Color "  [1/4] Persistence mode... " "Gray"
    $pmResult = Invoke-NvidiaSmi -Arguments @('-i', "$Idx", '-pm', '1')
    if ($pmResult.Ok) {
        Write-ColorLine "ON" "Green"
    } else {
        Write-ColorLine "NOT SUPPORTED/FAILED" "Yellow"
    }
    
    # 2. Lock memory clocks first (higher mem clock unlocks higher GPU bins)
    if ($limits.Mem -gt 0) {
        Write-Color "  [2/4] Lock mem clock to $($limits.Mem) MHz... " "Gray"
        $memResult = Invoke-NvidiaSmi -Arguments @('-i', "$Idx", '-lmc', "$($limits.Mem),$($limits.Mem)")
        if ($memResult.Ok) {
            Write-ColorLine "REQUESTED" "Green"
        } else {
            Write-ColorLine "FAILED" "Red"
        }
    } else {
        Write-Color "  [2/4] Lock mem clock... " "Gray"
        Write-ColorLine "SKIPPED (couldn't detect max clock)" "Yellow"
    }

    # 3. Lock GPU clocks to max
    if ($limits.Gpu -gt 0) {
        Write-Color "  [3/4] Lock GPU clock to $($limits.Gpu) MHz... " "Gray"
        $gpuResult = Invoke-NvidiaSmi -Arguments @('-i', "$Idx", '-lgc', "$($limits.Gpu),$($limits.Gpu)")
        if ($gpuResult.Ok) {
            Write-ColorLine "REQUESTED" "Green"
        } else {
            Write-ColorLine "FAILED" "Red"
        }
    } else {
        Write-Color "  [3/4] Lock GPU clock... " "Gray"
        Write-ColorLine "SKIPPED (couldn't detect max clock)" "Yellow"
    }
    
    # 4. Set compute mode to exclusive process (optional, good for inference)
    Write-Color "  [4/4] Set power preference... " "Gray"
    $gomResult = Invoke-NvidiaSmi -Arguments @('-i', "$Idx", '--gom=0')
    if ($gomResult.Ok) {
        Write-ColorLine "MAX PERFORMANCE" "Green"
    } else {
        Write-ColorLine "UNSUPPORTED/UNCHANGED" "Yellow"
    }

    # Retry lock check a few times -- driver may need a moment to apply the new clock limits
    $confirm = $null
    for ($i = 1; $i -le 3; $i++) {
        Start-Sleep -Seconds 2
        $confirm = Confirm-LockState $Idx
        if ($confirm.GpuOk -and $confirm.MemOk) { break }
    }
    if ($confirm.GpuOk -and $confirm.MemOk) {
        Write-ColorLine "  [CHK]  Lock verification: APPLIED" "BrightGreen"
    } else {
        Write-ColorLine "  [CHK]  Lock verification: NOT APPLIED" "BrightRed"
        Write-ColorLine "         Current: GPU $($confirm.Status.GpuClockMHz) MHz / MEM $($confirm.Status.MemClockMHz) MHz" "Yellow"
        Write-ColorLine "         This indicates driver policy/runtime is ignoring lock requests." "Yellow"
        if ($pmResult.Text) {
            Write-ColorLine "         pm: $($pmResult.Text)" "Gray"
        }
        if ($memResult -and $memResult.Text) {
            Write-ColorLine "         lmc: $($memResult.Text)" "Gray"
        }
        if ($gpuResult -and $gpuResult.Text) {
            Write-ColorLine "         lgc: $($gpuResult.Text)" "Gray"
        }
    }
    
    Write-Host ""
    Write-ColorLine "  Note: Idle can still show P8/P5; under load, healthy states are usually P0/P1/P2." "Gray"
}

function Reset-Performance {
    param([int]$Idx)
    
    Write-ColorLine "  >> Resetting to default performance state..." "Yellow"
    Write-Host ""
    
    Write-Color "  [1/3] Reset GPU clocks... " "Gray"
    & $NVIDIA_SMI -i $Idx -rgc 2>&1 | Out-Null
    Write-ColorLine "OK" "Green"
    
    Write-Color "  [2/3] Reset mem clocks... " "Gray"
    & $NVIDIA_SMI -i $Idx -rmc 2>&1 | Out-Null
    Write-ColorLine "OK" "Green"
    
    Write-Color "  [3/3] Disable persistence... " "Gray"
    & $NVIDIA_SMI -i $Idx -pm 0 2>&1 | Out-Null
    Write-ColorLine "OK" "Green"
    
    Write-Host ""
    Write-ColorLine "  OK GPU returned to default power management." "BrightGreen"
}

function Start-Monitor {
    param([int]$Idx)
    
    Write-ColorLine "  >> Live monitoring (Ctrl+C to stop)" "Cyan"
    Write-ColorLine "  --------------------------------------------" "Gray"
    Write-Host ""
    Write-ColorLine "  TIME       PSTATE  GPU_CLK  MEM_CLK  UTIL  TEMP  POWER    VRAM" "Gray"
    
    while ($true) {
        $s = Get-GpuStatus $Idx
        $time = Get-Date -Format "HH:mm:ss"
        
        $pcolor = if ($s.PState -eq "P0") { "BrightGreen" } 
                  elseif ($s.PState -match "P[12]") { "Green" } 
                  elseif ($s.PState -match "P[35]") { "Yellow" } 
                  else { "BrightRed" }
        
        Write-Color "  $time   " "White"
        Write-Color "$($s.PState.PadRight(6)) " $pcolor
        Write-Color "$($s.GpuClockMHz.PadLeft(5))MHz " "White"
        Write-Color "$($s.MemClockMHz.PadLeft(5))MHz " "White"
        Write-Color "$($s.GpuUtil.PadLeft(4))% " "Cyan"
        Write-Color "$($s.TempC.PadLeft(4))C " "White"
        Write-Color "$($s.PowerDraw.PadLeft(6))W " "White"
        Write-ColorLine "$($s.MemUsedMB.PadLeft(5))/$($s.MemTotalMB)MB" "Gray"
        
        Start-Sleep -Seconds $PollIntervalSeconds
    }
}

function Start-AutoMode {
    param([int]$Idx)
    
    $boosted = $false
    Write-ColorLine "  >> Auto mode: watching for '$WatchProcess'" "Cyan"
    Write-ColorLine "    Will prepare sustained boost when process detected, reset when it exits." "Gray"
    Write-ColorLine "    Polling every ${PollIntervalSeconds}s. Ctrl+C to stop." "Gray"
    Write-Host ""
    
    while ($true) {
        # Look for LM Studio or user-specified process
        $found = Get-Process | Where-Object { 
            $_.ProcessName -match $WatchProcess -or 
            $_.MainWindowTitle -match $WatchProcess 
        }
        
        if ($found -and -not $boosted) {
            $time = Get-Date -Format "HH:mm:ss"
            Write-ColorLine "  [$time] Detected '$WatchProcess' -- applying sustained boost profile!" "BrightGreen"
            Enable-MaxPerformance $Idx
            $boosted = $true
        }
        elseif (-not $found -and $boosted) {
            $time = Get-Date -Format "HH:mm:ss"
            Write-ColorLine "  [$time] '$WatchProcess' exited -- resetting GPU." "Yellow"
            Reset-Performance $Idx
            $boosted = $false
        }
        
        # Mini status line
        $s = Get-GpuStatus $Idx
        $time = Get-Date -Format "HH:mm:ss"
        $stateIcon = if ($boosted) { "^" } else { "o" }
        $pcolor = if ($s.PState -eq "P0") { "BrightGreen" } else { "Gray" }
        Write-Color "  $stateIcon [$time] " "Gray"
        Write-Color "$($s.PState) " $pcolor
        Write-Color "$($s.GpuClockMHz)MHz " "White"
        Write-Color "$($s.GpuUtil)% " "Cyan"
        Write-ColorLine "$($s.TempC)C" "Gray"
        
        Start-Sleep -Seconds $PollIntervalSeconds
    }
}

# -- Main -----------------------------------------------------------------------

Write-Banner
$gpuIdx = Find-A2000GpuIndex

switch ($Mode) {
    "status"  { Show-Status $gpuIdx }
    "boost"   { Enable-MaxPerformance $gpuIdx; Write-Host ""; Show-Status $gpuIdx }
    "reset"   { Reset-Performance $gpuIdx; Write-Host ""; Show-Status $gpuIdx }
    "monitor" { Show-Status $gpuIdx; Start-Monitor $gpuIdx }
    "auto"    { Show-Status $gpuIdx; Start-AutoMode $gpuIdx }
    "fix"     {
        Write-ColorLine "  >> Full recovery: TCC mode + reg keys + driver restart + clock lock" "BrightCyan"
        Write-Host ""

        # Step 0: enforce driver model based on registry profile
        if ($RegProfile -eq "legacy") {
            # Legacy = WDDM mode + PowerMizer registry keys
            $model = (& $NVIDIA_SMI -i $gpuIdx --query-gpu=driver_model.current --format=csv,noheader,nounits 2>&1).Trim()
            Write-Color "  [DRV]  Current driver model: " "Gray"
            if ($model -eq "TCC") {
                Write-ColorLine "TCC -- switching to WDDM for legacy profile..." "Yellow"
                $res = Invoke-NvidiaSmi -Arguments @('-i', "$gpuIdx", '-dm', '0')
                if ($res.Ok) {
                    Write-ColorLine "  [DRV]  WDDM switch requested. REBOOT REQUIRED." "BrightYellow"
                    Write-ColorLine "         After reboot, re-run: .\gpu-force-boost.ps1 -Mode fix -RegProfile legacy" "Yellow"
                } else {
                    Write-ColorLine "  [DRV]  FAILED: $($res.Text)" "BrightRed"
                }
                break
            } else {
                Write-ColorLine "WDDM  (legacy/PowerMizer profile will be applied)" "BrightGreen"
            }
        } else {
            # TCC mode required for lgc/lmc clock locks to be honored
            $tccOk = Ensure-TccMode $gpuIdx
            Write-Host ""
            if (-not $tccOk) {
                Write-ColorLine "  ACTION REQUIRED: Reboot now, then re-run: .\gpu-force-boost.ps1 -Mode fix" "BrightYellow"
                Write-ColorLine "  Skipping reg + driver bounce (TCC switch needs a full reboot first)." "Yellow"
                break
            }
        }
        Write-Host ""

        $regChanged = Ensure-RegistryKeys
        Write-Host ""

        if ($regChanged) {
            # Registry was just changed -- need driver restart to reload it
            $driverOk = Invoke-GpuDriverRestart
            if (-not $driverOk) {
                Write-Host ""
                Write-ColorLine "  Driver restart failed or incomplete. Please reboot and then run:" "Yellow"
                Write-ColorLine "    .\gpu-force-boost.ps1 -Mode fix" "White"
                break
            }
        } else {
            # TCC + registry already correct -- driver bounce would just reset any existing locks
            # Skip it and go straight to locking clocks
            Write-ColorLine "  [Drv]  Config already correct -- skipping driver bounce, applying clock locks directly." "Cyan"
        }

        Write-Host ""
        Enable-MaxPerformance $gpuIdx
        Write-Host ""
        Show-Status $gpuIdx
    }
}

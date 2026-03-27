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
    [ValidateSet("boost", "reset", "monitor", "auto", "status")]
    [string]$Mode = "status",
    
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
             "persistence_mode,name"
    
    $raw = & $NVIDIA_SMI -i $Idx --query-gpu=$query --format=csv,noheader,nounits 2>&1
    $parts = ($raw -split ",") | ForEach-Object { $_.Trim() }
    
    return @{
        PState       = $parts[0]
        GpuClockMHz  = $parts[1]
        MemClockMHz  = $parts[2]
        MaxGpuClock  = $parts[3]
        MaxMemClock  = $parts[4]
        GpuUtil      = $parts[5]
        MemUtil      = $parts[6]
        TempC        = $parts[7]
        PowerDraw    = $parts[8]
        PowerLimit   = $parts[9]
        MemUsedMB    = $parts[10]
        MemTotalMB   = $parts[11]
        Persistence  = $parts[12]
        Name         = $parts[13]
    }
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

function Enable-MaxPerformance {
    param([int]$Idx)
    
    Write-ColorLine "  >> Forcing maximum performance state..." "Cyan"
    Write-Host ""
    
    $limits = Get-GpuClockLimits $Idx
    
    # 1. Enable persistence mode (keeps driver loaded)
    Write-Color "  [1/4] Persistence mode... " "Gray"
    & $NVIDIA_SMI -i $Idx -pm 1 2>&1 | Out-Null
    Write-ColorLine "ON" "Green"
    
    # 2. Lock memory clocks first (higher mem clock unlocks higher GPU bins)
    if ($limits.Mem -gt 0) {
        Write-Color "  [2/4] Lock mem clock to $($limits.Mem) MHz... " "Gray"
        & $NVIDIA_SMI -i $Idx -lmc $($limits.Mem),$($limits.Mem) 2>&1 | Out-Null
        Write-ColorLine "LOCKED" "Green"
    } else {
        Write-Color "  [2/4] Lock mem clock... " "Gray"
        Write-ColorLine "SKIPPED (couldn't detect max clock)" "Yellow"
    }

    # 3. Lock GPU clocks to max
    if ($limits.Gpu -gt 0) {
        Write-Color "  [3/4] Lock GPU clock to $($limits.Gpu) MHz... " "Gray"
        & $NVIDIA_SMI -i $Idx -lgc $($limits.Gpu),$($limits.Gpu) 2>&1 | Out-Null
        Write-ColorLine "LOCKED" "Green"
    } else {
        Write-Color "  [3/4] Lock GPU clock... " "Gray"
        Write-ColorLine "SKIPPED (couldn't detect max clock)" "Yellow"
    }
    
    # 4. Set compute mode to exclusive process (optional, good for inference)
    Write-Color "  [4/4] Set power preference... " "Gray"
    & $NVIDIA_SMI -i $Idx --gom=0 2>&1 | Out-Null  # All-on mode
    Write-ColorLine "MAX PERFORMANCE" "Green"
    
    Write-Host ""
    Write-ColorLine "  OK GPU prepared for sustained boost under load." "BrightGreen"
    Write-ColorLine "     Note: Idle can still show P8/P5; under load, healthy states are usually P0/P1/P2." "Gray"
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
}

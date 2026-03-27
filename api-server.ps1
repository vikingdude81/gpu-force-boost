<#
.SYNOPSIS
    GPU Force Boost - HTTP API Server for the React dashboard.
    Serves http://localhost:3001 with GPU status, boost, reset, and LM Studio detection.
.NOTES
    Auto-relaunches as Administrator - required for clock locking commands.
#>

# -- Auto-elevate ---------------------------------------------------------------
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    Write-Host "  Relaunching as Administrator..." -ForegroundColor Yellow
    Start-Process powershell -Verb RunAs -ArgumentList "-NoExit", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`""
    exit
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

# -- Find nvidia-smi ------------------------------------------------------------
function Get-NvSmi {
    $p = Get-Command nvidia-smi -ErrorAction SilentlyContinue
    if ($p) { return $p.Source }
    foreach ($path in @("C:\Windows\System32\nvidia-smi.exe", "C:\Program Files\NVIDIA Corporation\NVSMI\nvidia-smi.exe")) {
        if (Test-Path $path) { return $path }
    }
    return $null
}

$NVSMI = Get-NvSmi

# -- Find GPU index -------------------------------------------------------------
function Get-GpuIndex {
    if (-not $NVSMI) { return 0 }
    $out = & $NVSMI --query-gpu=index,name --format=csv,noheader 2>&1
    foreach ($line in ($out -split "`n" | Where-Object { $_.Trim() })) {
        $parts = $line -split ","
        if ($parts.Count -ge 2 -and $parts[1].Trim() -match "A2000") {
            return [int]$parts[0].Trim()
        }
    }
    return 0
}

$GPU_IDX = Get-GpuIndex

# -- Helpers --------------------------------------------------------------------
function Parse-Int($s)    { $c = ($s -replace '[^0-9]',''); if ($c) { [int]$c } else { 0 } }
function Parse-Double($s) { $c = ($s -replace '[^0-9\.]',''); if ($c -match '^\d') { [double]$c } else { 0.0 } }

# -- GPU Status JSON ------------------------------------------------------------
function Get-StatusJson {
    if (-not $NVSMI) { return '{"error":"nvidia-smi not found. Install NVIDIA drivers."}' }

    $query = "pstate,clocks.gr,clocks.mem,clocks.max.gr,clocks.max.mem," +
             "utilization.gpu,utilization.memory,temperature.gpu," +
             "power.draw,power.limit,memory.used,memory.total," +
             "persistence_mode,clocks_throttle_reasons.sw_power_cap,driver_model.current,name"

    $raw = & $NVSMI -i $GPU_IDX --query-gpu=$query --format=csv,noheader,nounits 2>&1

    if ($LASTEXITCODE -ne 0) {
        $msg = ($raw -join " ").Replace('"','\"')
        return "{`"error`":`"nvidia-smi exited $LASTEXITCODE : $msg`"}"
    }

    $parts = ($raw -split ",") | ForEach-Object { $_.Trim() }
    if ($parts.Count -lt 15) {
        return "{`"error`":`"Unexpected nvidia-smi output`"}"
    }

    $swPowerCap = $parts[13].Trim()
    $driverModel = $parts[14].Trim()
    $gpuName = if ($parts.Count -gt 15) { ($parts[15..($parts.Count-1)] -join ",").Trim() } else { "NVIDIA GPU" }
    $clocksLocked = $script:BoostActive -eq $true

    $gpuClock = Parse-Int $parts[1]
    $memClock = Parse-Int $parts[2]
    $gpuUtil = Parse-Int $parts[5]
    $boostActive = ($parts[0] -in @("P0","P1","P2")) -and ($gpuClock -ge 900) -and ($memClock -ge 5000)
    $boostReady = $clocksLocked -or (($parts[0] -in @("P0","P1","P2")) -and ($memClock -ge 5000))

    [PSCustomObject]@{
        pstate       = $parts[0]
        gpuClock     = $gpuClock
        memClock     = $memClock
        maxGpuClock  = Parse-Int    $parts[3]
        maxMemClock  = Parse-Int    $parts[4]
        gpuUtil      = $gpuUtil
        memUtil      = Parse-Int    $parts[6]
        tempC        = Parse-Int    $parts[7]
        powerDraw    = Parse-Double $parts[8]
        powerLimit   = Parse-Double $parts[9]
        memUsedMB    = Parse-Int    $parts[10]
        memTotalMB   = Parse-Int    $parts[11]
        persistence  = ($parts[12] -match "Enabled")
        swPowerCap   = ($swPowerCap -match "^Active")
        driverModel  = $driverModel
        name         = $gpuName
        clocksLocked = $clocksLocked
        boostActive  = $boostActive
        boostReady   = $boostReady
    } | ConvertTo-Json -Compress
}

# -- Track boost state in-process -----------------------------------------------
$script:BoostActive = $false

# -- Boost ----------------------------------------------------------------------
function Invoke-Boost {
    if (-not $NVSMI) { return '{"ok":false,"msg":"nvidia-smi not found"}' }

    $clkRaw  = & $NVSMI -i $GPU_IDX --query-gpu=clocks.max.gr,clocks.max.mem --format=csv,noheader,nounits 2>&1
    $clkParts = ($clkRaw -split ",") | ForEach-Object { $_.Trim() }
    $maxGpu  = Parse-Int $clkParts[0]
    $maxMem  = Parse-Int $clkParts[1]

    $results = @()
    $hardFail = $false

    # 1. Reset any existing locks first (clean slate)
    & $NVSMI -i $GPU_IDX -rgc 2>&1 | Out-Null
    & $NVSMI -i $GPU_IDX -rmc 2>&1 | Out-Null
    Start-Sleep -Milliseconds 200

    # 2. Lock MEMORY clocks first (GPU needs high mem to reach high GPU clocks)
    $lmcOk = $false
    if ($maxMem -gt 0) {
        $out = & $NVSMI -i $GPU_IDX -lmc $maxMem,$maxMem 2>&1 | Out-String
        $lmcOk = $out -match 'locked|set|success|All done'
        if ($out -match 'fail|error|not supported|insufficient|denied') { $hardFail = $true }
        $results += "lmc: $($out.Trim())"
        Start-Sleep -Milliseconds 300
    }

    # 3. Lock GPU clocks to max
    $lgcOk = $false
    if ($maxGpu -gt 0) {
        $out = & $NVSMI -i $GPU_IDX -lgc $maxGpu,$maxGpu 2>&1 | Out-String
        $lgcOk = $out -match 'locked|set|success|All done'
        if ($out -match 'fail|error|not supported|insufficient|denied') { $hardFail = $true }
        $results += "lgc: $($out.Trim())"
        Start-Sleep -Milliseconds 300
    }

    # 4. Set power limit to max to prevent SW Power Cap throttling
    $out = & $NVSMI -i $GPU_IDX -pl 70 2>&1 | Out-String
    if ($out -match 'fail|error|not supported|insufficient|denied') { $hardFail = $true }
    $results += "pl: $($out.Trim())"

    # 5. Persistence mode (may not be supported - that's OK)
    $out = & $NVSMI -i $GPU_IDX -pm 1 2>&1 | Out-String
    if ($out -match 'fail|error|insufficient|denied') { $hardFail = $true }
    $results += "pm1: $($out.Trim())"

    # 6. Try application clocks as fallback (deprecated but may still work)
    if ($maxMem -gt 0 -and $maxGpu -gt 0) {
        $out = & $NVSMI -i $GPU_IDX -ac $maxMem,$maxGpu 2>&1 | Out-String
        $results += "ac: $($out.Trim())"
    }

    # 7. Verify by reading current clocks (with delay for state transition)
    Start-Sleep -Milliseconds 1000
    $verRaw = & $NVSMI -i $GPU_IDX --query-gpu=clocks.gr,clocks.mem,pstate --format=csv,noheader,nounits 2>&1
    $verParts = ($verRaw -split ",") | ForEach-Object { $_.Trim() }
    $nowGpu = Parse-Int $verParts[0]
    $nowMem = Parse-Int $verParts[1]
    $nowPS  = if ($verParts.Count -gt 2) { $verParts[2] } else { '?' }

    $boostReady = ($nowMem -ge 5000) -or ($nowGpu -ge 900)
    $allOk = -not $hardFail
    $script:BoostActive = $allOk

    $detail = "GPU:${nowGpu}/${maxGpu}MHz Mem:${nowMem}/${maxMem}MHz PState:${nowPS}"
    $msg = if ($allOk) {
        if ($boostReady) {
            "Boost profile applied. $detail"
        } else {
            "Boost commands applied. Validate under load (P0/P1/P2 with high mem clock is healthy). $detail"
        }
    } else {
        "Boost command failed on this driver/GPU. $detail"
    }

    $debugLog = ($results -join ' | ').Replace('"','').Replace("`n",' ').Replace("`r",'')
    return "{`"ok`":$($allOk.ToString().ToLower()),`"msg`":`"$msg`",`"debug`":`"$debugLog`",`"gpuClock`":$nowGpu,`"memClock`":$nowMem,`"pstate`":`"$nowPS`"}"
}

# -- Reset ----------------------------------------------------------------------
function Invoke-Reset {
    if (-not $NVSMI) { return '{"ok":false,"msg":"nvidia-smi not found"}' }

    & $NVSMI -i $GPU_IDX -rgc 2>&1 | Out-Null
    & $NVSMI -i $GPU_IDX -rmc 2>&1 | Out-Null
    & $NVSMI -i $GPU_IDX -pm 0  2>&1 | Out-Null
    $script:BoostActive = $false

    Start-Sleep -Milliseconds 500
    $verRaw = & $NVSMI -i $GPU_IDX --query-gpu=clocks.gr,pstate --format=csv,noheader,nounits 2>&1
    $verParts = ($verRaw -split ",") | ForEach-Object { $_.Trim() }
    $nowGpu = Parse-Int $verParts[0]
    $nowPS  = if ($verParts.Count -gt 1) { $verParts[1] } else { '?' }

    return "{`"ok`":true,`"msg`":`"GPU reset to defaults. Now at ${nowGpu}MHz $nowPS`"}"
}

# -- LM Studio detect -----------------------------------------------------------
function Get-DetectJson($processName) {
    if (-not $processName) { $processName = "LM Studio" }
    $found = $null -ne (Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $_.ProcessName -match [regex]::Escape($processName) -or
        $_.MainWindowTitle -match [regex]::Escape($processName)
    } | Select-Object -First 1)
    $safeProc = $processName.Replace('"','\"')
    return "{`"found`":$($found.ToString().ToLower()),`"process`":`"$safeProc`"}"
}

# -- HTTP Server ----------------------------------------------------------------
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:3001/")

try { $listener.Start() }
catch {
    Write-Host "  ERROR: Could not start listener on port 3001. Is another instance running?" -ForegroundColor Red
    Write-Host "  $_" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host ""
Write-Host "  +------------------------------------------+" -ForegroundColor Cyan
Write-Host "  |   GPU Force Boost - Dashboard Server     |" -ForegroundColor Cyan
Write-Host "  +------------------------------------------+" -ForegroundColor Cyan
Write-Host ""
Write-Host "  URL  : http://localhost:3001" -ForegroundColor Green
Write-Host "  GPU  : index $GPU_IDX" -ForegroundColor Gray
Write-Host "  NVSMI: $NVSMI" -ForegroundColor Gray
Write-Host ""
Write-Host "  Opening browser..." -ForegroundColor Gray
Write-Host "  Press Ctrl+C to stop." -ForegroundColor Gray
Write-Host ""

Start-Sleep -Milliseconds 500
Start-Process "http://localhost:3001"

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $req     = $context.Request
        $res     = $context.Response

        $res.Headers.Add("Access-Control-Allow-Origin",  "*")
        $res.Headers.Add("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        $res.Headers.Add("Access-Control-Allow-Headers", "Content-Type")

        $path   = $req.Url.AbsolutePath
        $method = $req.HttpMethod
        $body        = ""
        $contentType = "application/json"
        $statusCode  = 200

        try {
            if ($method -eq "OPTIONS") {
                $statusCode = 204

            } elseif ($path -eq "/" -or $path -eq "/index.html") {
                $contentType = "text/html; charset=utf-8"
                $htmlPath = Join-Path $ScriptDir "index.html"
                if (Test-Path $htmlPath) {
                    $body = Get-Content -Raw -Encoding UTF8 $htmlPath
                } else {
                    $body = "<html><body style='background:#0a0e14;color:#ff4444;font-family:monospace;padding:40px'>index.html not found in: $ScriptDir</body></html>"
                }

            } elseif ($path -eq "/api/status" -and $method -eq "GET") {
                $body = Get-StatusJson

            } elseif ($path -eq "/api/boost" -and $method -eq "POST") {
                $body = Invoke-Boost

            } elseif ($path -eq "/api/reset" -and $method -eq "POST") {
                $body = Invoke-Reset

            } elseif ($path -eq "/api/detect" -and $method -eq "GET") {
                $procParam = $req.QueryString["process"]
                $body = Get-DetectJson $procParam

            } else {
                $statusCode = 404
                $body = '{"error":"Not found"}'
            }
        } catch {
            $statusCode = 500
            $errMsg = $_.ToString().Replace('"','\"')
            $body = "{`"error`":`"Server error: $errMsg`"}"
        }

        $res.StatusCode  = $statusCode
        $res.ContentType = $contentType
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
        $res.ContentLength64 = $bytes.Length
        $res.OutputStream.Write($bytes, 0, $bytes.Length)
        $res.OutputStream.Close()
    }
} finally {
    $listener.Stop()
    Write-Host "  Server stopped." -ForegroundColor Yellow
}

<#
.SYNOPSIS
    Re-applies NVIDIA A2000 performance registry keys that Windows Update wipes on each driver install.
.NOTES
    Requires Administrator rights. Auto-elevates via UAC if not elevated.
    Safe to re-run at any time. Keys are restored to their known-good values.
#>

# --- Auto-elevate if not running as Administrator ---
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    Write-Host "Not running as Administrator - relaunching elevated..." -ForegroundColor Yellow
    Start-Process powershell -Verb RunAs -ArgumentList @('-NoExit', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    exit
}

# --- Find A2000 registry path dynamically (index can shift after driver installs) ---
$classBase = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
$regBase = $null
Get-ChildItem $classBase -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^\d{4}$' } | ForEach-Object {
    $desc = (Get-ItemProperty $_.PSPath -Name 'DriverDesc' -ErrorAction SilentlyContinue).DriverDesc
    if ($desc -match 'A2000') { $regBase = $_.PSPath }
}

if (-not $regBase) {
    Write-Host "ERROR: Could not find RTX A2000 in device registry. Is the driver installed?" -ForegroundColor Red
    exit 1
}

Write-Host "Target registry path: $regBase" -ForegroundColor Cyan

$out = @()
$out += "Target: $regBase"
$current = (Get-ItemProperty $regBase -Name EnableDriverControlledPMM -ErrorAction SilentlyContinue).EnableDriverControlledPMM
$out += "Before: EnableDriverControlledPMM = $(if ($null -eq $current) { '<NOT PRESENT>' } else { $current })"

Set-ItemProperty -Path $regBase -Name "EnableDriverControlledPMM" -Value 1 -Type DWord
Set-ItemProperty -Path $regBase -Name "PerfLevelSrc"              -Value 0x2222 -Type DWord
Set-ItemProperty -Path $regBase -Name "PowerMizerEnable"          -Value 1 -Type DWord
Set-ItemProperty -Path $regBase -Name "PowerMizerLevel"           -Value 1 -Type DWord
Set-ItemProperty -Path $regBase -Name "PowerMizerDefault"         -Value 1 -Type DWord
Set-ItemProperty -Path $regBase -Name "PowerMizerDefaultAC"       -Value 1 -Type DWord
$out += "All keys applied."

"EnableDriverControlledPMM","PerfLevelSrc","PowerMizerEnable","PowerMizerLevel","PowerMizerDefault","PowerMizerDefaultAC" | ForEach-Object {
    $val = (Get-ItemProperty $regBase -Name $_ -ErrorAction SilentlyContinue).$_
    $out += "  $_ = $val"
    Write-Host "  $_ = $val" -ForegroundColor Green
}

$out | Out-File "$PSScriptRoot\reg-result.txt" -Encoding utf8
Write-Host ""
Write-Host "Registry keys written. A GPU driver restart (PnP bounce or reboot) is needed for these to take effect." -ForegroundColor Yellow

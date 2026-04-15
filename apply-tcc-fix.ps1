<#
.SYNOPSIS
    Restore A2000 natural boost in TCC mode.
    Sets EnableDriverControlledPMM=0 (lets TCC handle P-states natively),
    removes PowerMizer overrides, then bounces the driver.
    Run as Administrator.
#>

$classBase = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
$regBase = $null
Get-ChildItem $classBase -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^\d{4}$' } | ForEach-Object {
    $desc = (Get-ItemProperty $_.PSPath -Name 'DriverDesc' -ErrorAction SilentlyContinue).DriverDesc
    if ($desc -match 'A2000') { $regBase = $_.PSPath }
}
if (-not $regBase) { Write-Host "ERROR: A2000 not found in registry" -ForegroundColor Red; exit 1 }

Write-Host "Target: $regBase" -ForegroundColor Cyan

# Set EnableDriverControlledPMM = 0 (let TCC manage P-states natively, not the driver's conservative PMM)
Set-ItemProperty -Path $regBase -Name "EnableDriverControlledPMM" -Value 0 -Type DWord
Write-Host "EnableDriverControlledPMM = 0" -ForegroundColor Green

# Remove PowerMizer overrides (not needed in TCC mode, can interfere)
@('PerfLevelSrc','PowerMizerEnable','PowerMizerLevel','PowerMizerDefault','PowerMizerDefaultAC') | ForEach-Object {
    Remove-ItemProperty -Path $regBase -Name $_ -ErrorAction SilentlyContinue
}
Write-Host "PowerMizer override keys removed" -ForegroundColor Green

Write-Host ""
Write-Host "Bouncing A2000 driver..." -ForegroundColor Yellow
$dev = Get-PnpDevice | Where-Object { $_.FriendlyName -match 'A2000' } | Select-Object -First 1
if (-not $dev) { Write-Host "ERROR: A2000 PnP device not found" -ForegroundColor Red; exit 1 }

Disable-PnpDevice -InstanceId $dev.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
Start-Sleep 4
Enable-PnpDevice  -InstanceId $dev.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
Start-Sleep 5

$s = nvidia-smi -i 0 --query-gpu=pstate,clocks.gr,clocks.mem,power.draw --format=csv,noheader 2>&1
Write-Host ""
Write-Host "Status after restart: $s" -ForegroundColor White
Write-Host ""
Write-Host "Done. Start LM Studio and run a prompt -- GPU should now boost to P2 near 1000-1200 MHz." -ForegroundColor Green

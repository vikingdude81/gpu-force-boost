$out = @()

# Revert PMM to 0
$base = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
Get-ChildItem $base | Where-Object { $_.PSChildName -match '^\d{4}$' } | ForEach-Object {
    $d = (Get-ItemProperty $_.PSPath -Name DriverDesc -EA SilentlyContinue).DriverDesc
    if ($d -match 'A2000') {
        Set-ItemProperty -Path $_.PSPath -Name "EnableDriverControlledPMM" -Value 0 -Type DWord
        $out += "PMM reverted to 0"
    }
}

# Power limit
$out += "=== Power limit ==="
$out += (nvidia-smi -i 0 -pl 70 2>&1 | Out-String)

# Reset clocks
$out += "=== Reset clocks ==="
$out += (nvidia-smi -i 0 -rgc 2>&1 | Out-String)
$out += (nvidia-smi -i 0 -rmc 2>&1 | Out-String)

# Re-lock
$out += "=== Re-lock ==="
$out += (nvidia-smi -i 0 -lmc 6001,6001 2>&1 | Out-String)
$out += (nvidia-smi -i 0 -lgc 2100,2100 2>&1 | Out-String)

# Status
$out += "=== Status ==="
$out += (nvidia-smi -i 0 --query-gpu=power.limit,power.default_power_limit,power.min_power_limit,power.max_power_limit --format=csv 2>&1 | Out-String)

$out | Set-Content C:\Users\akbon\Downloads\files\dev-status.txt

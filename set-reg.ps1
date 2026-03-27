$regBase = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0000"
$out = @()
$current = (Get-ItemProperty $regBase -Name EnableDriverControlledPMM).EnableDriverControlledPMM
$out += "Before: EnableDriverControlledPMM = $current"
Set-ItemProperty -Path $regBase -Name "EnableDriverControlledPMM" -Value 1 -Type DWord
Set-ItemProperty -Path $regBase -Name "PerfLevelSrc" -Value 0x2222 -Type DWord
Set-ItemProperty -Path $regBase -Name "PowerMizerEnable" -Value 1 -Type DWord
Set-ItemProperty -Path $regBase -Name "PowerMizerLevel" -Value 1 -Type DWord
Set-ItemProperty -Path $regBase -Name "PowerMizerDefault" -Value 1 -Type DWord
Set-ItemProperty -Path $regBase -Name "PowerMizerDefaultAC" -Value 1 -Type DWord
$out += "All keys set."
"EnableDriverControlledPMM","PerfLevelSrc","PowerMizerEnable","PowerMizerLevel","PowerMizerDefault","PowerMizerDefaultAC" | ForEach-Object {
    $val = (Get-ItemProperty $regBase -Name $_ -ErrorAction SilentlyContinue).$_
    $out += "  $_ = $val"
}
$out | Out-File C:\Users\akbon\Downloads\files\reg-result.txt -Encoding utf8

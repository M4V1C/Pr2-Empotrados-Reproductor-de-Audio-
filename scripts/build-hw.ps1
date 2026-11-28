# Regenera el SoC: tools\build_soc.tcl -> hw\quartus\soc_system.qsys
#                  -> HDL de sintesis (soc_system\synthesis\*.qip) + .sopcinfo
# Uso (PowerShell, desde la raiz del repo):
#     powershell -ExecutionPolicy Bypass -File scripts\build-hw.ps1
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\env.ps1"
$Root = Split-Path -Parent $PSScriptRoot
$Hw   = Join-Path $Root 'hw\quartus'
Push-Location $Hw
try {
    Write-Host '>> qsys-script: tools\build_soc.tcl -> soc_system.qsys' -ForegroundColor Cyan
    Invoke-Tool 'qsys-script' @("--script=$(To-Fwd "$Root\tools\build_soc.tcl")")

    Write-Host '>> qsys-generate: HDL de sintesis (Verilog)' -ForegroundColor Cyan
    Invoke-Tool 'qsys-generate' @('soc_system.qsys', '--synthesis=VERILOG',
                                  "--output-directory=$(To-Fwd "$Hw\soc_system")")

    $sopc = @("$Hw\soc_system.sopcinfo", "$Hw\soc_system\soc_system.sopcinfo") |
            Where-Object { Test-Path $_ } | Select-Object -First 1
    Write-Host '>> Listo.' -ForegroundColor Green
    Write-Host "   .qip     : hw\quartus\soc_system\synthesis\soc_system.qip"
    Write-Host "   .sopcinfo: $(if ($sopc) { $sopc } else { 'NO ENCONTRADO' })"
} finally { Pop-Location }

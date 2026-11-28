# Compila una aplicacion del Nios V y deja la imagen de la RAM en
# hw\quartus\nios_ram.hex (con la que Quartus inicializa la RAM on-chip).
# Uso (PowerShell, desde la raiz del repo):
#     powershell -ExecutionPolicy Bypass -File scripts\build-sw.ps1 sw\niosv\hw_tests\hola
# Requiere haber corrido antes build-hw.ps1 (necesita el .sopcinfo).
param([Parameter(Mandatory = $true)][string]$SrcDir)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\env.ps1"
$Root = Split-Path -Parent $PSScriptRoot
$Hw   = Join-Path $Root 'hw\quartus'

$Src = (Resolve-Path (Join-Path $Root $SrcDir)).Path
$App = Split-Path -Leaf $Src
$sopc = @("$Hw\soc_system.sopcinfo", "$Hw\soc_system\soc_system.sopcinfo") |
        Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $sopc) { throw 'Falta el .sopcinfo: corra primero scripts\build-hw.ps1' }

$Out = Join-Path $Root "build\niosv\$App"
if (Test-Path $Out) { Remove-Item -Recurse -Force $Out }
New-Item -ItemType Directory -Force $Out | Out-Null

Write-Host ">> BSP (HAL) desde $(Split-Path -Leaf $sopc)" -ForegroundColor Cyan
Invoke-Tool 'niosv-bsp' @('--create', '--type=hal', "--sopcinfo=$(To-Fwd $sopc)",
                          (To-Fwd "$Out\bsp\settings.bsp"))

Write-Host '>> Proyecto de aplicacion (CMake)' -ForegroundColor Cyan
Invoke-Tool 'niosv-app' @("--app-dir=$(To-Fwd "$Out\app")", "--bsp-dir=$(To-Fwd "$Out\bsp")",
                          "--srcs=$(To-Fwd $Src)", "--elf-name=$App.elf")

Write-Host '>> Compilando' -ForegroundColor Cyan
Invoke-Tool 'cmake' @('-G', 'Unix Makefiles', '-S', (To-Fwd "$Out\app"), '-B', (To-Fwd "$Out\app\build"))
Invoke-Tool 'make'  @('-C', (To-Fwd "$Out\app\build"))

$Elf = "$Out\app\build\$App.elf"
# El CMake de niosv-app ya genera <memoria>.hex con elf2hex (-w 32 -r 4:
# un registro por palabra de 32 bits, direcciones en palabras), que es el
# formato que espera Quartus para inicializar la RAM. Solo se copia.
$HexSrc = "$Out\app\build\nios_ram.hex"
if (-not (Test-Path $HexSrc)) { throw "No se genero $HexSrc (revise el nombre de la RAM en el .qsys)" }
Copy-Item -Force $HexSrc "$Hw\nios_ram.hex"
Write-Host '>> nios_ram.hex copiado a hw\quartus' -ForegroundColor Cyan

Write-Host '>> Tamano del programa (text+data+bss debe ser < 131072 B):' -ForegroundColor Cyan
Invoke-Tool 'riscv32-unknown-elf-size' @((To-Fwd $Elf))
Write-Host '>> Listo: hw\quartus\nios_ram.hex' -ForegroundColor Green

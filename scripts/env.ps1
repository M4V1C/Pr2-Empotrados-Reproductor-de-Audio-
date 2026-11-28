# Entorno de herramientas en Windows (Quartus Prime Lite 25.1std + Nios V).
# Lo cargan build-hw.ps1 y build-sw.ps1:   . "$PSScriptRoot\env.ps1"
# Ajuste $env:ALTERA_ROOT si Quartus esta en otra ruta.
# Replica lo que hace niosv-shell.exe: agrega al PATH las carpetas de
# Quartus, Platform Designer, Nios V y RiscFree (make, cmake, gcc RISC-V).

if (-not $env:ALTERA_ROOT) { $env:ALTERA_ROOT = 'C:\altera_lite\25.1std' }
$A = $env:ALTERA_ROOT
if (-not (Test-Path "$A\quartus\bin64\quartus_sh.exe")) {
    throw "No encuentro Quartus en '$A\quartus'. Defina `$env:ALTERA_ROOT."
}
$env:QUARTUS_ROOTDIR = "$A\quartus"
$env:SOPC_KIT_NIOS2  = "$A\nios2eds"
$env:PATH = @(
    "$A\quartus\bin64",
    "$A\quartus\sopc_builder\bin",
    "$A\niosv\bin",
    "$A\riscfree\build_tools\bin",
    "$A\riscfree\build_tools\cmake\bin",
    "$A\riscfree\toolchain\riscv32-unknown-elf\bin",
    $env:PATH
) -join ';'

# Corre un programa externo y aborta si devuelve codigo de error
# (PowerShell no lo hace solo con ejecutables nativos).
function Invoke-Tool {
    param([string]$Exe, [string[]]$ToolArgs)
    Write-Host "   $Exe $($ToolArgs -join ' ')" -ForegroundColor DarkGray
    & $Exe @ToolArgs
    if ($LASTEXITCODE -ne 0) { throw "$Exe termino con codigo $LASTEXITCODE" }
}

# Las herramientas de Nios V prefieren rutas con '/'
function To-Fwd([string]$p) { return ($p -replace '\\', '/') }

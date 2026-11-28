#!/usr/bin/env bash
# Compila una aplicacion del Nios V y deja la imagen de la RAM en
# hw/quartus/nios_ram.hex (con la que Quartus inicializa la RAM on-chip).
#
# Uso (WSL):  scripts/build-sw.sh <dir_de_fuentes>
#   ej.:      scripts/build-sw.sh sw/niosv/hw_tests/hola
# Requiere haber corrido antes scripts/build-hw.sh (necesita el .sopcinfo).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$HERE/scripts/env.sh"

SRC="$(cd "$HERE/${1:?Uso: build-sw.sh <dir_de_fuentes>}" && pwd)"
APP="$(basename "$SRC")"
SOPC=$(ls "$HERE"/hw/quartus/soc_system.sopcinfo "$HERE"/hw/quartus/soc_system/soc_system.sopcinfo 2>/dev/null | head -1 || true)
[ -n "$SOPC" ] || { echo "ERROR: falta el .sopcinfo; corra scripts/build-hw.sh" >&2; exit 1; }

OUT="$HERE/build/niosv/$APP"
rm -rf "$OUT"; mkdir -p "$OUT"

echo ">> BSP (HAL) desde $(basename "$SOPC")"
niosv-bsp --create --type=hal --sopcinfo="$SOPC" "$OUT/bsp/settings.bsp"

echo ">> Proyecto de aplicacion (CMake)"
niosv-app --app-dir="$OUT/app" --bsp-dir="$OUT/bsp" --srcs="$SRC" --elf-name="$APP.elf"

echo ">> Compilando"
cmake -G "Unix Makefiles" -S "$OUT/app" -B "$OUT/app/build" >/dev/null
make -C "$OUT/app/build"

ELF="$OUT/app/build/$APP.elf"
# El CMake de niosv-app ya genera <memoria>.hex con elf2hex (-w 32 -r 4:
# un registro por palabra, direcciones en palabras). Solo se copia.
cp "$OUT/app/build/nios_ram.hex" "$HERE/hw/quartus/nios_ram.hex"
echo ">> nios_ram.hex copiado a hw/quartus"

echo ">> Tamano del programa (debe caber en 131072 B):"
riscv32-unknown-elf-size "$ELF"
echo ">> Listo: hw/quartus/nios_ram.hex"

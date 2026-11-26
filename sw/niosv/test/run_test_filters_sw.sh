#================================================================================================================
#                ~~~~~ Prueba en la PC de los filtros de software (issue F-07 en el repo) ~~~~~
#
# Uso (desde cualquier carpeta, relativo a la raiz del repo):
#   sw/niosv/test/run_test_filters_sw.sh
#
# 1. Compila filters_sw.c + test_filters_sw.c con el gcc del host y corre la prueba contra sim/vectors/pb_*
#    y eco_* (bit a bit contra el modelo).
# 2. Si esta el toolchain del Nios (riscv32-unknown-elf-gcc, en el PATH con 'qenv'), compila filters_sw.c
#    para RV32I y revisa que NO use rutinas de multiplicacion/division por software (__mulsi3, __divsi3, etc)
#================================================================================================================
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"

BUILD=sw/niosv/test/build
mkdir -p "$BUILD"

echo "== 1. Prueba en la PC host (gcc del host) =="
gcc -std=c11 -O2 -Wall -Wextra -Werror \
    -I sw/niosv/src \
    sw/niosv/src/filters_sw.c sw/niosv/test/test_filters_sw.c \
    -o "$BUILD/test_filters_sw"
"$BUILD/test_filters_sw" sim/vectors | tee "$BUILD/test_filters_sw.log"

echo
echo "== 2. Revision para el Nios V/m =="
if command -v riscv32-unknown-elf-gcc >/dev/null 2>&1; then
    riscv32-unknown-elf-gcc -march=rv32i_zicsr -mabi=ilp32 -Os -c \
        -I sw/niosv/src sw/niosv/src/filters_sw.c -o "$BUILD/filters_sw_rv32i.o"
    PROHIBIDAS=$(riscv32-unknown-elf-nm -u "$BUILD/filters_sw_rv32i.o" \
                 | grep -E '__(mul|div|mod|udiv|umod)' || true)
    if [ -z "$PROHIBIDAS" ]; then
        echo "[PASS] filters_sw.c no llama a multiplicacion/division por software"
    else
        echo "[FAIL] filters_sw.c usa rutinas prohibidas de multiplicacion/division:"
        echo "$PROHIBIDAS"
        exit 1
    fi
    riscv32-unknown-elf-size "$BUILD/filters_sw_rv32i.o"
else
    echo "(se salta: riscv32-unknown-elf-gcc no esta en el PATH; correr 'qenv' antes)"
fi

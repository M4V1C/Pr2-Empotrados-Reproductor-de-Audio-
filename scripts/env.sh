#!/usr/bin/env bash
# Entorno de herramientas (WSL/Linux): Quartus + Platform Designer + Nios V.
# Uso:  source scripts/env.sh
# Ajuste ALTERA_ROOT si Quartus 25.1std esta en otra ruta.

: "${ALTERA_ROOT:=$HOME/altera_lite/25.1std}"

if [ ! -d "$ALTERA_ROOT/quartus" ]; then
    echo "ERROR: no encuentro Quartus en '$ALTERA_ROOT/quartus'." >&2
    echo "       export ALTERA_ROOT=/ruta/a/altera_lite/25.1std" >&2
    return 1 2>/dev/null || exit 1
fi

export QUARTUS_ROOTDIR="$ALTERA_ROOT/quartus"
export PATH="$QUARTUS_ROOTDIR/bin:$QUARTUS_ROOTDIR/sopc_builder/bin:$ALTERA_ROOT/niosv/bin:$ALTERA_ROOT/riscfree/toolchain/riscv32-unknown-elf/bin:$ALTERA_ROOT/questa_fse/bin:$PATH"

# Questa Starter usa SALT, no FLEXlm.
: "${SALT_LICENSE_SERVER:=$HOME/.altera.quartus/questa_lic.dat}"
export SALT_LICENSE_SERVER

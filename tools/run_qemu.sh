#!/usr/bin/env bash
# Arranca el Linux minimo en QEMU vexpress-a9 con la imagen de SD.
# Uso: run_qemu.sh [--shell] [imagen_sd]
#   (sin --shell) prueba automatica: monta la SD, lista la playlist y apaga.
#   --shell       deja la consola interactiva (salir: Ctrl-A X).
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
BR_DIR=${BR_DIR:-$REPO/../buildroot-${BR_VER:-2025.02}}
IMG=$BR_DIR/output/images

mode=autotest
if [ "${1:-}" = "--shell" ]; then
    mode=""
    shift
fi
SD=${1:-$REPO/sw/storage/build/sd.img}

for f in "$IMG/zImage" "$IMG/vexpress-v2p-ca9.dtb" "$IMG/rootfs.cpio.gz" "$SD"; do
    [ -f "$f" ] || { echo "Falta $f" >&2; exit 1; }
done

args=(-M vexpress-a9 -m 256
      -kernel "$IMG/zImage" -dtb "$IMG/vexpress-v2p-ca9.dtb"
      -initrd "$IMG/rootfs.cpio.gz"
      -drive "file=$SD,if=sd,format=raw"
      -append "console=ttyAMA0,115200 $mode"
      -nographic -net none)

if [ -n "$mode" ]; then
    exec timeout 180 qemu-system-arm "${args[@]}"   # red de seguridad si poweroff no cierra QEMU
else
    exec qemu-system-arm "${args[@]}"
fi

#!/usr/bin/env bash
# Construye un Linux minimo (Buildroot) para QEMU vexpress-a9 (Cortex-A9) con main_list
# dentro. Buildroot se descarga fuera del repo: <Proyecto2>/workarea/buildroot-<version>.
# Antes: make -C sw/storage list-arm   (genera sw/storage/build/main_list_arm)
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
BR_VER=${BR_VER:-2025.02}
BR_DIR=${BR_DIR:-$REPO/../buildroot-$BR_VER}
BIN=$REPO/sw/storage/build/main_list_arm

[ -f "$BIN" ] || { echo "Falta $BIN. Correr: make -C sw/storage list-arm" >&2; exit 1; }
command -v bc >/dev/null || { echo "Falta 'bc'. Instalar: sudo apt install bc" >&2; exit 1; }

if [ ! -d "$BR_DIR" ]; then
    mkdir -p "$BR_DIR"
    wget -O "$BR_DIR/.download.tar.gz" "https://buildroot.org/downloads/buildroot-$BR_VER.tar.gz"
    tar -xzf "$BR_DIR/.download.tar.gz" --strip-components=1 -C "$BR_DIR"
    rm -f "$BR_DIR/.download.tar.gz"
fi

# overlay del rootfs: script de prueba + binario ARM estatico
OVERLAY=$BR_DIR/pr2_overlay
rm -rf "$OVERLAY"
mkdir -p "$OVERLAY/usr/bin"
cp -a "$HERE/overlay/." "$OVERLAY/"
chmod 755 "$OVERLAY/etc/init.d/S99storage-test"
install -m 755 "$BIN" "$OVERLAY/usr/bin/main_list"

# defconfig = el de vexpress de Buildroot + nuestros cambios
{
    cat "$BR_DIR/configs/qemu_arm_vexpress_defconfig"
    cat "$HERE/pr2_vexpress.fragment"
    echo "BR2_ROOTFS_OVERLAY=\"$OVERLAY\""
    echo "BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES=\"$HERE/linux.fragment\""
} > "$BR_DIR/configs/pr2_vexpress_defconfig"

make -C "$BR_DIR" pr2_vexpress_defconfig
make -C "$BR_DIR" -j"$(nproc)"

echo "Listo. Imagenes en $BR_DIR/output/images"

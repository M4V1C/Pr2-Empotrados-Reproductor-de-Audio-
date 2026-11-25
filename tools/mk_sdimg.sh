#!/usr/bin/env bash
# Arma una imagen FAT32 de SD con los WAV de un directorio, sin root (mtools).
# Uso: mk_sdimg.sh <dir_con_wavs> <imagen_salida> [tamano_MB=256]
# Requiere: dosfstools (mkfs.vfat) y mtools (mcopy).
set -euo pipefail
export PATH="$PATH:/usr/sbin:/sbin"   # mkfs.vfat vive en sbin (no esta en el PATH de usuario en Debian)

if [ $# -lt 2 ]; then
    echo "Uso: $0 <dir_con_wavs> <imagen_salida> [tamano_MB=256]" >&2
    exit 1
fi

src=$1
img=$2
size_mb=${3:-256}   # FAT32 exige >= 65525 clusters: con menos de ~64 MB mkfs cambia a FAT16

for cmd in mkfs.vfat mcopy mdir; do
    command -v "$cmd" >/dev/null || {
        echo "Falta '$cmd'. Instalar: sudo apt install dosfstools mtools" >&2
        exit 1
    }
done

shopt -s nullglob
wavs=("$src"/*.wav)
[ ${#wavs[@]} -gt 0 ] || { echo "No hay .wav en $src" >&2; exit 1; }

mkdir -p "$(dirname "$img")"
rm -f "$img"
truncate -s "${size_mb}M" "$img"            # archivo disperso: no ocupa 256 MB reales
mkfs.vfat -F 32 -n AUDIO "$img" >/dev/null
mcopy -i "$img" "${wavs[@]}" ::/

echo "Imagen lista: $img"
mdir -i "$img" ::/

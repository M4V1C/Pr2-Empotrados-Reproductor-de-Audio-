#!/usr/bin/env bash
# Sube la rama actual a origin y (opcional) abre un Pull Request hacia develop.
#
# No toca develop ni main, no mezcla ramas y nunca usa --force: la integración
# se hace por PR, como en el resto del equipo. Pide confirmación antes de cada
# acción visible para los demás (push y PR).
#
# Uso (desde cualquier carpeta del repo, parado en la rama a subir):
#   tools/push-branch.sh              push + ofrece abrir el PR
#   tools/push-branch.sh --no-pr      solo push
#   tools/push-branch.sh --draft      el PR se abre como borrador
#   BASE=main tools/push-branch.sh    otra rama destino (por defecto: develop)
set -euo pipefail

BASE=${BASE:-develop}
HACER_PR=1
BORRADOR=0

for arg in "$@"; do
    case "$arg" in
        --no-pr) HACER_PR=0 ;;
        --draft) BORRADOR=1 ;;
        -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Opción desconocida: $arg (ver --help)" >&2; exit 2 ;;
    esac
done

die() { echo "Error: $*" >&2; exit 1; }

confirmar() { # pregunta -> 0 si responde s/y
    local r
    read -r -p "$1 [s/N] " r
    case "$r" in [sSyY]|[sS][iíIí]|[yY][eE][sS]) return 0 ;; *) return 1 ;; esac
}

git rev-parse --git-dir >/dev/null 2>&1 || die "no estás dentro de un repositorio git."
cd "$(git rev-parse --show-toplevel)"

RAMA=$(git rev-parse --abbrev-ref HEAD)
[ "$RAMA" != "HEAD" ] || die "HEAD desacoplado: cambiá a una rama (git switch <rama>)."
case "$RAMA" in
    main|master|"$BASE") die "no se corre parado en '$RAMA'. Cambiá a tu rama de trabajo." ;;
esac

if [ -n "$(git status --porcelain)" ]; then
    echo "Hay cambios sin commitear:" >&2
    git status --short >&2
    die "commiteá o guardá (git stash) antes de subir."
fi

echo "Actualizando referencias remotas..."
git fetch --quiet origin
git rev-parse --verify -q "origin/$BASE" >/dev/null || die "no existe origin/$BASE."

NUEVOS=$(git rev-list --count "origin/$BASE..HEAD")
ATRAS=$(git rev-list --count "HEAD..origin/$BASE")

[ "$NUEVOS" -gt 0 ] || die "'$RAMA' no tiene commits que no estén ya en origin/$BASE."

echo
echo "Rama:    $RAMA"
echo "Destino: $BASE"
echo "Commits nuevos respecto a origin/$BASE ($NUEVOS):"
git log --format='  %h %s' "origin/$BASE..HEAD"
echo

if [ "$ATRAS" -gt 0 ]; then
    echo "AVISO: origin/$BASE tiene $ATRAS commit(s) que tu rama no tiene:"
    git log --format='  %h %s' "HEAD..origin/$BASE" | head -10
    echo "Conviene actualizar antes del PR para evitar conflictos:"
    echo "  git merge origin/$BASE"
    confirmar "¿Subir de todas formas?" || { echo "Cancelado."; exit 1; }
    echo
fi

confirmar "¿Hacer push de '$RAMA' a origin?" || { echo "Cancelado."; exit 1; }
git push -u origin "$RAMA"

[ "$HACER_PR" -eq 1 ] || { echo "Listo: '$RAMA' subida (sin PR)."; exit 0; }

command -v gh >/dev/null || { echo "Falta 'gh': abrí el PR desde la web."; exit 0; }

EXISTENTE=$(gh pr list --head "$RAMA" --state open --json url --jq '.[0].url' 2>/dev/null || true)
if [ -n "$EXISTENTE" ]; then
    echo "Ya hay un PR abierto para '$RAMA' (el push lo actualizó): $EXISTENTE"
    exit 0
fi

echo
confirmar "¿Abrir un PR de '$RAMA' hacia '$BASE'?" || { echo "Listo: '$RAMA' subida, sin PR."; exit 0; }

TITULO_SUGERIDO=$(printf '%s' "$RAMA" | sed 's#/#: #; s/-/ /g')
if [ "$NUEVOS" -eq 1 ]; then
    TITULO_SUGERIDO=$(git log -1 --format=%s)
fi
read -r -p "Título del PR [$TITULO_SUGERIDO]: " TITULO
TITULO=${TITULO:-$TITULO_SUGERIDO}

CUERPO=$(mktemp)
trap 'rm -f "$CUERPO"' EXIT
{
    echo "## Cambios"
    git log --reverse --format='- %s' "origin/$BASE..HEAD"
    # Referencias a issues escritas en los commits (Closes/Refs/Fixes #N)
    REFS=$(git log --format=%B "origin/$BASE..HEAD" |
           grep -oiE '(closes|fixes|resolves|refs)[: ]+#[0-9]+' | sort -u || true)
    if [ -n "$REFS" ]; then
        echo
        echo "## Issues"
        printf '%s\n' "$REFS" | sed 's/^/- /'
    fi
} > "$CUERPO"

ARGS=(--base "$BASE" --head "$RAMA" --title "$TITULO" --body-file "$CUERPO")
[ "$BORRADOR" -eq 1 ] && ARGS+=(--draft)

URL=$(gh pr create "${ARGS[@]}")
echo "PR creado: $URL"
if [ "$BASE" != "$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)" ]; then
    echo "Nota: GitHub solo cierra issues con 'Closes #N' cuando el PR llega a la rama por"
    echo "defecto. Cerrá a mano los issues al mergear, o espera al merge de $BASE a main."
fi

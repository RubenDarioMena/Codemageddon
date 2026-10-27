#!/bin/sh
# Abre el juego en escritorio para probarlo: en el repo principal o en el worktree de un agente.
#   uso: sh tools/agentes/probar.sh [worktree] [args de Godot]
#     sh tools/agentes/probar.sh                                  # main
#     sh tools/agentes/probar.sh ../Codemageddon-wt/codex-<feature>
#     sh tools/agentes/probar.sh <worktree> -e                    # en el editor
#     sh tools/agentes/probar.sh <worktree> -- --guion=res://pruebas/guion_programas.gd
#
# Un worktree recién creado no trae lo que git ignora, y el script lo prepara:
#   servicio/node_modules  sin él no arranca Node y el juego cae a SQLite sin programas JS.
#                          Se enlaza el del repo principal si package-lock.json no cambió;
#                          si cambió, npm ci.
#   .godot/                el juego sin editor no importa GLB ni texturas: se importa siempre
#                          (unos segundos), así también entran los assets nuevos del ciclo.
set -e

G=${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}
aqui=$(cd "$(dirname "$0")" && pwd)
principal=$(dirname "$(git -C "$aqui" rev-parse --path-format=absolute --git-common-dir)")

proyecto="$principal/Concepto2"
case "$1" in
  ""|-*) ;;
  *)
    [ -d "$1" ] || { echo "no existe el worktree: $1" >&2; exit 1; }
    if [ -f "$1/project.godot" ]; then proyecto=$(cd "$1" && pwd); else proyecto=$(cd "$1/Concepto2" && pwd); fi
    shift
    ;;
esac
[ -f "$proyecto/project.godot" ] || { echo "no hay project.godot en $proyecto" >&2; exit 1; }

srv="$proyecto/servicio"
srv_principal="$principal/Concepto2/servicio"
if [ "$srv" != "$srv_principal" ]; then
  if [ -L "$srv/node_modules" ] && ! cmp -s "$srv/package-lock.json" "$srv_principal/package-lock.json"; then
    rm "$srv/node_modules"   # el encargo cambió las dependencias: el enlace ya no vale
  fi
  if [ ! -d "$srv/node_modules/@electric-sql/pglite" ] \
     && cmp -s "$srv/package-lock.json" "$srv_principal/package-lock.json" \
     && [ -d "$srv_principal/node_modules/@electric-sql/pglite" ]; then
    ln -sfn "$srv_principal/node_modules" "$srv/node_modules"
    echo "node_modules enlazado desde el repo principal" >&2
  fi
fi
if [ ! -d "$srv/node_modules/@electric-sql/pglite" ]; then
  if command -v npm >/dev/null 2>&1; then
    echo "instalando dependencias del servicio (npm ci)" >&2
    (cd "$srv" && npm ci --no-audit --no-fund) >&2
  else
    echo "aviso: sin npm; el juego usará SQLite y no ejecutará programas JS" >&2
  fi
fi

echo "importando recursos de $proyecto" >&2
"$G" --headless --path "$proyecto" --import >/dev/null 2>&1 \
  || echo "aviso: la importación terminó con error; se abre igualmente" >&2

exec "$G" --path "$proyecto" "$@"

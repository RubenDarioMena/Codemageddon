#!/bin/sh
# Crea un worktree aislado para un agente.
#   uso: sh tools/agentes/worktree.sh <codex|claude> <feature> [rama_base]
# El worktree queda FUERA del repo (carpeta hermana «Codemageddon-wt») para que Godot
# no escanee dos project.godot anidados. Imprime la ruta creada.
#
# Limpiar al terminar:  git worktree remove <ruta>,  rm -r <ruta>.codex  (registro de codex.sh)
# y, si ya se fusionó,  git branch -d <rama>
set -e

agente="$1"
feat="$2"
base="${3:-main}"

if [ -z "$agente" ] || [ -z "$feat" ]; then
  echo "uso: sh tools/agentes/worktree.sh <codex|claude> <feature> [rama_base]" >&2
  exit 1
fi
case "$agente" in
  codex|claude) ;;
  *) echo "agente debe ser «codex» o «claude»" >&2; exit 1 ;;
esac

raiz=$(git rev-parse --show-toplevel)
destino="$(dirname "$raiz")/$(basename "$raiz")-wt/$agente-$feat"
rama="agente/$agente/$feat"

git -C "$raiz" worktree add -b "$rama" "$destino" "$base" >&2
echo "$destino"

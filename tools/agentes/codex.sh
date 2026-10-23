#!/bin/sh
# Delega a Codex un encargo dentro de un worktree, sin interfaz (codex exec).
#   encargo nuevo:  sh tools/agentes/codex.sh nuevo  <worktree> <archivo_encargo>
#   corrección:     sh tools/agentes/codex.sh seguir <worktree> <archivo_encargo>
# «seguir» retoma el mismo hilo de Codex, que conserva el contexto del encargo anterior.
#
# El registro queda junto al worktree, en «<worktree>.codex/» (fuera de git):
#   hilo           thread_id de Codex
#   encargos.md    todos los encargos enviados, en orden
#   respuesta.md   último mensaje de Codex (también se imprime al terminar)
#   eventos.jsonl  traza completa;  errores.log  stderr de Codex
#
# Codex corre con sandbox workspace-write: escribe en el worktree pero no puede commitear,
# porque el índice vive en el .git del repo principal. Claude commitea después de revisar.
set -e

modo="$1"
wt="$2"
encargo="$3"

if [ -z "$modo" ] || [ -z "$wt" ] || [ -z "$encargo" ]; then
  echo "uso: sh tools/agentes/codex.sh <nuevo|seguir> <worktree> <archivo_encargo>" >&2
  exit 1
fi
[ -d "$wt" ] || { echo "no existe el worktree: $wt" >&2; exit 1; }
[ -f "$encargo" ] || { echo "no existe el encargo: $encargo" >&2; exit 1; }

reg="$wt.codex"
mkdir -p "$reg"
printf '\n## %s · %s\n\n' "$modo" "$(date '+%Y-%m-%d %H:%M')" >> "$reg/encargos.md"
cat "$encargo" >> "$reg/encargos.md"

estado=0
case "$modo" in
  nuevo)
    codex exec -C "$wt" -s workspace-write --json -o "$reg/respuesta.md" - \
      < "$encargo" > "$reg/eventos.jsonl" 2>> "$reg/errores.log" || estado=$?
    grep -o '"thread_id":"[^"]*"' "$reg/eventos.jsonl" | head -1 | cut -d'"' -f4 > "$reg/hilo"
    ;;
  seguir)
    [ -s "$reg/hilo" ] || { echo "no hay hilo previo en $reg/hilo" >&2; exit 1; }
    cd "$wt"
    codex exec resume -c 'sandbox_mode="workspace-write"' --json -o "$reg/respuesta.md" \
      "$(cat "$reg/hilo")" - < "$encargo" >> "$reg/eventos.jsonl" 2>> "$reg/errores.log" || estado=$?
    ;;
  *) echo "modo debe ser «nuevo» o «seguir»" >&2; exit 1 ;;
esac

echo "hilo: $(cat "$reg/hilo") · registro: $reg" >&2
if [ "$estado" -ne 0 ]; then
  echo "codex terminó con código $estado; últimas líneas de errores.log:" >&2
  tail -5 "$reg/errores.log" >&2
fi
[ -f "$reg/respuesta.md" ] && cat "$reg/respuesta.md" && echo
exit "$estado"

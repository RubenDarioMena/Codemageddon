#!/bin/sh
# Exporta la demo web a ../demo (raíz del repositorio): build de Godot + servicio web + PGlite.
# Uso: sh tools/exportar_web.sh   (desde Concepto2/, con las plantillas web de Godot 4.7.2 instaladas)
set -e
cd "$(dirname "$0")/.."
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
DEMO=../demo
rm -rf "$DEMO" && mkdir -p "$DEMO/servicio_web/pglite"
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . --export-release "Web" "$DEMO/index.html"
cp servicio/web/servicio_web.js "$DEMO/servicio_web/"
PG=servicio/node_modules/@electric-sql/pglite/dist
cp "$PG"/*.js "$PG"/pglite.wasm "$PG"/pglite.data "$PG"/initdb.wasm "$DEMO/servicio_web/pglite/"
cp tools/web/vercel.json "$DEMO/"
du -sh "$DEMO"

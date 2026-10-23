#!/bin/sh
# Exporta la demo web a ../demo (raíz del repositorio): build de Godot + servicio web + PGlite.
# Uso: sh tools/exportar_web.sh   (desde Concepto2/, con las plantillas web de Godot 4.7.2 instaladas)
# La demo es de pruebas: CMG_DEVTOOLS_WEB=0 permite exportarla sin laboratorio.
set -e
cd "$(dirname "$0")/.."
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
DEMO=../demo
REVISION=$(git rev-parse HEAD)
JUEGO="juego-$(git rev-parse --short=12 HEAD)"
CMG_DEVTOOLS_WEB="${CMG_DEVTOOLS_WEB:-1}"
case "$CMG_DEVTOOLS_WEB" in 0|1) ;; *) echo 'CMG_DEVTOOLS_WEB debe ser 0 o 1' >&2; exit 1 ;; esac
PG=servicio/node_modules/@electric-sql/pglite/dist
test -f "$PG/pglite.wasm" || { echo 'Ejecuta npm ci en Concepto2/servicio antes de exportar.' >&2; exit 1; }
rm -rf "$DEMO" && mkdir -p "$DEMO/servicio_web/pglite"
"$GODOT" --headless --path . --import > /tmp/codemageddon-export-import.log 2>&1
"$GODOT" --headless --path . --export-release "Web" "$DEMO/$JUEGO.html"
mv "$DEMO/$JUEGO.html" "$DEMO/index.html"
node tools/web/preparar_demo.mjs "$DEMO" "$REVISION" "$CMG_DEVTOOLS_WEB"
cp servicio/web/servicio_web.js "$DEMO/servicio_web/"
cp "$PG"/*.js "$PG"/pglite.wasm "$PG"/pglite.data "$PG"/initdb.wasm "$DEMO/servicio_web/pglite/"
cp tools/web/vercel.json "$DEMO/"
du -sh "$DEMO"

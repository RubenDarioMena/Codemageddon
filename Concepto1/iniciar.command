#!/bin/zsh
# Doble clic en Finder: levanta el servidor local y abre el concepto en el navegador.
cd "$(dirname "$0")"
( sleep 1 && open "http://localhost:8765" ) &
python3 tools/servidor.py 8765

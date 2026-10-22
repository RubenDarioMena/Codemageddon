"""Servidor local sin caché para el concepto (los módulos ES no funcionan con file://).

Uso: python3 tools/servidor.py [puerto]   → http://localhost:8765
"""
import http.server
import os
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


class SinCache(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=RAIZ, **kwargs)

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


if __name__ == "__main__":
    puerto = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    print(f"Codemageddon · Concepto 1 en http://localhost:{puerto}")
    http.server.ThreadingHTTPServer(("127.0.0.1", puerto), SinCache).serve_forever()

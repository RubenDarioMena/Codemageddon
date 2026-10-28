# Codemageddon · juego HTML

Primer juego hecho a partir de los prototipos HTML ([brief](../BRIEF_AGENTE.md)). Parte de una copia del banco 03 (lanzamisiles) y le pone una interfaz de juego que funciona en PC y en teléfono.

## Cómo abrirlo

Conviene servirlo por HTTP, como en producción:

```bash
python3 -m http.server 8765 --directory Concept-HTML/juego
```

- Juego: http://localhost:8765/
- Probador (teléfono y PC a la vez): http://localhost:8765/probar.html
- Forzar una forma: `?forma=movil` o `?forma=escritorio`.

En Claude Code está como `juego-html` en `.claude/launch.json`.

## Archivos

| Archivo | Qué hace |
| --- | --- |
| `index.html` | Estructura: zona del mapa (cabecera, escena con el inspector encima y mando), divisor y zona del código. |
| `css/base.css` | Colores, tipos y las piezas de metal (`.marco`, `.regla`, `.placa`). |
| `css/componentes.css` | Cada pieza: campo, inspector y signos vitales, paleta de iconos, editor, consola, pestañas, barra de símbolos. |
| `css/layout.css` | Reparto en PC (lado a lado) y en teléfono (arriba y abajo, teclado). |
| `js/iconos.js` | Iconos SVG de la paleta (`window.ICONOS`). |
| `js/juego.js` | Simulación, runtime del jugador, 3D y plano, inspector, editor. Viene del banco 03. |
| `js/layout.js` | Forma, divisor, teclado del teléfono, barra de símbolos y tooltips. Habla con el juego solo por `window.cmg`. |
| `probar.html` | Marcos de teléfono y de PC a escala, con teclado simulado. |

Al cambiar CSS o JS, sube el sello `?v=N` de `index.html` para que el navegador no use la copia vieja.

## Estilo

Minimalista con acentos metálicos. Lo que se lee (mapa, código, datos) va plano y limpio; el metal solo marca bordes, placas e iconos grabados. Los iconos están grabados en reposo y toman color al pasar el cursor. Una sola apariencia oscura.

## Pendiente

- Probar el teclado en un iPhone real.
- Cámara cenital con transición a 3D (brief §5).
- Extraer la simulación a TypeScript (brief §7).

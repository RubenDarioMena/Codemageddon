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

## Interacción del mapa y programas

- Clic izquierdo y arrastre: caja de selección. Shift conserva la selección previa.
- Rueda presionada: orbitar; botón derecho o dos dedos: desplazar; rueda o pellizco: zoom.
- Doble clic o doble toque: unidades del mismo tipo visibles en pantalla.
- En táctil, mantener 160 ms y arrastrar selecciona las unidades del recorrido. A los 480 ms se abre la ficha.
- El inspector móvil abre la ficha completa. La preferencia local `cmg-juego-inspector-movil` admite `"tira"` para recuperar el modo anterior; la pantalla Settings queda pendiente.
- Activa «Lugar manual» y haz doble clic/toque en el mapa para escribir sus coordenadas del suelo. «Insertar» las lleva al programa.
- La selección de lanzadores con programas distintos muestra un borrador vacío: Add lo anexa a cada programa y Replace los sustituye. Editar el borrador no modifica los programas hasta aplicar una acción.
- Replace pide confirmación; «No preguntar otra vez» persiste en este navegador. Una futura pantalla Settings puede reactivarla con `window.cmg.confirmarReplace = true`.
- En móvil, el editor ocupa el viewport visual disponible encima del teclado y de la barra de símbolos.

Pruebas de lógica sin dependencias:

```bash
node Concept-HTML/juego/pruebas/interaccion.cjs
node --check Concept-HTML/juego/js/juego.js
node --check Concept-HTML/juego/js/layout.js
```

La comprobación en navegador y en Samsung S24 Ultra con hyperMarker queda pendiente: las pruebas de lógica no validan eventos nativos, WebGL ni el teclado del dispositivo.

## Otros pendientes

- Probar el teclado en un iPhone real.
- Cámara cenital con transición a 3D (brief §5).
- Extraer la simulación a TypeScript (brief §7).


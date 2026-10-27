# Banco de mecánicas

Sandboxes HTML de un solo archivo que prueban **una** pregunta de diseño de la mecánica de código. No dependen de Godot. Cada uno se diseña antes con la skill `deep-game-systems` y se publica como Artifact para abrirlo en el móvil.

Convenciones:

- Simulación determinista por pasos fijos, separada del dibujo (Canvas 2D).
- El código del jugador corre en un Web Worker con la misma forma de API que Concepto2 (`await yo.verbo(...)` devuelve un texto).
- El reloj de juego se congela mientras el código del jugador piensa entre órdenes, así el mismo programa siempre da el mismo resultado.
- Cada ejecución reinicia el mundo y guarda un intento en la telemetría local (botón «Copiar telemetría» en la pestaña Registro).

| # | Archivo | Pregunta | Artifact |
| --- | --- | --- | --- |
| 01 | [01_recoger_entregar.html](01_recoger_entregar.html) | ¿El segundo argumento de `recoger` crea decisiones con sentido? | https://claude.ai/artifact/9eVKwT2yiN7Cxy2EQs2bcB |
| 02 | [02_tres_vistas.html](02_tres_vistas.html) | ¿El mismo programa se entiende en bloques, pseudocódigo y JS? ¿Un sensor vuelve necesarios `while` e `if`? | https://claude.ai/artifact/5VzufuABWh9zeWfE4fTqhG |

## 01 · Recoger y entregar

**Átomo:**
- `await yo.recoger(origen, material)`: R1 camina a 4 casillas/s y tarda 0,5 s. Devuelve `"ok"`, `"viaje_vacio"` o `"manos_llenas"`.
- `await yo.entregar(destino)`: devuelve `"ok"`, `"rechazado"`, `"derrame"` o `"manos_vacias"`.

**Conexiones:**
- Bodegas multimaterial → el segundo argumento elige el material.
- Máquinas que solo aceptan un material → `"rechazado"`, y R1 conserva la carga.
- Entrada con huecos limitados → `"derrame"`.
- Posición de R1 → el orden de los viajes cuesta tiempo.

**Cadena:** la máquina tarda 9 s → su entrada de 1 hueco se llena → el siguiente viaje derrama → el jugador tiene que intercalar viajes o esperar.

**Emergentes observados en las pruebas:**
- Reto 3: intercalar cobre y silicio resuelve los derrames sin `esperar`.
- Reto 4: si R1 vuelve de ENS, conviene ir a la bodega lejana. El *fallback* con `if (r === "viaje_vacio")` funciona, pero el viaje en vano cuesta tiempo y no entra en el límite.

**Retos y tiempos (simulados):**

| Reto | Solución ingenua | Solución buena |
| --- | --- | --- |
| 1 · Primer viaje | 2 líneas: falta cobre | `for`: 8,8 s |
| 2 · Dos materiales | `"rechazado"` → `"manos_llenas"` | dos bucles |
| 3 · Sin derrames | derrame a los 10,7 s | intercalar: 30,2 s, 0 derrames |
| 4 · Contra reloj (≤ 18 s) | 18,1 s, falla | cobre cercano primero: 16,4 s; silicio → ENT-2 → ENT-1: 15,7 s |

**Telemetría por intento:** reto, resultado, motivo, línea del error, tiempo de juego, líneas de código, derrames, verbos usados, resultados por tipo y el código.

**Pendiente:**
- Llevar la telemetría a una base compartida del Artifact para recogerla de varios testers.
- Validar con personas si el reto 4 se entiende sin la pista.

## 02 · Tres vistas y el sensor `cuantos`

**Arquitectura:** el programa es un árbol (`recoger`, `entregar`, `esperar`, `repetir`, `mientras`, `si`). Bloques y pseudocódigo son dos pieles del mismo editor. JavaScript se genera desde el árbol, y el texto se traduce de vuelta con acorn si usa solo ese subconjunto. Lo que no tiene bloque (variables, `log`, `&&`, `do…while`, funciones) se queda en texto, y el aviso dice la línea. La edición es de tocar y colocar, sin arrastrar. El pseudocódigo está en inglés por defecto, con opción en español.

**Átomo nuevo:** `await yo.cuantos(lugar, material)`: no gasta tiempo de juego. En una bodega devuelve las unidades que quedan; en una máquina, las que esperan en su entrada. No tiene error físico, pero si se llama 500 veces seguidas sin otra orden, el programa se detiene.

**Conexiones:**
- Bodegas → el sensor mide el contenido. Sirve aunque esté tapado.
- Máquinas → el mismo sensor mide la entrada, así que también resuelve el reto 3 sin `esperar` fijo.
- Errores físicos → `viaje_vacio` y `derrame` siguen siendo la consecuencia visible de no medir.

**Cadenas:**
- Reto 5: el camión trae una cantidad distinta en cada intento → `repeat N` se queda corto o hace un viaje vacío → hay que medir antes de cada vuelta.
- Reto 6: FUN tarda 6 s y tiene 1 hueco → entregar siempre ahí derrama → esperar no cabe en 24 s → si FUN está ocupada, se usa BOD.

**Emergentes previstos:**
- Reto 6: un plan fijo calculado a mano (FUN, FUN, BOD, FUN, BOD, FUN) también entra en el tiempo sin sensor.
- `while (cuantos(FUN) >= 1) wait 1` es correcto, pero tarda 24,1 s y no entra.

**Tiempos simulados:**

| Reto | Solución ingenua | Solución buena |
| --- | --- | --- |
| 5 · Hasta vaciar | `repeat 5`: falla con 7 (sobran 2) o con 3 (viaje vacío); `for 10`: viaje vacío | `while cobre in ENT-1 > 0`: 8,7 s con 3, 17,4 s con 6 |
| 6 · Plan B (≤ 24 s, FUN ≥ 3) | todo a FUN: derrame a 12,9 s; esperar a FUN: 24,1 s | `if cobre in FUN < 1` FUN, `else` BOD: 20,4 s (FUN 4, BOD 2) |

**Cambio de regla frente a 01:** el reto se cumple cuando el programa termina, no en el instante en que se completan las metas. Así un `for` demasiado largo sí hace su viaje vacío.

**Telemetría:** la misma que en 01, más el modo (bloques, pseudo o JS), el idioma, el número de bloques, los viajes vacíos y el contenido oculto de ese intento.

**Pendiente:**
- Variables y `log` en bloques. Necesitan un ladrillo de valor, por ejemplo «resultado de la última orden».
- `&&` y `||` en condiciones.
- Sangría francesa en las líneas largas del editor de texto.

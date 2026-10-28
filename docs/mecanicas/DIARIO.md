# Diario de mecánicas

Registro cronológico: cada entrada guarda el feedback tal como llegó, lo que se probó, lo que se decidió y por qué. Las entradas no se reescriben; si una idea cambia, se anota en una entrada nueva. La foto actual y completa está en [VISION.md](VISION.md).

Formato de cada entrada: **Feedback** (lo que pidió el usuario) · **Hecho** (qué cambió y dónde) · **Decisiones** (incluidos los desvíos y su motivo) · **Datos** (pruebas, calibración, telemetría) · **Abierto** (preguntas para la siguiente ronda) · **Para el juego final** (lo que no cabe en un HTML).

---

## 2026-10-27 · Bancos 01 y 02 (resumen retroactivo)

**Hecho.**
- [01 · Recoger y entregar](../../prototipos/mecanicas/01_recoger_entregar.html): dos verbos, `await yo.recoger(origen, material)` y `await yo.entregar(destino)`. El segundo argumento de `recoger` abre la decisión «qué material y de dónde». Errores físicos legibles: `viaje_vacio`, `rechazado`, `derrame`, `manos_vacias`.
- [02 · Tres vistas](../../prototipos/mecanicas/02_tres_vistas.html): el mismo programa como bloques, pseudocódigo y JavaScript (un árbol, tres pieles). Sensor `yo.cuantos(lugar, material)`, que no gasta tiempo. Retos 5 (camión con cantidad oculta → `while`) y 6 (plan B → `if/else`).

**Decisiones.**
- El reloj de juego se congela mientras el programa piensa: el mismo programa da siempre el mismo resultado.
- Un reto se cumple cuando el programa termina, no cuando se completan las metas, para que un `for` demasiado largo sí haga su viaje vacío.

**Datos.** Tiempos simulados en el [README del banco](../../prototipos/mecanicas/README.md).

---

## 2026-10-27 · Inspector, consola, métricas y el lanzamisiles (banco 03)

### Feedback

1. Si un ejercicio empieza con código ya puesto, que llegue **comentado**: el primer instinto es borrarlo cuando no encaja con lo que uno quiere hacer.
2. Para que el jugador escriba su propio código hacen falta **reglas visuales**. Gusta tener espacio para seleccionar máquinas y que muestren lo que se puede usar de ellas. Al seleccionar una máquina deberían verse, en colores y en orden, el nombre de la máquina, lo que contiene y sus propiedades y funciones. Eso va **separado de las estadísticas**, que miden la capacidad de la fábrica y pertenecen a un sistema de métricas.
   - Los productos terminados deberían llevar la estadística de cómo se hicieron: tiempo y recursos de cada máquina que aportó una parte.
   - Ese número se autogenera para tener un «número a optimizar», la misma dopamina de ver subir el número en un *cookie clicker*, pero dirigida a optimizar.
   - Optimizar debe reflejarse en el juego: más velocidad de investigación y más dinero, y también cosas difusas o menos deterministas: la preferencia del público por tu producto y la percepción que tienen de ti los gobiernos (el tuyo y el rival) y otras IA rivales, de tu nación o de la contraria (es decir, sus compañías).
   - Formato propuesto, en dos columnas. Columna 1, lo que se llama en el código: nombre de la máquina, lista de lo que contiene, funciones. Columna 2, información que también se puede leer en el código, pero sirve para decidir: entrada, salida, ratio, velocidad, probabilidad de fallo, sensores. Ejemplos: fundidora FUN-01 (cobre → placas, 2 placas por cobre, 1,5 s por ciclo) y lanzamisiles LAU-01 (`Autotarget(typeOfEnemy, sensor)`, `RegularShoot(place)`, `burstFire(place)` a 2,2 de cadencia con más fallo, `stopFire()`; fallo 2 % que sube a 15 % en ráfaga y sigue subiendo; sensores visual y térmico, independientes de la máquina, más uno de vibración de la red de defensa).
   - Ejemplo de uso: `if (failureRate >= 0.25) console.warn(failureRate); if (failureRate >= 0.35) stopFire();`.
   - Cada `console` se muestra como globo que sale de la máquina o como aviso grande a pantalla completa con referencia a la máquina; un hipervínculo centra la cámara en ella y la selecciona. La UI tendrá una opción para configurarlo por tipo de `console`.
   - Los valores llevan color según su tipo, y el jugador debe saber que con doble clic los referencia en su código. Una función se inserta con sus argumentos como comentarios de relleno: `Autotarget(//type Of Enemy, //type of sensor used); //position retrieved`.
3. Arrastrar y soltar en pseudocódigo y bloques.
4. Un editor dentro de los HTML de experimentación para escribir **tus propios enunciados** y pedir tus propias salidas.
5. Hacer el siguiente HTML con la mecánica del lanzador y enemigos para probarlo; quizá una cuadrícula más densa, o probar si conviene simular un entorno 3D. Si se puede, aplicar las mejoras de UI al banco 02.
6. Llevar dos documentos: este diario cronológico y un documento de especificación siempre completo ([VISION.md](VISION.md)).

### Hecho

**Banco 02** ([02_tres_vistas.html](../../prototipos/mecanicas/02_tres_vistas.html)):
- Inspector en dos columnas («Para tu código» y «Datos») con métricas aparte. Funciona para bodegas, máquinas y R1 (que ahora se puede tocar en el plano).
- Colores por tipo: variable, función, número, texto. Doble clic en JavaScript inserta en el cursor; las funciones llegan con huecos `/* material */` seleccionados y el siguiente doble clic en un valor los rellena. En bloques y pseudocódigo, el doble clic rellena el valor abierto o añade el bloque que corresponde (doble clic en `yo.entregar("FUN")` añade «entrega en FUN»). En escritorio los tokens también se arrastran al editor.
- Máquinas con salida y ratio: la fundidora hace 2 placas de cobre por cobre; la ensambladora, 1 oblea de silicio por silicio. **Ficha de producto**: la última pieza muestra cuánto tardó cada tramo (viaje de R1 → espera en la entrada → proceso) y el total. Métricas: productos, ciclos, ocupación, tiempo medio por pieza, derrames.
- **Número a optimizar**: récord de tiempo por reto, en las metas y en el aviso de victoria («nuevo récord» o «+1,7 s»).
- En JavaScript el programa de partida llega comentado, con una cabecera que explica cómo usarlo. Si se vuelve a bloques sin tocarlo, los bloques de partida siguen ahí. `Ctrl+/` y el botón «// comentar» comentan y descomentan.
- Arrastrar y soltar en bloques y pseudocódigo: ladrillos desde la paleta, bloques dentro y fuera de contenedores, y soltar sobre la paleta para borrar. En el móvil se mantiene pulsado 0,28 s.
- `console.log/info/warn/error` escriben en la consola y salen en un globo sobre R1.
- Pestaña **Reto**: «Tu reto» con título, enunciado, pista, metas (llegar a / vaciar), límites, mapa (copiado de cualquier reto y editable), bloques disponibles, y JSON para copiar y pegar.

**Banco 03, nuevo** ([03_lanzamisiles.html](../../prototipos/mecanicas/03_lanzamisiles.html)):
- Campo de 32 × 18 casillas con dos vistas intercambiables: **3D** (Three.js, órbita, zoom y desplazamiento) y **plano** 2D. Si el 3D no carga, queda el plano.
- Lanzamisiles con la API del ejemplo: `autoTarget(tipo, sensor)`, `regularShoot(lugar)`, `burstFire(lugar)`, `stopFire()` y las propiedades `failureRate`, `missiles`, `mode`, `jammed`, `fireRate`, `target`, `sensors`.
- Sensores: cámara y térmico montados; vibración `VIB_01` en la red. Enemigos: oruga (suelo), dron (2,5 m) y dron frío (invisible al térmico).
- Un programa y un Web Worker por lanzador, en *lockstep*: el tiempo solo avanza cuando todos están en `await esperar(...)`.
- Consola configurable por tipo: globo sobre la máquina, aviso a pantalla con enlace que centra la cámara, o solo consola.
- Inspector con el formato de dos columnas y métricas aparte; editor con resaltado en los mismos colores.
- **Número a optimizar**: ₵ por derribo (₵ 10 por misil y ₵ 40 por reparación), con récord y diferencia.
- Pestaña **Escenario**: escenario propio con enunciado, metas, defensa y oleadas; JSON para copiar y pegar.
- Cinco retos calibrados y telemetría local con vista usada, atascos detallados, usos de cada función, consolas e inserciones por doble clic, arrastre o atajo.

### Decisiones

- **Huecos con `/* … */`, no con `//`.** Un `//` dentro de una llamada comenta el resto de la línea y deja la llamada sin cerrar. Se inserta `autoTarget(/* tipo de enemigo */, /* sensor */) // → posición {x, y, z} o null`, el primer hueco queda seleccionado y el comentario de retorno solo se añade si no hay nada después en la línea. Si se ejecuta con un hueco sin rellenar, el 03 avisa con la línea.
- **Nombre en pantalla y en el código.** En pantalla `LAU-01`; en el código `LAU_01`, porque el guion no vale en un identificador de JavaScript. En el 02 los lugares siguen siendo textos (`"FUN"`), como en la API de Concepto2.
- **Lo propio sin prefijo.** En el programa de una máquina, lo suyo se escribe suelto, como en el ejemplo (`failureRate`, `stopFire()`); lo de otra máquina lleva su nombre (`LAU_02.jammed`). `yo.` también funciona. Las órdenes solo valen para la máquina dueña del programa: leer otras, sí; mandarlas, no. Eso mantiene el determinismo con varios programas a la vez.
- **Órdenes sin `await`, espera con `await`.** `autoTarget` y las propiedades leen una instantánea del mundo tomada al despertar; las órdenes no esperan respuesta y devuelven `"ok"`, `"sin_objetivo"`, `"sin_misiles"` o `"atascado"`. Solo `await esperar(s)` deja pasar tiempo. Así el ejemplo del usuario funciona tal cual dentro de un bucle.
- **`regularShoot(null)` no es un error**: devuelve `"sin_objetivo"` y deja de disparar. `regularShoot(autoTarget(...))` funciona sin `if` (al estilo de los errores físicos de 01).
- **`autoTarget` predice y `VIB_01.detect` no.** `autoTarget` elige al enemigo de ese tipo más cercano a la base, calcula dónde estará cuando llegue el próximo misil y descarta a los que ya tienen misiles suficientes en el aire. La vibración oye desde más lejos y a través de la niebla, pero da la posición de ahora: acierta a lo lento y falla a lo rápido.
- **El tipo de enemigo es obligatorio.** Sin un `"any"`, priorizar obliga a escribir `autoTarget("drone", …) ?? autoTarget("crawler", …)`, y `??` y `if/else` se vuelven necesarios.
- **Modelo de fallo, recalibrado.** Los números del ejemplo (2 % y 15 %) eran ilustrativos. Con ellos, una sola ráfaga de 3 s ya atascaba casi siempre. Valores actuales: base 2 %; al entrar en ráfaga sube a 4 % y luego 6 puntos por segundo; fuera de ráfaga baja 10 puntos por segundo, y 20 si está parado (así `stopFire` enfría el doble y la decisión «parar o seguir despacio» tiene sentido).
- **Fallo como riesgo acumulado.** Con una probabilidad independiente en cada disparo, la misma estrategia perdía en 2 de cada 8 semillas por atascos al 2 % en los primeros disparos. Ahora cada disparo suma su `failureRate` a un riesgo, y el lanzador se atasca al pasar un umbral aleatorio entre 0,75 y 1,25. La media es la misma (falla 1 de cada 1/failureRate disparos), pero sin rachas extremas.
- **La reparación tarda más si el fallo llegó con calor**: 1,5 s + 12 s × failureRate. Con reparación fija, la ráfaga sin control ganaba siempre, porque cada atasco la enfriaba a la fuerza. Con la reparación proporcional, mantener `failureRate` bajo es lo que gana.
- **El ejemplo del usuario es el programa de partida del reto 4.** Con esta calibración, avisar a 0,25 y parar a 0,35 llega tarde. El jugador tiene que ver los globos de `console.warn` y bajar el umbral.
- **Retos 4 y 5 admiten 1 brecha.** Aun con el riesgo acumulado, el momento de cada atasco cambia el resultado. Exigir 0 hacía que una buena estrategia perdiera casi la mitad de las veces.
- **3D y plano a la vez.** El 3D muestra la altura sin explicarla: una explosión en el suelo no alcanza a un dron a 2,5 m, y se ve. En el plano hay que codificarla: sombra desplazada, línea de altura y etiqueta «↑2.5» en miras y explosiones aéreas. Se dejan las dos vistas y la telemetría registra cuál se usó, para decidir con datos.
- **Semilla visible.** Cambia en cada intento salvo que se fije. Con la misma semilla, el mismo programa da el mismo resultado.

### Datos

Calibración del 03 con [pruebas/calibrar03.js](../../prototipos/mecanicas/pruebas/calibrar03.js) (10 semillas; el intento termina al pasar el máximo de brechas):

| Reto | Estrategia | Victorias |
| --- | --- | --- |
| 1 · Primer blanco | sin bucle (código de partida) | 0/1 |
| 1 | `while` + `esperar(0.5)` | 10/10 |
| 2 · Prioridades | orugas primero | 0/4 |
| 2 | drones primero (`??`) | 10/10 |
| 3 · Niebla | cámara para todo | 0/4 |
| 3 | cámara para los fríos + térmico, sin VIB | 0/4 |
| 3 | lo anterior + `VIB_01.detect("crawler")` | 10/10 |
| 4 · Enjambre | solo `regularShoot` | 0/4 |
| 4 | ráfaga siempre | 5/10 |
| 4 | código de partida (para a 0,35) | 5/10 |
| 4 | umbral 0,1 → regular, sin histéresis | 3/10 |
| 4 | histéresis: regular desde 0,1 hasta bajar a 0,04 | 8/10 |
| 5 · Dos lanzadores | regular ×2 | 0/4 |
| 5 | ráfaga siempre ×2 | 2/10 |
| 5 | histéresis ×2 | 7/10 |

Emergente encontrado: el umbral sin histéresis sale **peor** que la ráfaga sin control. Al quedarse rondando 0,1 nunca se enfría del todo. La variable de estado (`let enfriando`) aparece sola como la solución, y es un buen candidato a lección.

Pruebas de interfaz (Chromium sin ventana): doble clic e inserción con huecos, Ctrl+/, arrastre de ladrillos y bloques, borrado sobre la paleta, vuelta de JavaScript comentado a bloques, `console.warn`, «Tu reto» y «Tu escenario». Sin errores de consola. A 390 px de ancho, sin desbordes.

### Abierto

- ¿API en inglés (como el ejemplo: `autoTarget`, `failureRate`) o en español (como `yo.recoger`)? Hoy conviven.
- ¿Lo propio de una máquina sin prefijo, o siempre `yo.`? Sin prefijo se parece al ejemplo, pero enseña algo que en JS real necesita `this`.
- ¿El 3D aporta lo suficiente para el coste que tiene en móvil? Mirar en la telemetría el campo `vista` y los intentos hasta cumplir.
- ¿`failureRate` como probabilidad, o mostrar también el desgaste acumulado? Mostrarlo haría el fallo más predecible, quizá demasiado.
- En el 02 los nombres de lugar son textos (`"FUN"`); en el 03, variables (`LAU_01`). En el juego final convendría que cada máquina sea un objeto con nombre de variable (`FUN_01.espacio("cobre")`) además de su ID.
- ¿Hace falta un ladrillo de «valor de una propiedad» para que el inspector alimente también los bloques (por ejemplo, `failureRate` en una condición)?

### Para el juego final

- **Configuración de consola** global en Opciones (globo, pantalla o solo registro, por tipo) y bitácora revisable; encaja con la actividad 2.1 del [plan de Concepto 2](../plan/feedback-concepto2.md).
- **Fichas de producto en la base de datos**: una fila por pieza con cada tramo (máquina, espera, proceso, transporte), consultable con SQL. El número a optimizar sale de ahí.
- **Consecuencias de optimizar**: dinero e investigación (deterministas), y además preferencia del público, percepción del gobierno propio y del rival, y relación con IA o compañías rivales (difusas, con modelos como el logit de la ciudad). Requiere los sistemas de economía, ciudad y modo historia.
- **Defensa en el mundo**: los misiles salen de una cadena de producción y los robots reparadores son T1 o T2 con su propio programa, así que ráfaga y suministro dependen de la fábrica. Los sensores son edificios de una red con tabla `sensores` en la base.
- **Avisos con referencia**: cualquier mensaje de una máquina enlaza a ella y centra la cámara (ya prototipado en el 03).

## 2026-10-28 · El juego HTML: interfaz de juego, PC y teléfono

### Feedback

- Los prototipos HTML pasan a ser el primer juego (ver [Concept-HTML/BRIEF_AGENTE.md](../../Concept-HTML/BRIEF_AGENTE.md)). Prioridad: el diseño y que responda bien en cada plataforma.
- Prompt de imagen dado a GPT: interfaz más de juego que de página web; escenario y código como protagonistas; inspector que se despliega al **mantener presionada** una unidad; secciones divididas por un **borde metálico**; las palabras sobre el código reemplazadas por **iconos grabados en metal** que toman color al pasar el cursor, con el nombre en un cuadro rápido. Las imágenes de GPT no se podían aplicar tal cual.
- Respuestas del autor: minimalista con acentos metálicos; en PC, lado a lado y redimensionable, con el inspector muy visible, como widget sobre el mapa; partir de una copia del 03; se puede dejar de ser un solo HTML.

### Hecho

- `Concept-HTML/juego/`: copia del banco 03 separada en `index.html`, `css/` (base, componentes, layout) y `js/` (iconos, juego, layout). La simulación, los workers y los retos no cambian.
- Pantalla completa sin scroll de página. Marcos de acero de 3 px con tornillos de latón, reglas metálicas entre secciones, pestañas y títulos como placas grabadas. Una sola apariencia oscura.
- Inspector en tres estados (cerrado, tira, abierto) con signos vitales: cargador por celdas, medidor de `failureRate`, historia de 30 s y vida por celdas. Pulsación larga de 0,48 s con anillo.
- Paleta de 13 iconos SVG (redibujados de la hoja de GPT): grabados en reposo y de color al pasar el cursor, con tooltip de nombre y código. Se añadieron atajos para apuntar, disparo, ráfaga, detener y sensor.
- PC con divisor arrastrable; teléfono 50/50 con barra de símbolos sobre el teclado y el código que sube sin cambiar de tamaño (`visualViewport` + `interactive-widget=resizes-visual`).
- `probar.html`: teléfono y PC a la vez, a escala, con teclado simulado.

### Decisiones

- **Iconos vectoriales en vez de los PNG de GPT**: a 26–30 px los PNG se emborronan, y el grabado y el color al pasar el cursor se hacen con dos tintas en CSS. La hoja de GPT queda como referencia de forma y color.
- **Solo tema oscuro**: es un juego, y el metal grabado se lee mejor sobre grafito. Los bancos 01–03 conservan los dos temas.
- **Inspector como capa en el mapa**, no como columna: en PC ocupa la mitad derecha (las unidades propias están a la izquierda); en teléfono cubre el mapa, que es lo que el brief pide («arriba del mapa»). Queda para Opciones convertirlo en ventana flotante.
- **Tocar no abre la ficha**: tocar elige y muestra la tira; mantener presionado, o tocar la tira, la abre. Así el mapa sigue siendo jugable y la pulsación larga tiene un sentido propio.
- **Varios archivos sin herramienta de compilación**: scripts clásicos, con `window.cmg` como único puente entre `juego.js` y `layout.js`. Extraer el núcleo a TypeScript es la fase 2 del brief.
- **Desvío**: el brief pide cámara cenital por defecto con transición a 3D en Three.js. No se hizo en esta ronda; se mantienen el 3D y el plano en Canvas del 03.

### Datos

- Verificado en Chromium (panel del navegador) a 1366 × 768, 1440 × 860 y dentro del probador: iPhone 15 (393 × 852) con teclado simulado de 341 px. El código sube 387 px (teclado + barra) y queda entero encima. Sin errores de consola.
- No probado en un iPhone o un Android reales.

### Abierto

- Probar el teclado en un iPhone real: `visualViewport.offsetTop` cuando iOS desplaza la vista al enfocar.
- En el teléfono el campo de 32 × 18 queda con casillas de ~11 px: ¿zoom, cámara que siga la acción o mapas más pequeños?
- Con el teclado abierto no se ve el inspector; ¿hace falta un acceso rápido a las propiedades desde la barra de símbolos?

### Para el juego final

- Inspector como ventana flotante configurable en Opciones (PC).
- Cámara cenital ortográfica con transición a perspectiva (brief §5) en vez del plano en Canvas.
- Empaquetado con Capacitor y pruebas en dispositivos de gama media.

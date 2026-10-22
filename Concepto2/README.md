# Codemageddon · Concepto 2 (Godot 4.7)

Primer prototipo en Godot. Toma el feedback sobre el [Concepto 1](../Concepto1/README.md):

- Un mapa grande con la fábrica, una zona salvaje y la ciudad.
- Controles al estilo Age of Empires II.
- Construcción de máquinas y cintas.
- Materia prima que se compra y llega en camión.
- Robots por niveles.
- Máquinas que registran todo en una base de datos.
- Una ciudad que compra, se queja, protesta y audita.

![Inicio](docs/capturas/01_inicio.jpg)

## Abrirlo

Con Godot 4.7 en `/Applications`, abre la carpeta `Concepto2` como proyecto y pulsa ▶. O, desde la terminal:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path Concepto2
```

La partida empieza con la ayuda abierta (F1). Las capturas de esta página las genera el propio juego con un guion de pruebas (ver «Pruebas»).

## Decisiones de tecnología

| Tema | Hoy | Destino | Cómo se evita perder algo al migrar |
| --- | --- | --- | --- |
| Base de datos | SQLite ([godot-sqlite](https://github.com/2shady4u/godot-sqlite) v4.9, MIT, en `addons/`, para escritorio y web) | **PostgreSQL** | Todo el SQL del juego (esquema, ejemplos de la consola, auditoría de la ciudad) usa el subconjunto común de los dos motores. Sin `strftime` ni `AUTOINCREMENT`, y el tiempo se guarda como `t`, `dia` y `hora`. Las diferencias están aisladas en `scripts/db/base_datos.gd` y en el token `{ID}` de `datos/esquema.sql`. |
| Código del jugador | Las órdenes por clic se muestran como un programa **JavaScript** (`Robot.programa()`). | **JavaScript** ejecutado por el jugador | La API que se ve (`robots[1].recoger("REC-01", "cobre")`, `entregar`, `minar`, `buscarMena`…) es el contrato que deberá cumplir el runtime JS embebido. Las órdenes ya son datos serializables (GDD §10). |
| Renderizador | Compatibility (WebGL 2 / OpenGL) | Web + escritorio | El mismo que recomienda el GDD para Netlify y Steam. |

La base es **registro y proyección**: borrar o editar filas no crea ni destruye material.

## Cómo se juega (y qué enseña)

**El arranque.** Tienes un terreno, ₵ 1200, dos *mulas* T0 sin chip y una minilínea (REC-01 → FUN-01 → cinta → ENS-01 … DES-01). El cobre y el silicio se compran desde la barra superior y llegan en camión. Los circuitos se venden en el mercado de la ciudad, al otro lado del río.

**Robots por niveles = conceptos por niveles.**

| Nivel | Qué puede hacer | Concepto |
| --- | --- | --- |
| T0 Mula | Ejecuta **una vez** la lista de órdenes que le das con clics | Secuencia: tus clics ya son el programa (se ve en el panel) |
| T1 Operario (con chip) | `L` repite la lista en bucle | Bucles |
| T2 Explorador (sensores y pala) | `U` activa una rutina propia: busca menas, mina, y **comprueba si hay espacio** antes de entregar | Condiciones, funciones y sensores |

Comprar o extraer: el cobre comprado es caro pero inmediato. Las menas de la zona salvaje son gratis, pero exigen fabricar exploradores.

**Errores físicos legibles (GDD §5).**

- Recoger en un sitio vacío es un `viaje_vacio`.
- Entregar en una entrada llena hace que el material caiga al suelo (`derrame`, recuperable con clic derecho).
- Una máquina que no usa ese material lo rechaza (`rechazo`).
- Las mulas derraman; el explorador espera, porque tiene sensor.

**Datos y monitoreo.**

- Cada máquina tiene un ID estable y registra en `eventos` sus entradas, salidas, estados (`sin_insumo`, `salida_llena`…) y lo que pasa por las cintas.
- El HUD muestra poco a propósito. Escribes una consulta (F2) y la **fijas como panel**; así el jugador construye su propio tablero de monitoreo.
- Al seleccionar una máquina, el panel muestra sus últimos eventos *junto con la consulta SQL que los produce*.
- La capacidad del registro es limitada. Los servidores la amplían; si se llena, el juego borra los eventos más antiguos (retención) y avisa.
- Hay ejemplos de `GROUP BY`, `JOIN`, `CASE`, índices y retención manual.
- El archivo `partida.db` se puede abrir con DBeaver, DB Browser o `sqlite3` mientras juegas.

![Consola SQL](docs/capturas/04_consola.jpg)

**La ciudad (logit anidado, familia GEV).** Cada hora simulada, una muestra de vecinos de cada distrito elige entre `comprar · ignorar · {quejarse · protestar}`. Las dos últimas comparten un nido «político» (λ = 0,6). Las utilidades dependen de:

- el precio,
- la opinión sobre la empresa,
- el humo y el ruido de las máquinas (el ruido pesa ×2,5 de noche),
- el tráfico de camiones.

El jugador no ve las utilidades: ve la tabla `quejas` y tiene que **descubrir la causa con SQL** (p. ej., el Norte se queja de humo y el Centro de ruido nocturno). Las consecuencias:

- **Precio:** el precio del circuito sube o baja con la intención de compra.
- **Bloqueo:** si el Centro protesta, corta la carretera dos horas y los camiones esperan (ataque físico).
- **Sabotaje:** si el Norte protesta mucho, puede averiar una máquina, que se repara con un robot (clic derecho).
- **Ordenanza:** con muchas quejas de ruido nocturno, el ayuntamiento impone el **silencio nocturno** (ataque político). Desde ese momento, cada mañana a las 06:00 **ejecuta una consulta SQL sobre tu tabla `eventos`** y multa a las máquinas ruidosas que produjeron de noche. La consulta se muestra en pantalla. Se cumple poniendo esas máquinas en turno «diurno» (tecla T). Borrar los eventos también evitaría la multa: es una tentación deliberada para una futura mecánica de integridad de datos.

## Controles

| Ratón | |
| --- | --- |
| Clic izquierdo | Seleccionar. Arrastrar = caja; doble clic = todos los del mismo nivel en pantalla; Shift = añadir |
| Clic derecho | Orden según el objetivo: suelo = ir; máquina = recoger o entregar (según lleve carga); pila de REC-01 = el material de ese lado del andén; mena = minar; máquina averiada = reparar; material caído = recoger |
| Shift + clic derecho | Encolar (la lista es el programa del robot) |
| Rueda | Zoom en pasos enteros de píxel por metro, hacia el cursor |
| **Rueda pulsada** | **Orbitar** (giro libre que se ajusta a 45° al soltar, para que la luz dibujada de los sprites no quede en ángulos arbitrarios) |
| Minimapa | Clic o arrastre para mover la cámara |

| Teclado | |
| --- | --- |
| Flechas / WASD / bordes | Desplazar · Q/E girar 45° |
| B → Q W E / A S D | Construir: cinta, fundidora, ensambladora / fábrica de robots, despacho, servidor |
| R · Shift · clic derecho/Esc | Girar · colocar varias · cancelar |
| Supr · Ctrl+Z | Demoler (50 %) · deshacer la última obra si sigue en construcción (100 %) |
| Ctrl+1…9 · 1…9 | Crear grupo · seleccionarlo (dos veces = centrar) |
| . · H · Espacio | Robot ocioso · fábrica · centrar en la selección |
| L · X · U | Bucle · borrar órdenes · rutina automática (robots) |
| Z · T · V | Pausar máquina · turno diurno · enviar camión (despacho) |
| P · + / − | Pausa · velocidad (×1, ×2, ×4, ×8) |
| F1 · F2 | Ayuda · consola SQL |

Las **cintas** entregan material en la casilla de **entrada** de una máquina (lado cian) y reciben de su **salida** (lado ámbar). El fantasma de construcción muestra los dos puertos. El arrastre traza una L: el eje con más recorrido va primero.

![Órdenes encoladas](docs/capturas/10_orden_encolada.jpg)

## Estilo visual

Se mantiene la regla del Concepto 1: **lo vivo se dibuja, lo fabricado se modela, y el robot está entre ambos**.

- **Terreno:** un shader calcula cada píxel a 16 px/m a partir de un mapa lógico de 1 m. Las orillas son orgánicas gracias al ruido y al tramado Bayer, y las orugas desgastan el pasto y la fundidora lo seca.
- **Flora y menas:** sprites en un MultiMesh que miran a la cámara y quedan a la profundidad de su base.
- **Fábrica, camiones y ciudad:** modelos 3D. Las ventanas de la ciudad se encienden de noche.
- **Robots:** volumen 3D con la cara-pantalla en pixel art y su ID encima (`R1`).

| Explorador T2 | Noche |
| --- | --- |
| ![Explorador](docs/capturas/07_explorador.jpg) | ![Noche](docs/capturas/08_noche.jpg) |

Los modelos se generan con `tools/blender/modelos.py`, ya sea sin ventana o en tu sesión abierta de Blender (`vista_previa()` crea la escena «Codemageddon»):

```bash
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python tools/blender/modelos.py -- assets/modelos
```

## Arquitectura

```
scripts/config.gd          constantes de diseño y balance
scripts/sim/               simulación pura a 20 Hz (sin nodos): rejilla + A*, máquinas, cintas,
                           robots, camiones, ciudad (logit anidado)
scripts/db/base_datos.gd   adaptador SQLite → PostgreSQL: volcado por lotes, proyecciones, retención
datos/esquema.sql          esquema en el subconjunto común SQLite/PostgreSQL
scripts/mundo/pixel.gd     generadores de pixel art (portados del Concepto 1) y caras de robot
scripts/vista/             terreno, flora, ciudad, máquinas GLB, robots, cámara RTS
scripts/ui/                control AoE2, HUD con minimapa, consola SQL, estilo
scripts/principal.gd       bucle: pasos fijos con velocidad, interpolación, base de datos, auditorías
shaders/                   terreno, sprites, losa, cintas, edificios
tools/blender/modelos.py   familia paramétrica de modelos (10 GLB)
pruebas/                   pruebas sin ventana y guiones con capturas
```

La simulación publica tres colas (`registro`, `quejas`, `avisos`) que vacían la presentación y la base de datos. La auditoría de la ciudad es una consulta que la simulación pide y `principal.gd` ejecuta sobre la base real.

## Pruebas

```bash
cd Concepto2
G=/Applications/Godot.app/Contents/MacOS/Godot
$G --headless --path . -s pruebas/prueba_sim.gd       # línea inicial + consultas
$G --headless --path . -s pruebas/prueba_larga.gd     # 3 días: ventas, quejas, bloqueo, ordenanza, auditoría
$G --path . -- --guion=res://pruebas/guion_controles.gd   # 11 comprobaciones de controles por eventos reales
$G --path . -- --guion=res://pruebas/guion_capturas.gd    # capturas en pruebas/capturas/
```

Último resultado (22 de octubre de 2026):

- `guion_controles`: 0 fallos en 11 comprobaciones.
- `prueba_larga`:
  - 288 lingotes y 129 circuitos.
  - 12 ventas.
  - 2 bloqueos.
  - Ordenanza en vigor y 3 auditorías con multa.
  - 66 unidades minadas por el explorador.

## Límites conocidos

- **Sin runtime JavaScript:** el jugador todavía no escribe código. Ve el programa que generan sus clics y la rutina del T2. Es la prueba prioritaria del GDD (GodotJS/QuickJS o un intérprete propio con interrupción).
- **SQLite, no PostgreSQL:** falta la vía PGlite (web) y un PostgreSQL local (escritorio) detrás del mismo adaptador.
- **Balance sin ajustar:** precios, ruido, quejas y tiempos son de primera pasada. Las mulas derraman mucho si se usan en bucle hacia máquinas llenas (intencional, pero puede frustrar).
- **Movimiento:** solo hay órdenes por destino con A*. La variante «por pasos» del GDD queda pendiente.
- **Rotación y sprites:** con la cámara girada, el sombreado dibujado de los sprites no coincide con el sol. El ajuste a 45° lo limita.
- **Web:** no se probó la exportación web ni en Netlify, ni otro hardware que un Mac M1.
- **Datos:** el registro no tiene integridad (se pueden borrar eventos para esquivar la auditoría). Puede ser una mecánica futura: sellos encadenados, auditoría de huecos.

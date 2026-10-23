# Plan de trabajo: feedback sobre Concepto 2

Feedback del 22-oct-2026 sobre el prototipo `Concepto2/`, ordenado en 7 fases (0 a 6) y 17 actividades. Cada punto se contrastó con el código: el apartado «Hoy» de cada actividad dice cómo funciona ahora y dónde.

Dueños según [FLUJO.md](../colaboracion/FLUJO.md): **Codex** hace el núcleo (`sim/`, `db/`, `servicio/`, pruebas), **Claude** la presentación (`vista/`, `ui/`, shaders, modelos) y revisa e integra. Tamaños: S (una sesión), M (un par de sesiones), L (feature con ciclo adversarial).

## Resumen

| ID | Actividad | Dueño | Tamaño | Depende de |
| --- | --- | --- | --- | --- |
| **0.1** | Cola de comandos única (estaba aplazada) | Codex + Claude | L | Decisión D7 |
| **1.1** | Clic derecho arrastrado = desplazar cámara | Claude | S | — |
| **1.2** | Flechas de entrada (verde) y salida (roja) en las máquinas | Claude | S | D2 |
| **1.3** | Menú «Construir» visible, al centro, con modal por categorías | Claude | M | D1 |
| **1.4** | Miniaturas de los modelos para el menú | Claude | S | 1.3 |
| **1.5** | Gancho de desbloqueo por tecnología | Codex + Claude | S | 1.3 |
| **2.1** | Bitácora de avisos revisable | Codex (poco) + Claude | M | — |
| **2.2** | Multas y castigos notables | Claude | M | 2.1 |
| **2.3** | Visibilidad del log de eventos de máquina | Claude | S | D8 |
| **3.1** | Operario T1 como robot base: 3 al inicio, sin mulas | Codex + Claude | M | 0.1, D3 |
| **3.2** | Capacidades del siguiente nivel de robot | Usuario + Claude | — | — |
| **3.3** | Entregas por tiempo y luego con sensores | Codex + Claude | M | 3.1, 3.2, D5 |
| **4.1** | Cinta automática: arrastrar de salida a entrada | Codex + Claude | M | 1.2 |
| **4.2** | Construcción escalonada de la cinta (0,25 s por casilla): **ya existe**; revisar que se note | Claude | S | 4.1 |
| **5.1** | Diseño: SQL para leer, escribir y disparar eventos | Usuario + Claude | — | 0.1, 3.2, D6 |
| **5.2** | Implementación del SQL orientado a uso | Codex + Claude | L | 5.1 |
| **6.1** | Paredes laterales semitransparentes | Claude | S–M | baja prioridad |

## Avance

| Actividad | Estado | Dónde |
| --- | --- | --- |
| 1.1 Clic derecho arrastrado | Hecho | `main` (e15cf47) |
| 1.2 Flechas de puertos | Hecho. D2 asumida: siempre visibles, tenues si ya están conectadas | `main` (e15cf47) |
| 0.1 Cola de comandos | Hecho (Codex): aprobada con reservas tras 2 ciclos y un ajuste final; UI migrada | `main` (e15cf47) |

## Orden y paralelismo

Las fases 1 y 2 son casi todo presentación y no necesitan cambios en la simulación. Por eso **Codex puede trabajar en 0.1 (cola de comandos) mientras Claude hace la fase 1**, cada uno en su worktree. Las fases 3 y 5 cambian cómo entran órdenes a la simulación (bucle por defecto, niveles de robot, escribir en la base para actuar), así que conviene que lleguen con la cola ya hecha.

```
Claude:  1.1 → 1.2 → 1.3 → 1.4 ─────→ 2.2 → 2.3 ─────────→ 4.1 (asas y previa) → 6.1
Codex:   0.1 (cola de comandos) → 2.1 (origen en avisos) → 3.1 → 3.3 → 4.1 (ruta) → 5.2
Usuario: D1–D8 ─────────────→ 3.2 (matriz de robots) ──→ 5.1 (diseño SQL)
```

---

## Fase 0 · Base técnica

### 0.1 · Cola de comandos única

- **Hoy:** [CONTRATO.md](../colaboracion/CONTRATO.md#pendiente-cola-de-comandos-única-aplazado) la deja aplazada «hasta recibir otra ronda de feedback». Esta es esa ronda. Hay escrituras directas desde la UI (`m.pausada`, `r.repetir`, `r.ejecutando`…) y entradas asíncronas (programas JS, auditoría), así que no hay replays ni pruebas de determinismo.
- **Por qué ahora:** 3.1 cambia cómo se activa el bucle de los robots y 5.x quiere que el jugador actúe sobre el mundo escribiendo en la base. Las dos cosas necesitan un único punto de entrada a la simulación.
- **Propuesta:** comandos con número de paso, consumidos por `Simulacion` en un solo sitio. De paso, `mena(id)` público y la decisión sobre demoler cintas (deuda 2 y 4 del contrato).
- **Reparto:** Codex implementa la cola y una prueba de determinismo (dos corridas, mismo seed y mismos comandos ⇒ mismo estado). Claude cambia las escrituras de `ui/` y `principal.gd`. Ciclo adversarial.
- **Aceptación:** `prueba_sim`, `prueba_larga` y la nueva prueba de determinismo pasan; la sección «Deuda conocida» del contrato queda vacía o justificada.

## Fase 1 · Controles y construcción

### 1.1 · Clic derecho arrastrado = desplazar cámara

- **Hoy:** arrastrar con el clic derecho no hace nada. Pero la orden se da **al pulsar** (`scripts/ui/control_rts.gd:144`), así que hoy un arrastre ya habría mandado al robot al punto de partida. La rueda pulsada orbita.
- **Propuesta:** al pulsar solo se guarda la posición. Si el ratón se mueve más de 6 px es un arrastre: la cámara se desplaza «agarrando el suelo» (el punto bajo el cursor sigue al ratón). Si se suelta sin moverse, se da la orden como ahora. Shift + clic derecho sigue encolando. En modo construcción, el clic derecho sin arrastre sigue cancelando.
- **Aceptación:** `guion_controles.gd` (usa clic derecho en las líneas 86–87) se adapta y añade la comprobación «arrastrar con el derecho mueve la cámara y no da orden». Se actualiza la tabla de controles del README.

### 1.2 · Flechas de entrada y salida en las máquinas

- **Hoy:** las flechas solo existen en el fantasma de construcción, en cian (entrada) y ámbar (salida) (`control_rts.gd:494`). Las máquinas construidas no muestran sus puertos.
- **Propuesta:** en cada máquina, una flecha verde que parpadea en `celda_entrada()` apuntando hacia la máquina y una roja en `celda_salida()` apuntando hacia fuera. Se dibujan con un MultiMesh en `vista_fabrica.gd` y el fantasma usa los mismos colores. Recepción y servidor, según sus puertos reales.
- **Ojo:** el rojo ya significa «salida llena» y error. Por eso se propone que la flecha roja sea fija y solo la verde parpadee. Ver D2 (si están siempre visibles).
- **Aceptación:** captura nueva en `guion_capturas.gd` y el texto «lado cian/ámbar» del README actualizado. Es requisito de 4.1.

### 1.3 · Menú «Construir» visible

- **Hoy:** B convierte el panel de comandos en una rejilla de 6 botones con el mismo peso visual que el resto (`scripts/ui/hud.gd:567`). Dentro del menú, Q W E / A S D construyen y la cámara deja de girar con Q/E (`control_rts.gd:93`), pero nada en pantalla avisa de ese cambio de modo.
- **Propuesta:**
  - Un botón **Construir (B)** fijo, abajo al centro, que se ilumina al pulsar B.
  - Un modal centrado con pestañas por categoría: Transporte (cinta), Producción (fundidora, ensambladora), Logística (despacho), Robots (fábrica de robots), Datos (servidor).
  - Cada tarjeta muestra miniatura, nombre, costo y tecla. Las teclas solo valen con el modal abierto, y el modal hace evidente que Q/E ya no giran la cámara.
  - Ver D1: abrir manteniendo B o pulsándola.
- **Aceptación:** `guion_controles` (líneas 115 y 136) sigue pasando y hay comprobación de que con el modal cerrado Q/E giran la cámara.

### 1.4 · Miniaturas de los modelos

- **Propuesta:** render fuera de línea desde `tools/blender/modelos.py` (una cámara isométrica por modelo → PNG en `assets/miniaturas/`), con la misma paleta y cuantización que el resto. Es más barato y estable que un SubViewport en tiempo real.

### 1.5 · Gancho de desbloqueo por tecnología

- **Hoy:** no hay tecnologías: todo se puede construir desde el principio.
- **Propuesta (solo el gancho):** `requiere` en cada entrada de `Cfg.MAQUINAS` y un conjunto `sim.tecnologias`. Las tarjetas bloqueadas salen en gris con «Requiere: …». El árbol de tecnologías es un diseño aparte.
- **Reparto:** Codex añade el estado en la simulación y su entrada en el contrato; Claude, las tarjetas.

## Fase 2 · Avisos, castigos y registro

### 2.1 · Bitácora de avisos revisable

- **Hoy:** `hud.aviso()` muestra como mucho 6 líneas que se desvanecen a los 9 s (`hud.gd:355`, `hud.gd:402`). No hay historial. `sim.avisos` solo trae `{texto, tipo, t}`, sin la máquina ni el lugar.
- **Propuesta:**
  - Un panel **Avisos** (botón con contador de no leídos y una tecla) con todo el historial de la partida: día y hora, filtros por categoría (multa, derrame, ciudad, obra, programa) y clic para centrar la cámara en el origen.
  - Codex añade a `sim.aviso()` los campos `origen` (id), `celda` y `categoria`, y lo anota en el contrato. Si 0.1 ya está en marcha, va en el mismo encargo.

### 2.2 · Multas y castigos notables

- **Propuesta:**
  - **Multa, sabotaje, bloqueo, ordenanza:** banner grande al centro unos segundos, sonido, el dinero baja animado en rojo, «−₵ 120» flotando sobre cada máquina multada y una marca en el minimapa.
  - **Castigos que duran** (ordenanza, bloqueo): una etiqueta de estado en la barra superior, con tooltip y tiempo restante.
  - **Derrames:** la pila del suelo lleva un icono que parpadea y una marca en el minimapa hasta que se recoge.
  - Opcional: pausa automática en la primera multa.
- **Aceptación:** captura de una multa en `guion_capturas.gd` (la `prueba_larga` ya produce 3 auditorías con multa).

### 2.3 · Visibilidad del log de eventos de máquina

- **Hoy:** los últimos eventos de la máquina seleccionada salen en el panel inferior (206 px de alto), junto a la consulta SQL que los produce.
- **Propuesta:** un panel ampliable con letra más grande, color e icono por tipo de evento (entrada, salida, derrame, rechazo…) y filas nuevas resaltadas. En el mundo, rótulos breves sobre la máquina («+1 lingote»). Ver D8.

## Fase 3 · Robots y automatización

### 3.1 · Operario T1 como robot base

- **Hoy:**
  - La partida arranca con 2 mulas T0 y 1 Operario T1 (`scripts/sim/simulacion.gd:51–53`).
  - La fábrica de robots tiene receta de mula (`scripts/config.gd:52`).
  - El primer objetivo, el README y la tabla de niveles se apoyan en la mula.
- **Propuesta:**
  - Arrancar con **3 Operarios T1**.
  - Recolección → base repetible por defecto, como los aldeanos de AoE: clic derecho en una fuente y luego en el destino, y el robot repite el ciclo (L lo apaga). Ver D3.
  - Quitar la mula del arranque y de la fábrica.
- **Reparto:** Codex cambia `sim/`, `config.gd` y las pruebas. Claude cambia los comandos del HUD, los objetivos, las plantillas del editor y el README.

### 3.2 · Capacidades del siguiente nivel (decisión, no código)

- **Hoy en la API JS:**
  - Un T1 ya puede usar `db.query` y `maquinas[id].espacio()`. Esto último es de hecho un sensor y no pide nivel (`servicio/runtime_robot.mjs:128`).
  - Solo `buscarMena`, `buscarMaquina` y `minar` exigen T2 (`runtime_robot.mjs:91–104`).
- **Propuesta para discutir.** Sigue la progresión pedagógica tiempo → condiciones → datos:

  | Nivel | Puede | Enseña |
  | --- | --- | --- |
  | T1 Operario | secuencia, bucle, `esperar(s)` | secuencias, bucles, tiempo |
  | T2 Sensor | `espacio()`, `buscar*()`, esperar un evento | condiciones, eventos |
  | T3 Conectado | `db.query`, escribir en tablas de mando | datos, SQL dentro del código |

- Al decidirlo, Codex mueve los `requiereNivel` en `runtime_robot.mjs` **y** en `servicio/web/servicio_web.js` (la API debe ser idéntica).

### 3.3 · Entregas por tiempo y luego con sensores

- **Interpretación (ver D5):** dos lecciones encadenadas sobre la misma entrega.
  1. Con un T1, un programa que entrega cada N s (`esperar`). El jugador ve en SQL cuándo derrama o viaja vacío.
  2. Con un T2, la misma entrega guiada por sensor (espera a que haya espacio o salida), sin derrames.
- **Reparto:** Claude hace las plantillas del editor (`editor_programa.gd`) y los objetivos del HUD. Codex, lo que haga falta en la API (p. ej. `esperarEspacio()`) y su prueba.

## Fase 4 · Cintas automáticas

### 4.1 · Arrastrar de la salida a la entrada

- **Hoy:** la cinta se traza arrastrando en L desde una casilla (`control_rts.gd:560`) y no conoce los puertos.
- **Propuesta:**
  - En modo cinta, las flechas de 1.2 se convierten en asas.
  - Se arrastra desde una roja (salida) y se suelta en una verde (entrada). La simulación calcula la ruta sobre casillas libres (A*, pocas curvas) y la vista previa muestra recorrido y costo.
  - El trazado libre en L se mantiene.
- **Reparto:** Codex hace `sim.ruta_cinta(desde_id, hasta_id) -> tramo`, pura y determinista, con prueba. Claude, las asas y la vista previa.

### 4.2 · Construcción escalonada

- **Hoy:** ya está hecho en la simulación. `construir_cintas` da a la casilla k una obra de `Cfg.T_CONSTRUIR_CINTA * (k + 1)`, con `T_CONSTRUIR_CINTA = 0.25` (`scripts/sim/simulacion.gd:180`). La cinta en obra se pinta distinta en el shader.
- **Propuesta:** comprobar en partida que el avance casilla a casilla se nota. Si no se nota, reforzar la animación en la vista (Claude). El valor de 0,25 s se ajusta en `config.gd`.

## Fase 5 · SQL orientado a uso

### 5.1 · Diseño (decisión antes de código)

- **Hoy:** el camino principal de monitoreo es la consola F2 con «Fijar como panel» (`scripts/ui/consola_sql.gd:82`), y el objetivo 4 lo exige.
- **Restricciones que condicionan el diseño:**
  1. El principio «el mundo nunca se lee de la base» (registro y proyección). Escribir para actuar exige tablas de mando que la simulación consuma, es decir, 0.1.
  2. `CREATE TRIGGER` no está en el subconjunto común SQLite/PostgreSQL: PostgreSQL necesita una función PL/pgSQL y SQLite usa `BEGIN … END`. Hay que elegir entre disparadores del juego o renunciar al respaldo SQLite (D6).
- **Propuesta:**
  - **Escribir para actuar:** tablas de mando. `INSERT INTO pedidos (material, unidades) VALUES ('cobre', 10)` compra; `UPDATE maquinas SET turno = 'diurno' WHERE …` cambia turnos.
  - **Leer con propósito:** preguntas concretas en vez de tablero («¿por qué me multaron?», «¿quién derrama?»), con consultas rellenables para novatos.
  - **Disparadores del juego:** una regla es una consulta más una acción. Cuando `SELECT …` devuelve filas, el juego avisa, pausa o envía un camión. El juego evalúa las reglas cada N s y funcionan en los dos motores.
  - Los paneles fijados quedan como opción avanzada, no como objetivo obligatorio.

### 5.2 · Implementación

Se trocea tras 5.1. Codex hace las tablas de mando, el motor de reglas y las pruebas. Claude, el asistente de consultas y el editor de reglas. Toca el esquema SQL, así que va con ciclo adversarial.

## Fase 6 · Pulido visual (baja prioridad)

### 6.1 · Paredes laterales semitransparentes

- **Hoy:** no hay paredes ni nave. La fábrica es una losa abierta. Hay que decidir si habrá nave o si esto se aplica a las máquinas altas que tapan.
- **Propuesta:** un shader cuya opacidad depende del ángulo entre la normal de la pared y la cámara: semitransparente de lado y transparente al 100 % de frente.

---

## Decisiones abiertas

| ID | Pregunta | Afecta a |
| --- | --- | --- |
| D1 | ¿El menú se abre **manteniendo** B (y se cierra al soltar) o **pulsando** B? | 1.3 |
| D2 | ¿Flechas de puertos **siempre visibles** o solo con la máquina seleccionada, en modo construcción o al pasar el ratón? | 1.2 |
| D3 | ¿La mula **se elimina** o queda como robot barato para más adelante? ¿El bucle recolección → base va **activado por defecto** en T1? | 3.1 |
| D4 | Matriz de capacidades T1 / T2 / T3 (propuesta en 3.2). | 3.2, 3.3, 5.1 |
| D5 | «Entregas»: ¿se refiere a los **robots** (lecciones de programación) o a los **camiones** (compras y despacho programados)? | 3.3 |
| D6 | ¿Mantener el respaldo SQLite (disparadores del juego) o pasar a solo PostgreSQL (`TRIGGER` reales)? | 5.1 |
| D7 | ¿Se desbloquea ya la cola de comandos (0.1), aplazada en el contrato hasta esta ronda? | 0.1, 3.x, 5.x |
| D8 | Del log de eventos, ¿qué falla más: tamaño, ubicación, velocidad o que no se entiende qué significa cada fila? | 2.3 |

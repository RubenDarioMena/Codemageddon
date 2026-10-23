# Contrato núcleo ↔ presentación

Interfaz entre lo que posee Codex (simulación, base de datos, servicio JS) y lo que posee Claude (vista, UI, shaders). Es la única superficie que ambos pueden asumir estable.

> **Estado:** verificado contra el código el 2026-10-22 (`scripts/sim/*.gd`, `scripts/principal.gd`, `scripts/db/base_datos.gd` y los usos en `ui/` y `vista/`). Todas las rutas son relativas a `Concepto2/scripts/`. Lo que el código hace hoy y no cumple los principios está en la sección «Deuda conocida».

## Principios

1. La simulación (`Simulacion`, `RefCounted`) corre a **`Cfg.HZ` = 20 pasos por segundo**, con pasos fijos y sin nodos, y no conoce la presentación. `principal.gd` llama a `sim.paso()` (hasta 64 pasos por frame) y multiplica el reloj por la velocidad (`0, 1, 2, 4, 8`).
2. La presentación **lee** el estado y **actúa a través de los métodos públicos de `Simulacion`** (sección 3). No escribe campos directamente, salvo las excepciones de «Deuda conocida».
3. Mismo seed + mismas órdenes en el mismo paso ⇒ mismo estado. Los únicos RNG con seed son `Rejilla.new(7)` (terreno, menas y flora) y `Ciudad.rng` (seed 3; decisiones de vecinos y sabotaje). No se usa `randf()` global ni tiempo real dentro de `sim/`.
4. Un cambio en este archivo se hace en el mismo cambio que el código que lo requiere y se menciona en el resumen o la revisión.

Convenciones: una casilla equivale a 1 m. `Vector2i(x, z)` y `Vector2(x, z)` usan el componente `y` como eje Z del mundo. Rotación y dirección: `0 = +X, 1 = +Z, 2 = -X, 3 = -Z` (`Cfg.dir_vec(d)`).

## 1. Estado legible por la presentación

| Qué | Dónde | Campos que usa la presentación |
| --- | --- | --- |
| Reloj y economía | `sim` | `t` (s simulados), `hora()`, `dia()`, `dinero`, `hitos` (dict de logros), `pedidos` `[{material, unidades, espera}]`, `capacidad_registro()` |
| Terreno lógico | `sim.rejilla: Rejilla` | `ancho`, `alto`; `tipo` (`PackedByteArray`), `humedad`, `agua` (`PackedFloat32Array`, campo continuo para orillas), `fijo`, indexados con `idx(c)`; `ocupante` `{Vector2i: id_maquina}`; `flora` `[{pos: Vector2, clase, semilla, bloquea}]` con clase `pino`, `arbol`, `arbusto`, `pasto`, `flores` o `roca`; `menas` `[{id, celda, cantidad, max}]`; `puente_x`. Consultas: `dentro`, `libre`, `en_parcela`, `tipo_en`, `mena_en` |
| Máquinas | `sim.maquinas: {id: Maquina}` | `id` (`FUN-01`…), `tipo`, `def` (`Cfg.MAQUINAS[tipo]`), `celda` (esquina menor), `rot`, `tam`, `entrada`/`salida` `{material: unidades}`, `receta`, `progreso` (0–1), `trabajando`, `estado`, `obra` (s de construcción restantes), `turno_diurno`, `pausada`, `averiada`, `producidos`, `salida_cinta`, `envio_auto`. Métodos: `centro()`, `celdas()`, `rect()`, `lista()`, `celda_entrada()`, `celda_salida()`, `ruido()`, `humo()`. Además `sim.maquina_en(c)` |
| Estados de máquina | `Maquina.estado` | `construyendo`, `inactiva`, `trabajando`, `sin_insumo`, `salida_llena`, `pausada`, `turno`, `averiada` |
| Cintas | `sim.cintas.celdas: {Vector2i: {dir, items, obra, atasco}}` | `items` `[{mat, s, ps}]`, ordenados del más avanzado (`s≈1`) al menos avanzado. Posición: `Cintas.posicion(c, dir, s)` |
| Material en el suelo | `sim.suelo: {Vector2i: {mat, cant}}` | Pilas creadas por derrames y demoliciones |
| Robots | `sim.robots: Array[Robot]` (por id: `sim.robot(id)`) | `id`, `nivel` (0 = T0, 1 = T1, 2 = T2), `def` (`Cfg.ROBOTS[nivel]`), `pos`/`prev`, `rumbo`/`prev_rumbo` (radianes, 0 = mirando hacia +Z), `carga` + `cant`, `ordenes`, `pc`, `repetir`, `auto`, `estado`, `consola`, `ejecutando`, `linea`, `linea_error`. Métodos: `nombre()` (`R3`), `etiqueta()`, `cap()`, `ocioso()`, `programa()` → `[líneas, línea_activa]` |
| Estados de robot | `Robot.estado` | `ocioso`, `yendo`, `recogiendo`, `entregando`, `minando`, `reparando`, `esperando`, `sin_ruta`; en la rutina T2 también `buscando`, `sin_menas`, `sin_fundidora` |
| Camiones | `sim.camiones: Array[Dictionary]` | `{id: "CAM-n", tipo: "proveedor"|"venta", ruta: [Vector2], largo, s, ps, estado: "ida"|"descarga"|"vuelta", carga, timer, esperando}`. Posición: `Simulacion.punto_ruta(ruta, s)` → `[pos, dir]`. Punto del piquete: `sim.s_bloqueo()` |
| Ciudad | `sim.ciudad: Ciudad` | `distritos` `{nombre: {opinion, p: {comprar, ignorar, quejarse, protestar}, humo, ruido}}`, `precio`, `ordenanza`, `bloqueada()` |

**Interpolación.** `principal.gd` calcula `alfa = _acum / dt` y lo pasa a `vfab.actualizar(alfa, velocidad)` y `vrob.actualizar(alfa, velocidad)`. Cada paso guarda el valor anterior en estos campos:

| Valor anterior → actual | Entidad |
| --- | --- |
| `prev` → `pos`, `prev_rumbo` → `rumbo` | robot |
| `ps` → `s` | objeto en cinta (al pasar a la casilla siguiente arranca con `ps = -0.05`) |
| `ps` → `s` | camión |

Las máquinas y las pilas del suelo no se interpolan.

## 2. Colas de salida (simulación → presentación y base de datos)

La simulación **añade** y el consumidor **vacía** (`clear()`).

| Cola | Forma de cada elemento | Productor | Consumidor |
| --- | --- | --- | --- |
| `sim.registro` | `{t, dia, hora: int, origen, tipo, material, cantidad: int, detalle, monto}`; `material`, `detalle` y `monto` son `null` si no hay dato (no `""`) | `sim.log_evento(origen, tipo, material="", cantidad=0, detalle="", monto=null)` | `BaseDatos.volcar(sim)` cada 0,25 s → tabla `eventos` |
| `sim.quejas` | `{distrito, motivo, intensidad, t, dia, hora}`; `motivo` ∈ `humo`, `ruido`, `ruido_nocturno`, `trafico`; `intensidad` 1.0 = queja, 2.0 = protesta | `_paso_ciudad()` una vez por hora simulada | `BaseDatos.volcar(sim)` → tabla `quejas` |
| `sim.avisos` | `{texto, tipo, t}`; `tipo` ∈ `info`, `error`, `alerta`, `dinero` | `sim.aviso(texto, tipo="info", clave="")`; con `clave`, el mismo aviso sale como máximo cada 30 s simulados | `principal._process` → `hud.aviso()` |
| `sim.auditorias` | `{dia, sql}` | `_paso_ciudad()` a las 06:00 si hay ordenanza (`SQL_AUDITORIA`) | `principal._base_de_datos` → `db.consultar_luego(sql)` → `sim.resultado_auditoria(filas)` |
| `sim.resultados` | `{robot: int, ticket: int, resultado}` | `_terminar()` y `orden_programa()` | `principal._programas` → `servicio.enviar({op: "resultado", …, estado: sim.instantanea()})` |

Tipos de evento (`registro.tipo`) que emite hoy el código: `a_cinta`, `agotada`, `alta`, `auditoria`, `bloqueo`, `carga`, `compra`, `construccion`, `demolicion`, `derrame`, `deshacer`, `entrada`, `entrega`, `entrega_vacia`, `error_programa`, `estado`, `inicio`, `lista`, `log`, `manos_ocupadas`, `mina`, `multa`, `ordenanza`, `programa`, `rechazo`, `recibe`, `recoge`, `reparada`, `sabotaje`, `sale`, `salida`, `sin_objetivo`, `sin_ruta`, `venta`, `viaje_vacio`. Son vocabulario de las consultas SQL del jugador: renombrar uno rompe consultas y lecciones.

**Proyección** (no es cola). Cada segundo, `BaseDatos.proyectar(sim)` reescribe las tablas `maquinas` (`id, tipo, x, z, ruido, estado, turno, entrada, salida, producidos`) y `robots` (`id, nivel, modelo, estado, carga, cantidad, x, z, distancia`). El mundo nunca se lee de la base.

## 3. Órdenes (presentación → simulación)

Son **llamadas síncronas a métodos de `Simulacion`**, hechas entre pasos desde `ui/control_rts.gd`, `ui/hud.gd` y `principal.gd`. Convención: los métodos que devuelven `String` usan `""` para éxito y un mensaje legible para el jugador en caso de error.

| Método | Efecto |
| --- | --- |
| `validar(tipo, celda, rot) -> String`, `validar_cinta(c) -> String` | Solo consulta (vista previa de construcción) |
| `construir(tipo, celda, rot) -> String` | Cobra y crea la máquina en obra (`Cfg.T_CONSTRUIR`) |
| `construir_cintas(tramo: Array[[Vector2i, dir]]) -> String` | Las casillas que ya son cinta solo cambian de dirección, gratis |
| `demoler(id)` | 50 % de reembolso si ya estaba lista, 100 % si seguía en obra; derrama su contenido. La recepción no se puede demoler |
| `deshacer() -> String` | Ctrl+Z: deshace la última obra mientras siga en construcción |
| `comprar(material) -> String` | Pedido al proveedor (`Cfg.PEDIDOS`) |
| `enviar_camion() -> String` | Camión de venta con hasta 20 unidades del despacho |
| `ordenar(robots: Array, orden: Dictionary, encolar: bool)` | `orden = {tipo, …}`, con `tipo` ∈ `mover` (`celda`), `recoger` (`objetivo` = id de máquina o `"suelo"`, más `celda`, `material` y `punto` opcionales), `entregar` (`objetivo`), `minar` (`objetivo` = id de mena), `reparar` (`objetivo`), `esperar` (`seg`). `encolar` = Shift |
| `limpiar_ordenes(r)`, `set_repetir(r, v) -> String`, `set_auto(r, v)` | Bucle (requiere T1 o superior) y rutina autónoma (solo T2) |
| `orden_programa(r, datos, ticket)` | Orden de un programa JS: `datos = {tipo, x, z, objetivo, material, seg}`. Sustituye la lista del robot; el resultado vuelve por `sim.resultados` con el mismo `ticket` |
| `instantanea() -> Dictionary` | Foto para los programas: `{t, hora, dia, robots: {id: {nivel, x, z, carga, cantidad, capacidad, estado}}, maquinas: {id: {tipo, estado, x, z, entrada, salida, cap_entrada, acepta}}, menas: [{id, x, z, cantidad}]}` |
| `resultado_auditoria(filas)` | Aplica la multa de la auditoría nocturna |

Pausa y velocidad no son órdenes: viven en `principal.velocidad` y no tocan la simulación.

Valores de `resultado` que devuelve la simulación: `ok`, `viaje_vacio`, `derrame`, `rechazo`, `entrega_vacia`, `manos_ocupadas`, `agotada`, `sin_objetivo`, `sin_ruta`, `sin_pala`, `orden_desconocida`.

## Deuda conocida (no cumple los principios)

1. **Escrituras directas desde la presentación.** No pasan por métodos de `Simulacion`:
   - `ui/control_rts.gd:241,245`: `m.pausada` y `m.turno_diurno`.
   - `ui/hud.gd:628,636,645`: `m.receta`, `m.salida_cinta` y `m.envio_auto`.
   - `ui/editor_programa.gd:200,266`: `r.codigo` y `r.linea_error`.
   - `principal.gd` (`ejecutar_programa`, `detener_programa`, `_programas`): `r.ejecutando`, `r.ejecucion`, `r.linea`, `r.auto`, `r.repetir`, `r.ordenes.clear()` y `r.pc`.
   Afectan a la simulación, así que un replay no las vería.
2. **`ui/hud.gd:476` llama a `sim._mena(id)`**, que es privado. Hace falta un `mena(id)` público.
3. **Entradas asíncronas.** Las órdenes de programas JS (`orden_programa`) y el resultado de la auditoría (`resultado_auditoria`) llegan cuando responde el servicio o la base, así que el paso en que se aplican depende del frame. Con programas o auditorías activos, mismo seed + mismas acciones no garantiza el mismo estado.
4. `sim.quitar_cinta(c)` existe, pero ninguna parte de la UI la llama: las cintas terminadas no se pueden demoler.

## Pendiente: cola de comandos única (aplazado)

> **Estado: aplazado.** No se implementa hasta recibir otra ronda de feedback del usuario, que puede cambiar el alcance. No delegar a Codex mientras tanto.

- **Problema:** las entradas a la simulación llegan por caminos distintos. Unas son escrituras directas (deuda 1) y otras son asíncronas (deuda 3), así que hoy no se pueden hacer replays ni pruebas «golden» de determinismo.
- **Propuesta:** que todas las entradas pasen por un único punto de la simulación, como una cola de comandos con número de paso.
- **Reparto:** Codex implementaría la cola y las pruebas de determinismo en `sim/` y `pruebas/`. Claude cambiaría las escrituras directas de `ui/` y `principal.gd` por llamadas a esa cola. Por ser una feature que cruza núcleo y presentación, va con ciclo adversarial.
- **De paso:** añadir un `mena(id)` público (deuda 2) y decidir si se expone la demolición de cintas (deuda 4).

## 4. API de programas JavaScript

Idéntica en `servicio/runtime_robot.mjs` (escritorio) y `servicio/web/servicio_web.js` (web). Ejemplos: `yo.recoger("REC-01", "cobre")`, `maquinas["FUN-01"].espacio("cobre")`, `await db.query(...)`, `log()`. Cada `await` de una acción termina cuando la simulación devuelve su `resultado` (sección 3).

Protocolo servicio ↔ `principal.gd`:
- Del servicio llegan `{op: "accion" | "log" | "error" | "fin" | "aviso_db", robot, ejecucion, …}`. Los mensajes con un `ejecucion` antiguo se descartan.
- Hacia el servicio van `{op: "ejecutar" | "detener" | "estado" | "resultado", …}`.

Cambiar una versión obliga a cambiar la otra en el mismo cambio.

## 5. Configuración y balance

`scripts/config.gd` (`Cfg`) contiene las constantes de diseño y balance: `HZ`, `SEG_POR_HORA` (12,5 s; un día dura 5 min a ×1), `MAQUINAS`, `ROBOTS`, `PEDIDOS`, `DISTRITOS`, rutas de camión y tiempos. Lo leen ambos lados y cambiarlo es zona compartida. Los parámetros puramente visuales (paletas, densidad de flora, tramado) viven en la capa de vista, no en `config.gd`.

## Registro de cambios del contrato

| Fecha | Cambio | Autor |
| --- | --- | --- |
| 2026-10-22 | Borrador inicial desde el README | Claude |
| 2026-10-22 | Verificado contra el código: firmas reales, formas de colas y órdenes, deuda conocida | Claude |

# Prompt de revisión: fase 1 (controles) y cola de comandos

> Pégalo tal cual en una sesión nueva (Claude Code o Codex) abierta en la raíz del repo `Codemageddon`.

---

Revisa los cambios hechos el 22-oct-2026 en `main`. Están **sin push**: es el rango `2c79074..fcd9adc`.

Antes de empezar, lee:
- `CLAUDE.md` y `AGENTS.md`;
- `docs/colaboracion/FLUJO.md` (usa su «Plantilla de revisión»);
- `docs/colaboracion/CONTRATO.md`;
- `Concepto2/README.md`;
- `docs/plan/feedback-concepto2.md`, el plan del que salen estos cambios.

No modifiques nada: solo revisa e informa.

## Qué se pidió

El usuario dio feedback sobre el prototipo `Concepto2/` (Godot 4.7) y se convirtió en un plan de 17 actividades. Esta entrega cubre tres:

- **0.1 · Cola de comandos única** (implementada por Codex, revisada por Claude): toda mutación del mundo pasa por un único punto con diario, para poder hacer replays y pruebas de determinismo.
- **1.1 · Arrastrar con el clic derecho desplaza la cámara** (Claude), si arrastrar no hacía nada antes.
- **1.2 · Flechas en los puertos de las máquinas** (Claude): verde para la entrada (parpadea), roja para la salida en sentido contrario a la máquina.

## Commits

| Commit | Qué |
| --- | --- |
| `adc96e5` | 1.1 y 1.2 (Claude) |
| `a6fa8fe` | 0.1, cola de comandos (Codex, commiteado por Claude tras revisar) |
| `7e99c1b` | Fusión de la rama de Codex en la de Claude |
| `625026c` | La UI migra sus escrituras directas a la cola, y se adaptan los guiones de prueba |
| `e15cf47` | Fusión en `main` |
| `fcd9adc` | El plan de trabajo, `docs/plan/feedback-concepto2.md` |

En total: 13 archivos, +758 / −105. Para ver todo el diff:

```bash
git diff 2c79074..fcd9adc
```

## Qué cambió y dónde

Todas las rutas van bajo `Concepto2/`.

### 1.1 · Clic derecho

**`scripts/ui/control_rts.gd`**
- El clic derecho ya **no da la orden al pulsar**: la da **al soltar**, si el ratón no se movió más de 6 px.
  - Al pulsar solo se guarda la posición y el Shift (`:186`).
  - El movimiento y la suelta se siguen en `_input` (`:118`), antes que la GUI, para que el arrastre no se corte al pasar sobre el HUD.
  - `_fin_derecho` (`:141`) limpia el estado y restaura el cursor.
  - Si el botón se suelta fuera de la ventana, `_process` (`:110`) olvida el clic sin dar orden.
- En los modos de construcción (`colocar`, `cinta`, `menu`), soltar sin arrastrar cancela, como antes. Arrastrar desplaza sin cancelar.
- La orden usa la posición y el Shift **del momento de pulsar**.

**`scripts/vista/camara_rts.gd`**
- `arrastrar(desde, hasta)` (`:145`): el punto del suelo bajo `desde` queda bajo `hasta`. Con proyección ortográfica, la diferencia no depende de la posición de la cámara.
- `desplazando` (`:19`) desactiva el desplazamiento por los bordes de la pantalla mientras dura el arrastre (`:63`).

### 1.2 · Flechas de puertos

**`scripts/vista/vista_fabrica.gd`**
- `malla_flecha()` (`:233`): una flecha plana con borde negro. El color de la instancia del MultiMesh tiñe solo el relleno, porque sus vértices son blancos y los del borde negros.
- `puertos(m)` (`:254`):
  - hay **entrada** si la máquina tiene `cap_entrada`; la flecha va en la casilla exterior anterior a `celda_entrada()` y apunta a la máquina;
  - hay **salida** si tiene `cap_salida`; la flecha va en `celda_salida()` y apunta hacia fuera;
  - por eso la fábrica de robots y el despacho solo tienen entrada, el servidor no tiene ninguna y la recepción solo tiene salida.
- `_conectado` (`:279`): un puerto está conectado si hay una cinta en su casilla con el sentido correcto.
- `_escribir_flechas` (`:288`):
  - sin conectar: flota (vaivén en el sentido del flujo) y parpadea (alfa entre 0,35 y 1);
  - conectada: quieta con alfa 0,45.
- Se actualiza cada frame en `_actualizar_puertos` (`:264`).
- El material es *unshaded*, sin prueba de profundidad (`no_depth_test`) y sin descartar caras (`cull disabled`). `ESCALA_FLECHA = 1.2` (`:20`).

**Fantasma de construcción**
- `ControlRTS` asigna `vfab.fantasma`, una `Maquina` temporal, y sus flechas se dibujan en un MultiMesh aparte.
- Se eliminaron los antiguos conos cian/ámbar, que además mostraban una salida falsa en la fábrica de robots y el despacho.

### 0.1 · Cola de comandos (Codex)

**`scripts/sim/simulacion.gd`**
- `n_paso` y `diario` (`:11`, `:12`).
- `aplicar(cmd)` (`:43`) es la entrada única. Anota `{paso, cmd.duplicate(true)}` **también si el comando falla**.
- Los métodos públicos de siempre (`comprar`, `construir`, `construir_cintas`, `demoler`, `quitar_cinta`, `deshacer`, `enviar_camion`, `ordenar`, `limpiar_ordenes`, `set_repetir`, `set_auto`, `orden_programa`, `resultado_auditoria`) mantienen su firma, pero ahora envuelven a `aplicar`. Su lógica pasó a funciones `_privadas`.
- Comandos nuevos:
  - `set_maquina`, con lista blanca de campos: `pausada`, `turno_diurno`, `receta`, `salida_cinta`, `envio_auto`;
  - `iniciar_programa`, `detener_programa` y `fin_programa`;
  - `perdida_servicio`, que es global.
- `reproducir(diario, pasos)` (`:136`): crea una simulación nueva y la avanza consumiendo el diario con un índice.
- `huella()` (`:147`) es el MD5 de `huella_detalle()` (`:151`).
  - `huella_detalle()` es una lista explícita de campos del mundo: máquinas; robots, incluidos `timer`, `paso`, `meta`, `atasco`, `auto_obj` y `distancia`; cintas, suelo, camiones, pedidos, menas, ciudad con su RNG, `historial`, contadores y `_acum`.
  - Excluye la presentación (`consola`, `codigo`, `linea`, `linea_error`) y el terreno estático.
- `mena(id)` público (`:923`).
- El envío automático del despacho, dentro de `_paso_maquina`, llama a `_enviar_camion()` directamente y no pasa por el diario, porque se deriva del estado.

**`scripts/principal.gd`**
- El ciclo de vida de los programas JS usa los comandos nuevos (`:137`, `:150`, `:165`, `:198`, `:212`).
- La auditoría pasa por `resultado_auditoria`, que ahora envuelve a `aplicar`.

**`pruebas/prueba_determinismo.gd`** (nueva)
- 13 comandos repartidos entre los pasos 0 y 4500, incluido uno que falla a propósito, en una corrida de 6000 pasos.
- Comprueba:
  - 26 puntos de control comparando dos corridas;
  - el replay del diario;
  - el diario tras `var_to_str` → `str_to_var`;
  - que un comando alterado cambia la huella;
  - que una mena cambia la huella y la consola no.
- Termina con código 1 si algo falla.

**`docs/colaboracion/CONTRATO.md`**
- Sección 3 actualizada: «toda mutación del mundo pasa por `aplicar`; `log_evento` y `aviso` solo alimentan colas de salida».
- Se cierra la deuda de escrituras directas desde la UI y el apartado «Cola de comandos (hecho)».

### Migración de la UI (Claude, `625026c`)

- `scripts/ui/control_rts.gd:280,284` (teclas Z y T) y `scripts/ui/hud.gd:630,638,647` (receta, salida a cinta, envío automático) usan `sim.aplicar({"tipo": "set_maquina", …})`.
- `hud.gd:478` usa `sim.mena(id)`.

### Pruebas y documentación

- `pruebas/guion_controles.gd` pasa de 11 a 16 comprobaciones:
  - arrastre con el clic derecho;
  - cancelar al soltar;
  - número de flechas;
  - puertos conectados de la línea inicial;
  - flechas del fantasma;
  - Z pausa FUN-01 con un `set_maquina` en el diario.
- `pruebas/guion_programas.gd`: el clic derecho ahora se envía completo (pulsar y soltar), porque la orden se da al soltar.
- `README.md` (controles, puertos, pruebas) y la ayuda F1 (`hud.gd`).

## Decisiones tomadas sin confirmación explícita del usuario

Comprueba si son razonables.

1. **Flechas siempre visibles, y tenues y quietas cuando ya hay una cinta conectada.** El usuario no eligió (decisión D2 del plan).
2. **La flecha roja también parpadea**, siguiendo la petición literal. El rojo ya significa «salida llena» y error en otros sitios.
3. **La orden del clic derecho se da al soltar**, no al pulsar como en AoE2. Se nota como una latencia mínima.
4. **Propiedad de carpetas:** Claude editó `pruebas/guion_controles.gd` y `pruebas/guion_programas.gd`, que según `FLUJO.md` son de Codex.
5. **La rama de Codex se aprobó «con reservas»:** 2 ciclos más un ajuste final, fuera del máximo de ciclos, para corregir campos de la huella y el estilo.

## Qué se verificó

Todo se corrió fuera del sandbox, en macOS con Godot 4.7.2.

| Prueba | Resultado |
| --- | --- |
| `prueba_sim`, `prueba_larga` | Salida idéntica a la línea base previa al cambio (diff sin tiempos). Cifras clave: FUN-01 prod=296, ENS-01 prod=132, 12 ventas por ₵ 3089, 66 eventos `mina` |
| `prueba_determinismo` | 0 fallos. Con un fallo inyectado sale con código 1 |
| `guion_controles` | 16 de 16 |
| `guion_programas` (JS + PostgreSQL/PGlite) | 10 de 10 |
| `guion_capturas` | 8 capturas, revisadas a ojo |

Comandos:

```bash
cd Concepto2
G=${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}
$G --headless --path . -s pruebas/prueba_sim.gd
$G --headless --path . -s pruebas/prueba_larga.gd
$G --headless --path . -s pruebas/prueba_determinismo.gd
$G --path . -- --guion=res://pruebas/guion_controles.gd
$G --path . -- --guion=res://pruebas/guion_programas.gd
$G --path . -- --guion=res://pruebas/guion_capturas.gd
```

## Qué NO se verificó

- **Demo web:** export con `tools/exportar_web.sh` y prueba en Chromium. `principal.gd` cambió y lo usan las dos plataformas.
- **Partida manual:** la sensación del arrastre; el clic derecho en trackpad (dos dedos o Ctrl+clic en macOS); la legibilidad de las flechas en todos los niveles de zoom y con la cámara orbitada.
- **Rendimiento:** con muchas máquinas, `_actualizar_puertos` recrea arrays cada frame, y el `diario` crece sin límite durante la partida.
- **Construcción escalonada de cintas (4.2):** ya existía en la simulación; falta comprobar en partida que se nota.

## Qué mirar con lupa

1. **`control_rts.gd`: estado del clic derecho.**
   - `_input` marca como manejados los movimientos mientras se arrastra. ¿Afecta a `CamaraRTS._raton_dentro` o al hover de la GUI?
   - ¿Hay forma de que se quede pegado un `_presion_der`: foco perdido, pulsar el derecho con el izquierdo ya arrastrando, o Esc durante el arrastre?
2. **Orden al soltar:** se usa la posición del momento de pulsar. ¿Algo en `_orden` depende de que la cámara no se haya movido entre pulsar y soltar?
3. **Flechas:**
   - `no_depth_test` las dibuja sobre robots y máquinas;
   - `mm.instance_count` crece y nunca encoge;
   - ¿es correcta la posición en máquinas de lado par (fábrica de robots 4×4, recepción 4×3) y con las cuatro rotaciones?
4. **`aplicar`:**
   - ¿queda algún camino que mute el mundo sin pasar por él (`grep` de escrituras desde `ui/`, `vista/` y `principal.gd`)?
   - `iniciar_programa` escribe `linea` y `linea_error` (presentación) dentro de un comando de la simulación;
   - `perdida_servicio` no limpia `ordenes` ni `pc`. Es el mismo comportamiento de antes, pero ¿es el correcto?
5. **`reproducir`:** supone el diario ordenado por paso. Los comandos con `paso == pasos` no se aplican.
6. **`huella_detalle`:**
   - ¿falta algún campo con efecto físico? Por ejemplo `_hora_previa`, `_estado_previo` o `hitos`;
   - depende del orden de inserción de los diccionarios dentro de `var_to_str`.
7. **Contrato:** que `CONTRATO.md` describa exactamente lo que hace el código (sección 3 y «Deuda conocida»).
8. **Plan:** que las afirmaciones del apartado «Hoy» de `docs/plan/feedback-concepto2.md` sigan siendo ciertas. Por ejemplo: «un T1 ya puede usar `db.query` y `espacio()`».

## Problemas conocidos que no se tocaron

- **README desactualizado:** dice «288 lingotes y 129 circuitos» para `prueba_larga`, pero hoy se mide FUN-01 = 296 y ENS-01 = 132. La diferencia ya existía antes de este cambio.
- **Commit sin atribución:** el commit de fusión `7e99c1b` no lleva la línea `Co-Authored-By`.

## Formato de la respuesta

Usa la «Plantilla de revisión» de `FLUJO.md`:
- compuertas con ✅ / ❌;
- hallazgos numerados con severidad (`bloqueante` / `importante` / `menor`), `archivo:línea` y cómo reproducirlo;
- estado del contrato;
- determinismo;
- veredicto.

Separa los hallazgos de código de las dudas de diseño que deba decidir el usuario.

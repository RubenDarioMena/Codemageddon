# Devtools: herramientas para ajustar la jugabilidad

> Implementación inicial (23-oct-2026): panel F12, comandos granulares, escenarios, pausas, ajustes y ranuras. La referencia de lo disponible es [DEVTOOLS.md](../../Concepto2/docs/DEVTOOLS.md). El catálogo siguiente conserva propuestas futuras; bots, barridos, superposiciones y comparación automática todavía no están implementados.

Propuesta del 23-oct-2026 para `Concepto2/`. Va desde lo obvio (reiniciar, pausar, crear unidades) hasta herramientas para experimentar con el balance y el ritmo hasta que el juego divierta. Todo lo que dice «Hoy» se contrastó con el código.

Dueños según [FLUJO.md](../colaboracion/FLUJO.md): **Codex** hace el núcleo (`sim/`, `db/`, pruebas y herramientas sin ventana) y **Claude** la presentación (paneles, superposiciones, gráficas) y la integración en `principal.gd`. Tamaños: S (una sesión), M (un par de sesiones), L (feature con ciclo adversarial).

## La idea central: acortar el ciclo de ajuste

Ajustar la jugabilidad es repetir un ciclo de cinco etapas. Cada devtool sirve para acortar una de ellas:

| Etapa | Hoy | Con devtools |
| --- | --- | --- |
| **Cambiar** algo | Editar `config.gd` o el código y relanzar | Una perilla en vivo (segundos), un perfil o una variante |
| **Llegar** a la situación que quieres probar | Jugar 10 minutos hasta la noche del día 2 | Cargar una ranura, un escenario o «avanzar hasta las 21:55» |
| **Observar** qué pasa | HUD y SQL a mano. La ciudad es una caja negra incluso para ti | Inspector del estado oculto, superposiciones en el mapa y gráficas |
| **Juzgar** si mejoró | Sensación | Métricas de ritmo, bots que juegan sin ventana y comparaciones A/B |
| **Registrar** lo aprendido | Memoria | Grabadora de sesiones con notas y perfiles guardados |

La que más tiempo cuesta hoy es **llegar**. Cada cambio en el código obliga a volver a jugar hasta el momento interesante. Por eso las ranuras y los escenarios van en la primera fase, antes que las perillas.

## Lo que ya juega a favor

La cola de comandos (fase 0.1 del [plan anterior](feedback-concepto2.md)) dejó una base excelente para devtools:

- **Una sola puerta.** Toda mutación pasa por `Simulacion.aplicar(cmd)`, que lo anota en `diario` con su paso.
- **Replay exacto.** `Simulacion.reproducir(diario, pasos)` reconstruye el mundo desde cero, y `huella()` comprueba que coincide.
- **Velocidad sin ventana (medida hoy).** `prueba_larga` simula 3 días con 9 robots y SQLite en 3,3 s, o sea **≈ 1 s por día simulado**. Un día dura 5 min a ×1. Con eso:
  - Restaurar una partida del día 3 por replay tarda unos 3 s.
  - 100 partidas de 3 días tardan unos 5 min en un núcleo, y se pueden lanzar varios procesos a la vez.
- **Ganchos ya hechos.** `--guion=` carga un script con acceso a `principal`.
- **La base de datos lo registra todo.** Las métricas de desarrollo se pueden consultar con el mismo SQL que el jugador, y en escritorio también desde DBeaver (`127.0.0.1:5433`).

## Lo que lo complica

1. **`Cfg` es constante.** En Godot 4 un `const` de tipo diccionario es de solo lectura, así que `Cfg.MAQUINAS`, `Cfg.ROBOTS`… no se pueden cambiar en partida. `Maquina` y `Robot` toman su `def` directamente de `Cfg` (`maquina.gd:29`, `robot.gd:39`).
2. **Hay números de balance escritos en el código, no en `config.gd`:**
   - En `ciudad.gd`, unos 25:
     - las utilidades (0,6 · 1,2 · −0,04 · −1,6 · 3,0 · −3,2 · 3,5 · −1,5);
     - la exposición (0,35 · 0,12 · ×2,5 de noche · 0,3);
     - la dinámica de opinión (0,05 · 0,45 · 0,08) y la fórmula del precio (0,7 + 0,6·p);
     - los umbrales de bloqueo (0,2), sabotaje (0,25 y 50 %) y ordenanza (12 quejas);
     - las duraciones (2 h de bloqueo, 8 h de enfriamiento);
     - `LAMBDA` y `MUESTRA`.
   - En `simulacion.gd`: la multa (₵ 40 por máquina), el cupo del camión (20), el envío automático (≥ 10), la descarga (3 s), la reparación (3 s) y la repetición de avisos (30 s).

   Justo los números que deciden si la ciudad se siente justa o arbitraria.
3. **El comportamiento es código.** No todo es un número: «la mula derrama, el explorador espera» es una regla escrita a mano.
4. **Las semillas son fijas** (`Rejilla.new(7)`, `Ciudad` con 3). Todas las partidas de prueba son la misma partida, así que no se mide la varianza.

## Tres niveles de «ajustable»

Como la jugabilidad es sobre todo código, no basta con sacar números. Cada tipo de cambio tiene su herramienta:

| Qué cambias | Ejemplo | Herramienta | Ciclo |
| --- | --- | --- | --- |
| Un **número** | Velocidad del robot, umbral de la ordenanza | Perilla en vivo (C1–C3) | Segundos |
| Una **regla con estructura** | Recetas, catálogo de máquinas, eventos de la ciudad | Tablas de datos en el perfil (C3) | Segundos |
| Un **comportamiento** | Qué hace una mula al llegar a una máquina llena | Variante con interruptor (C4) y relanzar en el escenario (L3, L5) | ~10 s |

Para el tercer nivel no hay atajo mágico. El objetivo es que editar, relanzar y volver a estar en la situación exacta tome diez segundos y no diez minutos.

## Principios

1. **Todo truco y todo ajuste es un comando.** `{"tipo": "dev_dinero", …}` y `{"tipo": "ajuste", "clave", "valor"}` pasan por `aplicar` y quedan en el diario. Así el replay es fiel aunque hayas hecho trampas o movido perillas a mitad de partida. Nunca se escribe un campo directamente.
2. **Los ajustes van en cada `Simulacion` (`sim.aj`), no en una variable global.** Dos simulaciones con perillas distintas conviven en el mismo proceso, y eso permite hacer A/B y barridos.
3. **Partida marcada.** `sim.trampas` cuenta los comandos `dev_*`. Las métricas y los informes dicen si una partida es limpia.
4. **Solo en modo desarrollo:** `OS.is_debug_build()` (editor y exportaciones de depuración) o `--dev`. La demo web se exporta con `--export-release`, así que hoy no las tendría (ver DV2).
5. **Mismo vocabulario que el jugador.** Las métricas van a tablas `dev_*` de la misma base: el diseñador también usa SQL.

---

## Catálogo

### L · Llegar: tiempo, estado y trucos

**L1 · Consola de desarrollo** (tecla `º`, la de la izquierda del 1 en un teclado español, o F12; ver DV4). Es la herramienta más barata con más alcance: cada truco nuevo es una línea. Autocompleta, guarda historial y muestra ayuda con `?`.

| Ejemplo | Efecto |
| --- | --- |
| `dinero 5000` · `dinero +500` | Fija o suma presupuesto |
| `robot 2` · `robot 1 x3` | Crea un explorador (o tres operarios) bajo el cursor |
| `material cobre 20` | Pila de cobre bajo el cursor. Con una máquina seleccionada, llena su entrada |
| `obras` | Termina todas las construcciones en curso |
| `ir R3` | Teletransporta el robot al cursor |
| `evento bloqueo` · `evento sabotaje` · `evento ordenanza` · `auditar` | Fuerza un evento de la ciudad o la auditoría ahora |
| `opinion Norte 0.2` · `ciudad off` | Fija la opinión de un distrito · congela la ciudad |
| `gratis on` | Construir no cuesta |
| `ajuste ciudad.umbral_ordenanza 25` | Cambia una perilla (C1) |
| `avanzar 21:55` · `avanzar 1d` · `avanzar evento` | Avance rápido sin dibujar (L2) |
| `guardar a` · `cargar a` · `atras 30` | Ranuras y rebobinado (L3) |

**L2 · Control del tiempo.** Ya existen la pausa y ×1–×8.
- **Paso a paso** con la partida en pausa: un paso (1/20 s), 1 s o 1 h simulada.
- **Velocidades ×16 y ×32:** a 60 fps caben de sobra en el tope de 64 pasos por frame de `principal.gd`.
- **«Avanzar hasta»** una hora, un día o el siguiente evento de la ciudad. Simula sin dibujar (≈ 1 s por día) y vuelve a la vista. Se simula de verdad y no se cambia `t` a mano, porque saltar el reloj desincronizaría `_paso_ciudad` y `_acum`.

**L3 · Ranuras, reinicio y rebobinado.**
- **Qué es una ranura:** el diario hasta `n_paso`, más el perfil de ajustes.
- **Restaurar:** `reproducir`, cambiar `sim`, reconstruir las vistas (ya se construyen desde `sim`), vaciar la base y volcar el `registro` reproducido. Además:
  - se descartan los `avisos` acumulados;
  - se detienen los programas JS, porque el estado de un worker no se puede reconstruir;
  - se conserva el `codigo` de cada robot, que está fuera del diario.
- **Reiniciar** es cargar la ranura vacía. **«Atrás 30 s»** reproduce hasta `n_paso − 600`.
- Las ranuras se guardan en disco (`user://ranuras/`).

**L4 · Trucos de mundo.** Los de la tabla de L1, como comandos `dev_*`, más:
- reparar todo y averiar una máquina;
- vaciar o llenar los búferes de una máquina;
- desbloquear todo (cuando exista 1.5, el gancho de tecnologías);
- mostrar los IDs de todo.

**L5 · Escenarios.** Puntos de partida con nombre, para aislar una mecánica como en un nivel de pruebas: `fabrica_media_dia2`, `justo_antes_ordenanza`, `explorador_con_menas`, `laboratorio` (dinero infinito, todo desbloqueado). Se lanzan con `--escenario=nombre`. Hay dos formas:
- **Guion de comandos de alto nivel** («construir fundidora en (26,44)»). Sobrevive mejor a los cambios de código.
- **Diario grabado.** Es exacto, pero se desvía en cuanto cambia el código.

### C · Cambiar: perillas

**C1 · Registro de perillas (`Ajustes`).**
- Cada perilla tiene: clave (`ciudad.umbral_ordenanza`), valor por defecto (sale de `Cfg`), mínimo, máximo, paso, unidad, grupo, una frase que explique qué hace y si aplica **en vivo** o tras **reinicio** (el tamaño del mapa, por ejemplo).
- Al crearse, `Simulacion` copia las tablas de `Cfg` (`MAQUINAS`, `ROBOTS`, `PEDIDOS`, `DISTRITOS` y los escalares). `Maquina.def` y `Robot.def` salen de esa copia.
- Los números de `ciudad.gd` y `simulacion.gd` de la lista de arriba pasan al registro.
- La presentación lee los costos de `sim.aj` y no de `Cfg` (`hud.gd` usa `Cfg` 15 veces).
- Cambiar una perilla es el comando `ajuste`.

**C2 · Panel de perillas.**
- Grupos (economía, máquinas, robots, cintas, ciudad, tiempo), búsqueda, deslizador y campo numérico.
- Marca de «modificada» y botón para volver al valor por defecto.
- Historial de cambios con la hora simulada.
- **A/B rápido:** una tecla alterna entre dos valores de la misma perilla para *sentir* la diferencia (velocidad del robot, de la cinta), como el A/B de un ingeniero de sonido.
- En escritorio puede abrirse en **otra ventana del sistema** (`Window` con `embed_subwindows` desactivado) para tenerla en un segundo monitor (ver DV3).

**C3 · Perfiles.**
- Un perfil es un JSON en `Concepto2/datos/balance/` que solo guarda las diferencias con los valores por defecto. Se carga con `--perfil=ciudad_dura`, desde la consola o desde el panel.
- Si el archivo cambia en disco, se recarga: puedes editarlo en tu editor y el juego lo toma.
- **«Promover»** genera el cambio para `config.gd` (texto listo para pegar o diff), y así se cierra el ciclo entre experimento y código (ver DV1).

**C4 · Variantes de comportamiento.**
- `sim.aj.variante("robots.lleno")` devuelve el nombre de la variante activa, y el código elige con `match`.
- Candidatas de hoy:
  - qué hace una mula ante una entrada llena: derramar (hoy) o esperar;
  - si una cinta que lleva el material equivocado lo rechaza o lo tira al suelo;
  - el bloqueo como corte total o como retraso.
- **Regla:** cada variante lleva una fecha de caducidad. Cuando decides, se borra la perdedora; si no, el código se pudre.

### O · Observar

**O1 · Inspector del estado oculto.** Es lo que más falta: el jugador no debe ver las utilidades de la ciudad, pero tú sí.
- **Ciudad**, por distrito:
  - las utilidades V y las probabilidades p, la opinión y la exposición desglosada (humo, ruido, tráfico);
  - los contadores frente a sus umbrales: «ordenanza 7/12 quejas nocturnas», «Centro protesta 0,14/0,20», «enfriamiento del bloqueo 3 h»;
  - la próxima auditoría y el desglose del precio.
- **Máquina:** % de tiempo en cada estado durante la última hora.
- **Robot:** órdenes, `pc`, `atasco`, el camino A* y la última razón de `sin_ruta`.

**O2 · Superposiciones del mapa** (se activan una a una):
- **Utilización:** cada máquina se colorea por su estado dominante (trabajando, sin insumo, salida llena). La cadena de colores dice dónde está el cuello de botella.
- **Tráfico y atascos** de robots: un mapa de calor acumulado.
- **Derrames** y material en el suelo.
- **Humo y ruido:** cuánto aporta cada máquina a la exposición de cada distrito.
- **Rutas** de los robots.

**O3 · Gráficas en vivo.**
- Series: dinero y su ritmo (₵/min), producción por material, precio del circuito, opinión por distrito, quejas por hora y robots ociosos. Ventana de N minutos.
- **Versión gratis:** `Performance.add_custom_monitor("sim/dinero", …)` hace que el depurador del editor (Depurador → Monitores) las dibuje sin escribir interfaz. Sirve desde el primer día mientras llega el panel propio.

**O4 · Línea de tiempo de hitos.**
- Primer lingote, primer circuito, primera venta, primer robot fabricado, primera queja, bloqueo, ordenanza, primera multa. Junto a ellos, tus notas (R2) y los cambios de perillas.
- Cada marca es clicable y te lleva a ese momento (por L3).

**O5 · Calculadora de economía.** Se calcula a partir de las perillas, sin simular, y se actualiza al mover un deslizador:
- coste por unidad y margen;
- ritmo de cada máquina y proporciones (cuántas fundidoras saturan una ensambladora);
- tope de venta del camión;
- tiempo que tarda cada edificio en pagarse.

> **Lo que mostraría hoy** (cuentas a mano, aproximadas):
> - **Costes de entrada:** el cobre sale a ₵ 4/u y el silicio a ₵ 8/u.
> - **Lingote:** cuesta ₵ 4 y se vende a ₵ 7, margen ₵ 3.
> - **Circuito:** cuesta ₵ 16. Se vende a 24 × (0,7 + 0,6·p̄), con p̄ la intención media de compra; con p̄ entre 0,5 y 0,75 sale a ₵ 24–28.
> - **Lo que aporta ensamblar:** dos lingotes vendidos más el silicio ahorrado valen ₵ 22, así que la ensambladora solo añade **₵ 2–6 por circuito**.
> - **Por qué igual compensa:** el camión lleva 20 unidades, y la ida y vuelta (72 m a 7 m/s, más 3 s de descarga) dura ≈ 24 s. Con ese tope de ≈ 0,8 u/s, los circuitos dejan ₵ 6–10/s y los lingotes ≈ ₵ 2,5/s.
> - **Proporción:** una ensambladora necesita 1,25 fundidoras.
> - **Conclusión:** quizá sea el diseño que quieres; hoy nadie lo vería sin hacer cuentas.
>
> **Y lo que dice la prueba larga.** El bot de `prueba_larga` empieza con ₵ 20 000 y termina con ₵ 16 953: gastó ₵ 4 880 en compras y ₵ 240 en multas, y vendió por ₵ 3 089. Pero FUN-02, FUN-03 y FUN-04 hicieron 8 lingotes cada una y se quedaron en `salida_llena`, porque nadie recoge su salida. Hay dos lecciones: el balance no se ve sin herramientas, y **un bot mal diseñado da conclusiones malas**.

### J · Juzgar

**J1 · Métricas de partida.** Se guardan cada minuto simulado en la tabla `dev_metricas` y en un CSV de la sesión:
- tiempo hasta cada hito;
- curva de dinero y ₵/min;
- tiempo de espera hasta la próxima compra con sentido;
- utilización por máquina;
- derrames por hora;
- % de robots ociosos;
- presión de la ciudad (distancia a cada umbral);
- comandos por minuto, que salen del diario.

**J2 · Matriz acción × progreso.** Es la mejor aproximación a la diversión que se puede medir sin preguntarle a nadie. Por cada minuto, la acción son los comandos del jugador (diario) y el progreso, el dinero y los hitos:

| | Hay progreso | No hay progreso |
| --- | --- | --- |
| **Poca acción** | La automatización paga: es la recompensa de este género | Espera muerta: aburrimiento |
| **Mucha acción** | Juego activo | Apagar fuegos: frustración (derrames, atascos) |

Ojo con lo típico del género: en un juego de automatización, poca acción no es mala señal; solo lo es si además no hay progreso. La línea de tiempo (O4) se colorea con esta matriz.

**J3 · Bots que juegan y barridos sin ventana.**
- Uso: `tools/balance/correr.gd --perfil=… --bot=novato --dias=3 --semillas=1..20`. Escribe un CSV o JSON por partida y un informe HTML con tablas y curvas.
- Tres bots:
  - **pasivo:** no construye; sirve de línea base;
  - **novato:** construye lento y compra cuando le falta material;
  - **experto:** sigue un orden de construcción optimizado.
- La distancia entre el novato y el experto da el suelo y el techo de habilidad.
- `prueba_larga` ya es un protobot.
- La varianza llega con la semilla de la ciudad como perilla.
- **Límite:** los bots miden economía y ritmo, no diversión. Responden a «¿se rompe la economía si cambio X?», no a «¿es entretenido?».

**J4 · Sensibilidad: ¿qué perillas importan?** Se mueve cada perilla un ±20 %, se corre el bot novato y se mide cuánto cambia cada métrica. El resultado es un ranking (gráfico de tornado) que separa:
- las perillas muertas, que no mueven nada y se pueden congelar o borrar;
- las peligrosas, en las que un 20 % rompe el juego;
- las que de verdad dan forma a la experiencia.

Con unas 60 perillas sale en unos pocos minutos.

**J5 · A/B sobre tu propia partida.** Se reproduce el diario de una sesión tuya con otro perfil y se comparan las métricas lado a lado. Ojo: la partida se desvía. Si una obra ya no se puede pagar, el comando falla, queda anotado como fallido y eso también es información. Funciona mejor con perillas de ciudad y precio que con costes de construcción.

**J6 · Pruebas de ritmo.** Son expectativas escritas como aserciones y se corren con las pruebas sin ventana:
- «el bot novato vende por primera vez antes de 4 min»;
- «sin multa antes del día 2»;
- «el experto no pasa de ₵ X al día 3».

Protegen el balance de cambios de código, tanto los de Codex como los tuyos, igual que `prueba_determinismo` protege el replay.

### R · Registrar

**R1 · Grabadora siempre encendida** (en modo desarrollo). Cada sesión se guarda en `user://sesiones/<fecha>/`: `diario.json`, `perfil.json`, `metricas.csv`, `notas.json` y el hash de git. Cualquier error se puede reproducir, porque un diario es un caso de prueba.

**R2 · Notas de playtest.** Con la tecla N escribes una nota rápida que lleva su `n_paso` y una etiqueta opcional: *aburrido*, *frustrante*, *confuso*, *¡bien!*. Aparecen en la línea de tiempo.

**R3 · Playtest remoto (web).** Quien prueba la demo de Vercel pulsa una tecla y descarga su sesión; tú la reproduces en local con todas las herramientas. Depende de DV2.

**R4 · Revisión de sesión.** Abres una sesión grabada y ves su línea de tiempo, las métricas y las notas. Desde cualquier nota puedes saltar a ese momento (L3) y probar ajustes desde ahí.

---

## Así se vería una sesión de ajuste

Problema: *«la ordenanza llega demasiado pronto y la multa parece arbitraria»*.

1. **Registrar.** En la sesión de ayer hay una nota «multa sin entender por qué» a las 23:10 del día 1 (R4).
2. **Llegar.** Saltas a esa nota (L3).
3. **Observar.** El inspector de la ciudad (O1) muestra `quejas_nocturnas 12/12` a las 23:00 del día 1. El ×2,5 del ruido nocturno dispara la cuenta.
4. **Cambiar.** `ciudad.umbral_ordenanza` pasa de 12 a 25 y `ciudad.ruido_noche` de 2,5 a 1,8 (C2).
5. **Juzgar.**
   - A/B con tu diario (J5): la ordenanza llega ahora a las 02:00 del día 2.
   - Barrido con el bot novato y 20 semillas (J3): el % de partidas con multa antes del día 2 baja del 85 % al 30 %. Son cifras inventadas: esto es lo que respondería la herramienta.
6. **Registrar.** Guardas el perfil, lo promueves a `config.gd` y añades la prueba de ritmo «sin ordenanza antes del día 2 con el novato» (J6).

Sin devtools, el paso 2 cuesta 10 minutos de juego cada vez y los pasos 3 y 5 son conjeturas.

## Fases

| ID | Actividad | Dueño | Tamaño | Depende de |
| --- | --- | --- | --- | --- |
| **Fase 1 · Cimientos** | | | | |
| L1 | Consola de desarrollo y comandos `dev_*` en `aplicar` | Codex (comandos) + Claude (consola) | M | — |
| L2 | Paso a paso, ×16/×32, «avanzar hasta» | Claude | S | — |
| L3 | Ranuras, reinicio y rebobinado por replay | Codex (`reproducir` con perfil) + Claude (restaurar vistas y base) | M | L1 |
| R1 | Grabadora de sesiones | Claude | S | — |
| R2 | Notas de playtest | Claude | S | R1 |
| **Fase 2 · Perillas** | | | | |
| C1 | Registro `Ajustes` por simulación y migración de los números escritos en el código | Codex | L | L1 |
| C2 | Panel de perillas con A/B rápido | Claude | M | C1 |
| C3 | Perfiles JSON, recarga en caliente y «promover» | Codex (carga) + Claude (panel) | S | C1 |
| O5 | Calculadora de economía | Claude | S | C1 |
| **Fase 3 · Observar** | | | | |
| O3 | Monitores del depurador (versión gratis) | Claude | S | — |
| O1 | Inspector del estado oculto | Codex (exponer los términos de la ciudad) + Claude | M | C1 |
| O2 | Superposiciones del mapa | Codex (acumular tráfico y estados) + Claude | M | — |
| O4 | Línea de tiempo de hitos y notas | Claude | M | R1, L3 |
| **Fase 4 · Experimentar** | | | | |
| J1 | Métricas y tabla `dev_metricas` | Codex | M | C1 |
| J3 | Bots y barridos sin ventana, con informe | Codex (bots y corredor) + Claude (informe) | L | J1 |
| J6 | Pruebas de ritmo | Codex | S | J3 |
| J4 | Sensibilidad | Codex | S | J3 |
| J5 | A/B sobre una sesión | Codex + Claude | S | L3, J1 |
| J2 | Matriz acción × progreso en la línea de tiempo | Claude | S | J1, O4 |
| L5 | Escenarios | Codex (formato y carga) + Claude (lista) | M | L3 |
| C4 | Variantes de comportamiento | Codex | S cada una | C1 |
| R3 | Playtest remoto en la web | Claude | S | R1, DV2 |

**Orden recomendado.** La fase 1 completa, y después C1, C2 y O5. Con eso tienes el 80 % del valor para los primeros testeos: llegar rápido, cambiar en vivo y ver la economía. O3 es gratis y conviene hacerla en cualquier momento. La fase 4 merece la pena cuando ya juegues con regularidad y quieras confirmar lo que sientes.

**Paralelismo.** Codex hace los comandos `dev_*` y luego C1 mientras Claude hace la consola, L2, R1 y R2. Todo eso puede ir en paralelo con la fase 1 del plan anterior (1.3 Menú Construir), porque no toca los mismos archivos. C1 sí toca `config.gd` (zona compartida) y casi todo `sim/`, así que va con ciclo adversarial y **antes** de 3.1 (Operario T1 como base), que cambia los robots.

**Contrato.** Hay que añadir un apartado «Modo desarrollo» a [CONTRATO.md](../colaboracion/CONTRATO.md) con los comandos `dev_*` y `ajuste`, `sim.aj` y su esquema, `sim.trampas`, y el cambio de `Cfg` a `sim.aj` en todo lo que lee la presentación.

## Fuera de alcance (por ahora)

- Un editor de mapas o de niveles.
- Un tablero externo conectado en vivo, por ejemplo una página web servida por el servicio Node: es posible, porque el canal ya existe, pero sería demasiada ingeniería para hoy.
- Hacer en tiempo real la recarga en caliente del código de la simulación. Para el código, la estrategia es relanzar en el escenario.

## Decisiones abiertas

| ID | Pregunta | Recomendación | Afecta a |
| --- | --- | --- | --- |
| DV1 | ¿El balance sigue viviendo en `config.gd` (los perfiles son experimentos y «promover» genera el cambio) o pasa a un archivo de datos como fuente de verdad? | `config.gd` sigue mandando por ahora: es tipado y es un solo sitio. Se revisa cuando haya un árbol de tecnologías | C1, C3 |
| DV2 | ¿Devtools en la demo web, detrás de `?dev=1`, para playtesters remotos? | Sí, pero solo la grabadora, las notas y la descarga de la sesión (R1–R3), no los trucos | R3 |
| DV3 | ¿Panel acoplado en la pantalla del juego o ventana aparte del sistema? | Ventana aparte en escritorio (segundo monitor) y acoplado en la web | C2, O1, O3 |
| DV4 | Tecla de la consola: `º` o F12 | `º`: está a mano y no choca con nada de hoy | L1 |
| DV5 | ¿Mover perillas marca la partida como «tocada», igual que un truco? | No: un contador aparte. Los perfiles son parte del experimento, no trampas | J1, J3 |
| DV6 | ¿La semilla del mapa también varía en los barridos o solo la de la ciudad? | Solo la de la ciudad: el mapa y la instalación inicial están pensados a mano | J3 |

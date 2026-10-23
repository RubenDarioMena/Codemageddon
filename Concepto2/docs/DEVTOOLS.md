# Laboratorio de jugabilidad

Las devtools preparan experimentos repetibles sobre el prototipo. Un escenario reúne un estado inicial, ajustes de balance, comandos de preparación, eventos programados y condiciones de pausa. Permite variar una sola condición, repetir la prueba y comparar observaciones.

Las mulas son una mecánica provisional. Los escenarios se describen mediante tipos y niveles de robot y funcionan también con operarios y exploradores.

**F12** abre y cierra el panel; **Escape** también lo cierra. Al abrir se pausa la partida y se puede reanudar desde el propio panel.

## Preparar un experimento

1. Elegir un escenario de ejemplo o una plantilla.
2. Ajustar presupuesto, día, hora, sistemas y entidades.
3. Validar y aplicar el escenario; la sustitución empieza pausada.
4. Avanzar un paso o reanudar, observar el inspector y añadir notas.
5. Guardar el punto de prueba o volver a cargar el escenario para repetir desde su estado inicial.

El estado inicial se prepara directamente: elegir las 23:00 no simula las horas anteriores ni genera sus quejas. Para observar consecuencias acumuladas hay que ejecutar esos pasos de simulación.

## Granularidad

El panel tiene cinco pestañas:

| Pestaña | Opciones |
| --- | --- |
| Controles | Pausa, avance de 1/20/250 pasos, velocidad ×1/2/4/8/16, reinicio, presupuesto, terminar obras, reparar y congelar sistemas. |
| Escenario | Presets, guardados y editor JSON completo para aplicar el escenario preparado. |
| Entidades | Altas de robots y máquinas del catálogo; edición de máquinas por ID, lista separada por comas o `*`; comandos JSON para el resto del mundo. |
| Ajustes | Catálogo buscable, unidades, valor actual, aplicación y vuelta al valor de fábrica. |
| Inspector | Estado del experimento actualizado cada medio segundo y notas asociadas al momento de juego. |

Los cambios de estado pueden dirigirse a una entidad o, para máquinas, una lista explícita de entidades. Permiten variar inventarios, receta, avance, obra pendiente, pausa, turno, avería y envío automático. Los robots admiten posición y carga, y los exploradores pueden activar su rutina automática. Los comandos JSON permiten además cambiar velocidad (`vel`) y capacidad (`cap`) de un robot individual y duración de recetas (`tiempo`, factor de 0.1 a 10) de una máquina individual.

Los ajustes de balance de robots se aplican por nivel a unidades existentes y nuevas. Otros ajustes controlan duración de recetas, velocidad de cintas, sensibilidad al ruido nocturno, umbral de ordenanza y multa. Los cambios se guardan en la simulación del experimento y conservan los valores originales del proyecto.

Los valores incluyen unidades: velocidades en metros por segundo, tiempos en segundos simulados, capacidades en unidades y presupuesto en créditos. La simulación avanza a 20 pasos por segundo. Los eventos programados usan pasos, relativos al inicio del experimento.

Los cuatro sistemas que se pueden congelar son ciudad, producción, robots y logística. Congelar un sistema detiene sus actualizaciones; el reloj del experimento puede seguir avanzando. La pausa general detiene todo el reloj y el avance manual ejecuta pasos completos.

## Escenarios JSON

El formato versionado usa diccionarios y arrays JSON. Las coordenadas de celda se expresan como `[x, z]`; el cargador las convierte a las coordenadas de Godot. Los comandos se ejecutan en orden y los identificadores producidos por cada alta quedan disponibles para los comandos posteriores.

```json
{
  "version": 1,
  "nombre": "Comparación de capacidad",
  "base": "inicial",
  "inicio": {"dia": 1, "hora": 7, "dinero": 1200, "semilla_ciudad": 7},
  "sistemas": {"ciudad": false, "produccion": true, "robots": true, "logistica": true},
  "ajustes": {},
  "comandos": [],
  "eventos": [],
  "pausa": {"evento": "derrame", "pasos": 0},
  "programas": {}
}
```

`base: "inicial"` conserva la instalación de arranque; `base: "vacio"` permite construir una situación mínima. Los programas asocian un ID de robot con su código fuente. No se ejecutan automáticamente al cargar: su inicio es una acción explícita del experimentador.

### Comandos de preparación

Cada objeto siguiente puede usarse como un elemento de `comandos`. Los IDs de máquina y robot deben existir cuando se aplica ese elemento.

```json
{"tipo":"dev_robot","nivel":1,"cantidad":2,"celda":[23,66]}
{"tipo":"dev_robot_estado","id":3,"celda":[24,66],"carga":"cobre","cantidad":2}
{"tipo":"dev_robot_estado","id":3,"vel":3.5,"cap":4}
{"tipo":"dev_maquina","maquina":"fundidora","celda":[40,70],"rot":0}
{"tipo":"dev_maquina_estado","id":"FUN-01","entrada":{"cobre":8},"progreso":0.5,"pausada":true,"tiempo":1.5}
{"tipo":"dev_ciudad","distrito":"Norte","opinion":0.2,"ordenanza":true,"bloqueo_horas":2}
{"tipo":"dev_material","material":"cobre","cantidad":10,"celda":[24,64]}
{"tipo":"dev_pedido","material":"silicio","unidades":10,"espera":20}
{"tipo":"dev_cinta","celda":[40,65],"dir":0,"material":"lingote","cantidad":2}
{"tipo":"dev_camion","clase":"proveedor","avance":0.5,"carga":{"cobre":10}}
```

El listado muestra objetos independientes, no un solo documento JSON. La orientación de máquinas y cintas usa `0: +X`, `1: +Z`, `2: −X`, `3: −Z`. El progreso de producción está entre 0 incluido y 1 excluido; `obra` es el tiempo de construcción pendiente. Los inventarios se reemplazan con los objetos indicados y las capacidades se validan por material, igual que en el juego.

Los eventos usan el mismo formato dentro de `cmd`:

```json
{"paso":400,"cmd":{"tipo":"dev_pedido","material":"cobre","unidades":10,"espera":0}}
```

El evento se programa a los 20 segundos simulados. Los eventos del mismo paso conservan el orden escrito. Las pausas pueden configurarse por límite de pasos o por la primera aparición de `derrame`, `multa`, `bloqueo`, `ordenanza`, `sabotaje`, `viaje_vacio` o `salida`. Semilla, reloj y limpieza estructural solo se preparan antes del primer paso.

La pausa automática se consume una vez: reanudar o avanzar permite seguir después del evento o límite elegido. Si falla un evento programado, el controlador pausa el experimento con el motivo para corregir la preparación.

Los datos se validan sobre una simulación nueva antes de sustituir la partida actual. Un escenario rechazado deja la partida actual disponible. Conviene guardar el escenario base y duplicarlo para cada variante de un experimento.

## Guardado y reproducción

Un escenario describe cómo empezar; un guardado conserva un punto alcanzado por la simulación mediante su diario de comandos y su número de paso. La reproducción utiliza las mismas órdenes y el mismo estado del generador aleatorio. Los comandos de desarrollo también forman parte de ese diario.

Las ranuras se escriben en `user://devtools/<nombre>.json`, dentro de los datos de usuario de Godot, y aparecen con el prefijo `Guardado:`. Conservan código, ajustes, agenda pendiente, pausas consumidas, notas y métricas del laboratorio. Los nombres no admiten rutas. La escritura sustituye la ranura después de completar un archivo temporal y la carga comprueba que la huella del mundo reconstruido coincide.

El replay y los eventos programados tienen un límite de 24000 pasos, equivalente a 20 minutos simulados. Un cambio de reglas del juego puede invalidar una ranura antigua aunque conserve el mismo formato de archivo; conviene conservar también el JSON del escenario.

Los programas JavaScript tienen estado propio dentro de sus workers. Un guardado del mundo no captura su pila de ejecución, variables locales ni esperas activas. Tras restaurar, el código queda disponible para volver a iniciarlo. Hay que considerar ese reinicio al comparar programas.

Para guardar o avanzar sin dibujar se deben detener los programas activos. Durante una auditoría, el avance se detiene para esperar la respuesta SQL. Para probar la ejecución real de JavaScript, reanudar a velocidad normal desde el panel y abrir su editor con J.

La base de datos es una proyección y un registro de la partida. La restauración no es una copia arbitraria de PostgreSQL/SQLite: cambios manuales de SQL, tablas ajenas al juego o borrados del registro no equivalen al diario del mundo. Para comparar auditorías, emplear el mismo escenario y las mismas condiciones de retención.

## Interpretar resultados

El inspector ofrece el estado real de la simulación: inventarios, órdenes, producción y bloqueos. Las notas del playtest añaden el contexto que las cifras no explican: confusión, espera, frustración o satisfacción. Producción, dinero y número de acciones no miden por sí mismos la diversión.

Para una comparación útil, conservar semilla, programas y condiciones iniciales y cambiar un valor a la vez. Registrar la hipótesis, el cambio, el resultado y el momento en que fue necesario intervenir.

## Verificación sin ventana

Desde `Concepto2/`:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s pruebas/prueba_dev_escenarios.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s pruebas/prueba_dev_comandos.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s pruebas/prueba_sim.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s pruebas/prueba_larga.gd
```

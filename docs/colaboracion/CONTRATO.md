# Contrato núcleo ↔ presentación

Interfaz entre lo que posee Codex (simulación, base de datos, servicio JS) y lo que posee Claude (vista, UI, shaders). Es la única superficie que ambos pueden asumir estable.

> **Estado: borrador.** Está escrito a partir de la descripción de arquitectura del README de Concepto2, **no** de una lectura del código. Primera tarea de Claude como orquestador: leer `scripts/sim/` y `scripts/principal.gd`, y reemplazar cada `⚠ verificar` por la firma real. Mientras tanto, no te fíes de los nombres exactos.

## Principios

1. La simulación corre a **20 Hz con pasos fijos**, sin nodos, y no conoce la presentación.
2. La presentación **solo lee** el estado de la simulación (interpolando entre pasos) y le envía **órdenes**; nunca modifica el estado directamente.
3. Mismo seed + misma secuencia de órdenes ⇒ mismo estado, siempre.
4. Un cambio en este archivo se hace en el mismo commit que el código que lo requiere y se menciona en el resumen/revisión.

## 1. Estado legible por la presentación

| Qué | Dónde | Notas |
| --- | --- | --- |
| Rejilla de 1 m y terreno lógico | `scripts/sim/` ⚠ verificar | La vista pinta el terreno a 16 px/m desde este mapa |
| Máquinas (ID estable, posición, orientación, estado) | `scripts/sim/` ⚠ verificar | Estados incluyen `sin_insumo`, `salida_llena`… |
| Cintas y material en tránsito | `scripts/sim/` ⚠ verificar | |
| Robots (ID, nivel T0–T2, posición, carga, lista de órdenes) | `scripts/sim/` ⚠ verificar | |
| Camiones, ciudad (distritos, opinión) | `scripts/sim/` ⚠ verificar | |

La vista interpola entre el paso anterior y el actual; por eso el estado debe exponer posición previa y actual (o un factor de interpolación).

## 2. Colas de salida (simulación → presentación y base de datos)

Documentadas en el README: la simulación publica tres colas que vacían la presentación y la base de datos.

| Cola | Contenido | Consumidores |
| --- | --- | --- |
| `registro` | Eventos de máquinas/cintas/robots (alimenta la tabla `eventos`) | `base_datos.gd`, paneles UI |
| `quejas` | Quejas, protestas y decisiones de la ciudad | `base_datos.gd`, UI |
| `avisos` | Mensajes para el jugador (derrames, averías, ordenanza…) | UI |

Forma de cada elemento: ⚠ verificar (campos, tipos, unidades).

La auditoría de la ciudad es una consulta que la simulación **pide** y `principal.gd` **ejecuta** sobre la base real.

## 3. Órdenes (presentación → simulación)

Ir a un punto, recoger/entregar en una máquina, minar, reparar, recoger material caído, encolar, bucle, borrar órdenes, rutina automática; construir/demoler/rotar; pausar máquina, turno diurno, enviar camión; pausa y velocidad.

Forma: ⚠ verificar (¿funciones sobre la simulación o comandos en cola?). **Decisión pendiente**: para que los replays sean posibles conviene que todas las órdenes entren por un único punto con un número de paso; eso permitiría pruebas «golden» de determinismo.

## 4. API de programas JavaScript

Idéntica en `servicio/runtime_robot.mjs` (escritorio) y `servicio/web/servicio_web.js` (web). Ejemplos: `yo.recoger("REC-01", "cobre")`, `maquinas["FUN-01"].espacio("cobre")`, `await db.query(...)`, `log()`. Valores de retorno: `"ok"`, `"viaje_vacio"`, `"derrame"`, `"rechazo"`…

Cambiar una versión obliga a cambiar la otra en el mismo commit.

## 5. Configuración y balance

`scripts/config.gd` contiene las constantes de diseño y balance. Lo leen ambos lados; cambiarlo es zona compartida. Los parámetros puramente visuales (paletas, densidad de flora, tramado) viven en la capa de vista, no en `config.gd`.

## Registro de cambios del contrato

| Fecha | Cambio | Autor |
| --- | --- | --- |
| 2026-10-22 | Borrador inicial desde el README | Claude |

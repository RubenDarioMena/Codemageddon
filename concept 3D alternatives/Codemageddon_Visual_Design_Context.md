# Codemageddon — Memoria de diseño visual, robots y dirección artística

**Fecha de consolidación:** 26 de octubre de 2026  
**Uso previsto:** contexto de proyecto para Codex (documento de referencia, no especificación final ni tarea de implementación).  
**Estado:** exploratorio. Distinguir entre decisiones del creador, propuestas generadas por IA y cuestiones pendientes.

## 1. Objetivo del proyecto

**Codemageddon** es un videojuego centrado en automatización industrial y aprendizaje de programación, influido por juegos como *Factorio*. Los jugadores controlan y automatizan fábricas, recursos, máquinas y robots mediante código. Un objetivo importante es que las mecánicas de automatización se relacionen de forma creíble con tecnologías y conceptos industriales reales, sin sacrificar claridad didáctica.

La dirección visual **no está cerrada**: se está explorando un juego de aspecto 2D/3D, con cámara elevada / semicenital, geometría industrial legible, robots modulares y distintos grados de fidelidad gráfica.

### Ejemplo de interacción esperada

```js
await yo.recoger("ENT-1", "cobre");
await yo.entregar("FUN");
```

> El usuario había escrito `Await yo.recoger(ENT-1, cobre)` y `Await yo.entregar(FUN)` como ilustración conceptual. La variante anterior es una normalización visual tipo JavaScript, **no** una decisión sobre API, sintaxis definitiva, tipado ni comportamiento real.

## 2. Historia del robot básico de transporte

### 2.1 Diseño inicial, en conversación anterior (25 de octubre de 2026)

El autor presentó imágenes propias de un **primer robot de Codemageddon**. En esa fase el robot **ya tenía un cuerpo bajo y orugas tipo tanque**, pero **todavía no tenía brazo**. Se pidió mantener su sencillez:

- Apariencia de prototipo industrial, todavía en desarrollo.
- Geometría clara, pocos adornos, pocas tonalidades: principalmente líneas, planos y sombras que definan volúmenes.
- Coherencia visual con máquinas y dispositivos de fábrica.
- Detalle limitado porque en la cámara habitual del juego muchos componentes pequeños no serán distinguibles.
- El robot inicial debe ser económico y funcional; sensores avanzados se reservarían a modelos posteriores más caros.

La cuestión planteada entonces fue qué sensor sencillo permitiría desplazarse de una máquina a otra para recoger y entregar materiales. Se consideraron ideas como un **seguidor de línea** o un **sensor frontal básico**. Esto no implica que la navegación final ya dependa obligatoriamente de líneas pintadas.

### 2.2 Incorporación posterior del brazo

El autor pidió añadir **en la zona posterior del robot** un brazo mecánico **relativamente largo**, a medio camino entre:

- la geometría y amplitud de movimiento de una retroexcavadora;
- la articulación y precisión de un manipulador robótico sencillo.

El propósito del brazo es recoger materiales de máquinas o entradas de recursos, transportarlos y depositarlos en otra máquina. No debe parecer un brazo industrial sofisticado ni introducir excesiva complejidad visual en el primer robot.

### 2.3 Lámina de concepto posterior

![Propuesta de robot básico de transporte](assets/robot_transport_design_sheet.png)

Esta imagen es una **propuesta visual generada**, no un plano CAD definitivo. Muestra:

- Chasis bajo y alargado con orugas laterales.
- Sensores frontales simples: seguidor de línea IR inferior y detector básico de distancia IR/ultrasonido superior (ambos indicados en la lámina, todavía sujetos a validación de diseño de juego).
- Manipulador superior/posterior largo con pinza.
- Un esquema conceptual de 2–3 grados de libertad para el brazo, además de apertura/cierre de pinza. **Los grados de libertad reales aún no están definidos**.
- Una secuencia de aproximación, recogida y entrega en estaciones.

**Corrección explícita del autor:** los círculos rojos destacan un defecto de la imagen: **el brazo generado y su pedestal/base están desalineados**, como si pertenecieran a posiciones o piezas distintas. **No replicar ese error al modelar.** El origen del brazo y el eje o soporte de su primera articulación deben quedar correctamente centrados y físicamente conectados a una única base anclada al chasis. Si se incluye un segundo cilindro o soporte, su función debe ser intencional y clara, no un residuo de generación de imagen.

## 3. Debate sobre calidad gráfica y alcance para una sola persona

Se mostró como inspiración una captura de un juego con **estética de miniaturas/objetos de juguete en 3D**: formas estilizadas, texturas creíbles, iluminación suave y cámara inclinada. Sirvió para preguntar si una persona desarrollando en **Godot** podría alcanzar ese nivel.

![Referencia de nivel gráfico](assets/graphic_quality_reference.png)

Conclusiones de la conversación:

- **Técnicamente viable en Godot 4** para un desarrollador individual, pero el costo principal será crear suficientes activos con calidad consistente, animarlos y mantener el estilo a lo largo del juego.
- El look puede lograrse con modelos low/mid-poly bien diseñados, materiales PBR estilizados, sombras suaves, iluminación controlada y cámara ortográfica o de perspectiva poco pronunciada.
- La iluminación precalculada o una mezcla de iluminación estática/dinámica puede ser útil según la escena y el rendimiento buscado; **no hay aún un pipeline elegido**.
- No se decidió que el objetivo obligatorio sea igualar la referencia ni adoptar una cifra arbitraria de calidad. Se propuso priorizar una apariencia coherente y un alcance sostenible.
- Tener cámara fija o controlada ayuda a la composición y a administrar el detalle.

### Requisito crítico para Codemageddon

**La legibilidad del juego de automatización es más importante que la cantidad de detalle.** El jugador debería comprender rutas, entradas/salidas, recursos, estado de las máquinas, sensores y comportamiento robótico sin que el acabado estético esconda esos sistemas.

## 4. Dos direcciones artísticas propuestas (ninguna seleccionada)

### A. Factory-first / estética cercana a Factorio

- La fábrica, cintas y flujos de producción son el centro visual.
- Los robots se ven pequeños desde cámara elevada; siluetas, funciones y animaciones simples.
- Los enemigos aparecen **más adelante en la historia**, no necesariamente desde las primeras fases.
- Potencialmente menor carga de producción gráfica y mejor lectura de sistemas complejos.

### B. Robot-first / robots con mayor fidelidad

- Los robots, sus estructuras y movimientos reciben mayor protagonismo visual.
- Permite diseños enemigos complejos, robots de rango superior y locomoción articulada.
- Exige mayor esfuerzo en modelado, materiales, rigging, animación, LOD y pruebas de legibilidad.
- **No obliga a abandonar la automatización tipo Factorio.** La posible tensión está en cantidad de detalles visibles, densidad de la fábrica y costos de producción/rendimiento.

### C. Alternativa híbrida surgida de la conversación

Una fábrica visualmente sencilla y bien organizada, contrastada con robots progresivamente más sofisticados, podría comunicar tanto la progresión tecnológica como el peso narrativo de los enemigos. Es una **hipótesis a probar**, no una dirección aprobada.

## 5. Generative Design, enemigos y progresión visual

El autor contempla que **algunos robots enemigos** utilicen formas derivadas del **diseño generativo / optimización estructural**, en ocasiones con geometrías biomiméticas o naturales; se puso como ejemplo un **cuadrúpedo**.

- Los enemigos se introducirían en etapas posteriores de la historia, al menos en la variante factory-first.
- El diseño orgánico/estructural podría diferenciar claramente a enemigos y robots avanzados del transporte básico industrial.
- El autor cuestiona si los diseños generativos serían adecuados dentro de una estética muy simple o si un mayor nivel de detalle volvería ese enfoque demasiado costoso.
- Los resultados de diseño generativo no deben asumirse directamente como mallas listas para jugar: probablemente requieran retopología/simplificación, rigging, colisiones y LOD según el caso.
- No se ha aprobado un sistema procedimental de generación de enemigos en runtime: **“generative design” se está hablando aquí principalmente como enfoque de diseño/formas**.

## 6. Experimento propuesto para decidir el estilo

Construir un **mismo microescenario de fábrica** con dos tratamientos visuales, conservando la misma cámara y las mismas acciones:

1. Versión simple: fábrica legible, materiales básicos, robot de transporte sencillo, cinta, máquinas y cuadrúpedo.
2. Versión pulida: las mismas entidades, geometría/materiales/iluminación/animaciones de mejor calidad.

Medir o comparar:

- Legibilidad desde zoom de juego real: distinguir unidades, acciones y rutas.
- Estilo visual y consistencia del mundo.
- Tiempo de producción por activo y por animación.
- Rendimiento con múltiples robots, máquinas y cintas simultáneamente.
- Claridad de jerarquía entre robot básico, robots más avanzados y enemigos.

**No hacer dos juegos distintos:** la comparación debe controlar el contenido y la mecánica para aislar el efecto del estilo.

## 7. Concept art generado en esta conversación

![Escena de fábrica con robots de distinta categoría](assets/factory_high_fidelity_concept.png)

La ilustración es un **concepto de dirección visual**, **no una captura de un build real de Godot** ni prueba de rendimiento. Interpreta el objetivo de un estilo 2D/3D de mayor fidelidad, una fábrica automatizada y robots de rango superior coexistiendo con el robot básico.

### Contenido destacado de la escena

- Cámara alta oblicua, cercana a una vista isométrica de juego.
- Fábrica compacta con máquinas de procesamiento, transportadores, cajas de recursos, rutas señalizadas, barandales y paneles industriales.
- Robot básico cerca del centro: chasis de orugas, sensores frontales, brazo largo montado en la parte superior, sujetando/entregando una caja.
- Robot con orugas y brazo de mayor tamaño para manipular cajas pesadas.
- Robot tipo elevador/montacargas.
- Robot con extremidades articuladas, como ejemplo de categoría más avanzada y silueta distinta (no define todavía al enemigo cuadrúpedo final).
- Paleta crema/blanco, turquesa, amarillo industrial, naranja y acentos verdes.
- Materiales 3D estilizados, reflejos suaves, luces de señalización y sombras con aspecto de maqueta/miniatura.

### Interpretación correcta

El autor solicitó imaginar **el robot básico de transporte junto con otros robots de rango superior** en una fábrica, desde una cámara **más cenital/elevada**, con mezcla de lectura 2D y volumen 3D. La imagen cumple como inspiración, pero su ángulo, densidad de props y desenfoque deben ajustarse si interfieren con la experiencia real de programación/automatización.

**Cuidado especial:** al tomar la imagen como referencia, preservar la base del brazo bien alineada con el cuerpo y con la primera articulación; el error marcado en la lámina previa **no** es parte del diseño deseado.

## 8. Elementos confirmados vs. por decidir

| Tema | Estado | Aclaración |
|---|---|---|
| Juego de automatización que enseña programación | Visión confirmada | El código controla comportamiento de robots/fábrica. |
| Robot inicial de transporte con orugas | Preferencia expresada | Mantener geometría industrial simple. |
| Brazo posterior relativamente largo, estilo retroexcavadora/manipulador | Preferencia expresada | Adaptado a recolección/entrega. |
| Brazo correctamente alineado con su pedestal | Corrección explícita / requisito | No replicar desalineación de concepto previo. |
| Sensores económicos y funciones modestas en nivel inicial | Intención confirmada | Tecnología sensorial concreta por decidir. |
| Sensores IR seguidor de línea + distancia | Propuesta visual | Aparecen en lámina, no requisitos cerrados. |
| 2–3 DOF del brazo | Propuesta visual | No es cinemática final. |
| Godot como opción para estilo 3D | En evaluación | Se habló de viabilidad, no constituye orden de migración ni arquitectura. |
| Cámara alta / semicenital, lectura 2D/3D | Dirección bajo prueba | Comparar con la experiencia de juego real. |
| Mayor detalle gráfico tipo miniaturas | Referencia / exploración | No es compromiso de producción. |
| Enemigos de diseño generativo y biomimético | Idea de exploración | Posibles cuadrúpedos; aparición posterior. |
| Robots superiores con siluetas distintas | Idea visual | La imagen propone ejemplos, no clases definitivas. |
| Enfoque factory-first, robot-first o híbrido | Pendiente | Validar con un prototipo comparativo. |

## 9. Instrucciones para un agente Codex

1. **Tratar este Markdown como memoria contextual y de diseño**, no como una lista de tareas a ejecutar automáticamente.
2. Antes de proponer cambios, revisar el GDD, la arquitectura y el estado **actual** del repositorio; resolver cualquier contradicción a favor de decisiones más recientes y explícitas del proyecto.
3. No dar por hecho que el render conceptual refleja modelos 3D terminados, requisitos de cámara, paleta obligatoria o assets existentes.
4. Si se pide modelar el robot básico, partir de las **orugas y chasis sencillos** y de un **brazo largo posterior** bien montado/alineado; evitar detalles mecánicos invisibles a escala real de gameplay.
5. No convertir los robots con formas generativas ni los cuadrúpedos en requisitos del MVP sin confirmación.
6. Para sugerir prototipos gráficos, priorizar comparaciones de **legibilidad, costo de producción y rendimiento**.
7. Separar siempre: **(a) decisión explícita del autor, (b) hipótesis/propuesta de IA, (c) referencia artística y (d) cuestión sin resolver**.

## 10. Índice de recursos incluidos

| Archivo | Función |
|---|---|
| `assets/robot_transport_design_sheet.png` | Diseño con brazo, vistas y problema señalado en círculos rojos. |
| `assets/graphic_quality_reference.png` | Captura de referencia para nivel de calidad estilizada 3D. |
| `assets/factory_high_fidelity_concept.png` | Escena conceptual de Codemageddon generada a partir del diseño y la conversación. |

> **Nota de procedencia:** la primera etapa del diseño (robot con orugas pero sin brazo) se sintetizó de la conversación anterior recuperada; **las imágenes originales de esa etapa no forman parte de este paquete**. Si Codex necesita comparar exactamente la silueta antigua, habrá que añadir esos archivos originales. Las tres imágenes listadas arriba sí se incluyen.

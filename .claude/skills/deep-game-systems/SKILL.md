---
name: deep-game-systems
description: Analiza una mecánica, sistema o interacción de Codemageddon como parte de una red de sistemas (mecánica → sistema → emergencia), no como contenido aislado. Úsala siempre que se diseñe, cambie o conecte una mecánica de código (verbos de la API como yo.recoger / yo.entregar, sensores, db.query), un puente entre sistemas (robots, inventarios, máquinas, base de datos, ciudad, economía), un ejercicio adaptado de un curso de JS/SQL, o un ajuste basado en feedback o telemetría de jugadores. También antes de prototipar una mecánica en un sandbox HTML.
---

# Deep Game Systems

Marco basado en «How Simple Mechanics Become Deep Game Systems» (https://www.youtube.com/watch?v=1Og5dH8XEg0), adaptado a un RTS-factory que enseña JavaScript y SQL.

## Vocabulario

- **Mecánica**: una regla o acción atómica. En Codemageddon casi siempre es un **verbo de la API** con firma, duración en tiempo de juego y valores de retorno (`await yo.recoger("REC-01", "cobre")` → `"ok" | "viaje_vacio"`).
- **Sistema**: reglas conectadas que producen comportamiento complejo. Ej.: recoger + inventarios multimaterial + capacidad de entrada + derrames = sistema logístico.
- **Emergencia**: soluciones que nadie programó y que salen de combinar reglas simples. Aquí la emergencia vive **en los programas que escribe el jugador**: si dos verbos simples permiten un programa que no habíamos previsto, el sistema tiene profundidad.
- **Profundidad ≠ complejidad**: la complejidad cuenta reglas; la profundidad cuenta **decisiones con sentido**. La joya de referencia es `recoger(origen, material)` + `entregar(destino)`: dos verbos, y el segundo argumento abre la decisión «¿qué material, de dónde?».

## Sistemas existentes con los que conectar

Antes de proponer algo nuevo, lee `Concepto2/README.md` y comprueba con cuáles de estos se toca. Si la lista quedó vieja frente al README, manda el README.

| Sistema | Qué aporta | Concepto que enseña |
| --- | --- | --- |
| Robots por niveles (T0 clics, T1 bucle, T2 sensores) | Quién puede ejecutar qué | Secuencia → bucles → condiciones/funciones |
| Inventarios y entradas multimaterial | Capacidad, mezcla, espacio libre | Argumentos, estado |
| Máquinas y cintas | Transformación y flujo | Pipelines, asincronía |
| Errores físicos legibles (`viaje_vacio`, `derrame`) | El fallo es visible y recuperable | Valores de retorno, manejo de errores |
| Base de datos (registro y proyección, tabla `eventos`) | Todo deja rastro consultable | SQL: SELECT, WHERE, GROUP BY, agregados |
| Ciudad (compra, queja, protesta, auditoría) | Demanda y presión externa | Consultas para justificar o diagnosticar |
| Economía (comprar caro e inmediato vs. extraer gratis y lento) | Coste de oportunidad | Optimización, trade-offs |

## Procedimiento

1. **Átomo.** Enuncia la mecánica en una línea: firma, duración en tiempo de juego, qué cambia en el mundo, qué devuelve y qué error físico tiene. Si no cabe en una línea, son dos mecánicas.
2. **Conexiones.** Recorre la tabla de sistemas y escribe, para cada uno que toque, la regla de conexión de una frase («los robots T2 evitan entradas marcadas como llenas en la tabla `estado`»). Busca la **una sola regla nueva** que conecte dos sistemas existentes en vez de añadir un sistema nuevo.
3. **Cadena causa → efecto.** Escribe una cadena de 3 a 5 eslabones como la de la bola de fuego (fuego → pasto → IA evita → embudo en el puente). Debe terminar en una situación que el jugador resuelva con código.
4. **Escenario emergente.** Describe al menos un programa de jugador que funcione y que **no** hayamos escrito como solución esperada. Si no se te ocurre ninguno, la mecánica es lineal: vuelve al paso 2.
5. **Las cinco preguntas.** Responde cada una en una o dos frases:
   1. ¿Esto añade contenido aislado o profundiza un sistema que ya existe?
   2. ¿Genera una decisión nueva, o solo hace algo «más fuerte» (más rápido, más capacidad)?
   3. ¿Qué más del mundo puede afectar esta mecánica?
   4. ¿Aporta una decisión significativa o solo complejidad?
   5. ¿Puede el jugador ver la regla y deducir por qué su programa falló, o se siente aleatorio?
6. **Legibilidad.** Indica en qué canal se ve cada regla: el mundo (color, forma, animación), la línea del código iluminada, el valor devuelto, `log()`, o una fila en la base. Toda regla necesita al menos un canal visible; el ciclo es observar → experimentar → aprender → dominar.
7. **Concepto pedagógico.** Qué concepto de JS o SQL hace *necesario* esta mecánica (no solo posible) y en qué nivel de robot aparece. Si viene de un curso, cita la lección y explica qué ejercicio del curso reemplaza.
8. **Riesgos.** Estrategia dominante (¿hay un programa de 3 líneas que lo resuelve todo?), bucles infinitos o esperas muertas, no determinismo, fallos invisibles, y si choca con algún error físico existente.
9. **Telemetría.** Qué eventos debe registrar el sandbox o el juego para saber si funciona: intentos hasta el éxito, errores por tipo, verbos usados, longitud del programa, tiempo hasta el primer programa que funciona, abandono. Si el cambio viene de telemetría, empieza por el dato y la hipótesis de por qué ocurre.
10. **Prototipo mínimo.** Especifica el sandbox HTML más pequeño que prueba la hipótesis: mapa (casillas), entidades, verbos expuestos, código inicial, condición de victoria y qué telemetría guarda. Un sandbox prueba **una** pregunta.

## Formato de salida

```markdown
## <Nombre de la mecánica>
**Átomo:** `firma` — duración · efecto · retornos · error físico
**Conexiones:** sistema → regla (una por línea)
**Cadena:** A → B → C → situación a resolver con código
**Emergente:** programa no previsto que funciona (con código corto)
**Cinco preguntas:** 1… 2… 3… 4… 5…
**Legibilidad:** regla → canal
**Concepto:** JS/SQL · nivel de robot · lección de origen (si hay)
**Riesgos:** …
**Telemetría:** eventos
**Sandbox:** mapa · verbos · código inicial · victoria
**Veredicto:** profundiza / solo complica / descartar, y por qué
```

## Cuándo no aplicarla

No todo debe ser sistémico. Los tutoriales de un solo concepto y los retos de precisión (por ejemplo, «escribe esta consulta exacta») pierden claridad si el caos del mundo interfiere. En esos casos dilo y propone aislarlos del resto de sistemas.

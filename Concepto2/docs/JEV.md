# ¿Usar Jev (TypeSafe AI) para las decisiones del juego?

Análisis del 22 de octubre de 2026. Las cifras de rendimiento son del fabricante o de artículos secundarios; no las verifiqué.

## Qué es Jev

Jev es el primer modelo «System One» de TypeSafe AI. No genera texto: recibe un **estado** (texto o JSON) y una lista de **preguntas tipadas**, y en una sola pasada no autorregresiva devuelve decisiones con probabilidades calibradas.

| Tipo de pregunta | Qué devuelve |
| --- | --- |
| `Choice` | Una opción de una lista cerrada (hasta 255), la probabilidad de cada opción y una confianza |
| `Score` | Una posición en una escala ordenada de 2 a 10 niveles (puede caer entre niveles) |
| `Noul` | La probabilidad de «sí» en una pregunta de sí/no |

Datos prácticos:

- **API y modelo:** `POST /v1/systemone` en `api.typesafe.ai`, SDK de Python `typesafe-sdk`, modelo `jev-1.13` (`jev-latest`).
- **Latencia:** de 70 a 500 ms por llamada.
- **Precio:** $0,042 por millón de tokens de entrada; la salida no se cobra.
- **Contexto:** de 32 000 a 64 000 tokens según la fuente.
- **Límites declarados:** falla contando, haciendo cuentas o comparando fechas; lee las preguntas de forma literal (una negación se le puede escapar); el orden de las opciones puede cambiar la respuesta; el texto hostil dentro del estado puede manipularlo. Que la salida tenga un tipo válido no significa que sea correcta.
- **Ejemplo de juego:** el codelab de Google trae uno: elegir la respuesta a un oponente con un `Choice` y preguntar con un `Noul` si está expuesto.

**Alternativas abiertas:**

- **Laya:** 421M parámetros sobre ModernBERT, licencia Apache 2.0. El paquete comunitario `laya-serve` expone un endpoint compatible con Jev. Sin ajuste fino rinde poco (0,362 frente a una línea base de 0,318 por azar y 0,461 por clase mayoritaria); está pensado para especializarlo.
- **openjev:** lee los logits de las opciones de Qwen3.5-4B. Coincide con Jev en 0,845 frente a 0,883, en solo 102 casos. Necesita GPU.
- **gliformer:** un clasificador zero-shot.

Según su fundador, lo que no se copia del modelo es la calibración y los datos de entrenamiento.

## Encaje con Codemageddon

La ciudad ya usa un **logit anidado (GEV)**. Es un modelo estadístico de población: barato, determinista, sin conexión y explicable con SQL. Jev no lo sustituye; resuelve otra cosa: **juicios semánticos sobre texto o estado desordenado**, que un logit no puede hacer.

| Uso posible | ¿Encaja? | Por qué |
| --- | --- | --- |
| **Comunicados a la ciudad.** Tras una protesta, el jugador escribe un mensaje. Jev puntúa el tono (`Score`), elige la reacción del distrito (`Choice`: calma, indiferencia, indignación) y estima si promete algo verificable (`Noul`). Eso ajusta las utilidades del logit. | **Sí, es el mejor primer experimento** | Lo que hace es juzgar texto libre, que es justo el terreno de Jev. Pasa pocas veces (latencia irrelevante) y enseña comunicación con datos. |
| **Robots T3 con «chip de criterio».** Una API JS `await ia.decidir(estado, {accion: Choice([...])})` que devuelve una decisión con confianza; el programa actúa por encima de un umbral y escala por debajo. | **Sí, como nivel avanzado** | Enseña algo muy valioso hoy: un modelo de decisión es una función probabilística que se encapsula, se umbraliza y **se monitorea**. Cada decisión puede ir a una tabla `decisiones` para medir su acierto con SQL. |
| **Auditor que valida consultas del jugador** | Parcial | Si la consulta es correcta se comprueba ejecutándola. Jev solo serviría para pistas («¿la consulta responde a la pregunta?»). |
| **Detectar errores en programas JS** | No | El análisis estático es exacto y gratuito. |
| **Movimiento o producción tick a tick** | No | 70–500 ms por llamada es demasiado para 20 Hz, y es lógica que el código calcula mejor. |
| **Sustituir el logit de la ciudad** | No | Perderíamos determinismo, juego sin conexión y la explicación por SQL. Jev mismo recomienda dejar los cálculos al código. |

## Riesgos y condiciones

1. **No depender de él para jugar.** El GDD dice que el prototipo no dependerá de un servicio de IA. Jev debe ser una capa opcional, con el logit como respaldo.
2. **Clave de API.** En la versión web no puede ir en el cliente. Haría falta un proxy en el servidor (por ejemplo, una función de Vercel) con límite de uso.
3. **Reproducibilidad.** Las respuestas son probabilísticas, pero la simulación es determinista. Para pruebas y repeticiones habría que guardar cada decisión y muestrear con semilla.
4. **Coste.** Es bajo. Con tres distritos y una llamada por hora simulada de unos 1 000 tokens, son unos 864 000 tokens por hora de juego real, menos de 4 centavos de dólar.
5. **Seguridad.** El texto del jugador entra en el estado. Jev puede ser manipulado por ese texto; para un juego eso puede ser incluso una mecánica (persuasión), pero sin consecuencias graves.

## Propuesta

1. **Un motor de decisiones con el formato de Jev:** `estado + preguntas tipadas → probabilidades`, con tres implementaciones:
   - `logit` (el actual, local y por defecto),
   - `jev` (hospedado, vía proxy),
   - `laya` (local experimental, tras ajuste fino con datos generados por el propio logit).

   Así el juego no depende de un proveedor y se puede comparar.
2. **Primer experimento:** los comunicados a la ciudad, registrados en una tabla `decisiones (t, actor, pregunta, opcion, probabilidad, confianza, motor)`.
3. **Más adelante:** el chip T3 para robots, con la lección de umbral y escalado.
4. **No usar Jev para nada que el código calcule** (cantidades, rutas, precios).

## Fuentes

- [DataCamp: Jev, el modelo System One de TypeSafe](https://www.datacamp.com/blog/system-one-models-jev)
- [Google Codelabs: modelos discriminativos (Jev/DiffusionGemma)](https://codelabs.developers.google.com/codelabs/discriminative-models)
- [InfoQ: TypeSafe AI publica Jev](https://www.infoq.com/news/2026/10/typesafe-ai-jev-released/)
- [Firecrawl: qué es Jev (clones abiertos)](https://www.firecrawl.dev/blog/what-is-jev)
- [Referencia de Jev en un gist de GitHub](https://gist.github.com/pjburnhill/adf8d28efcad9df037bfdece178ef965)
- [AI Weekly: Laya, modelo de decisión Apache 2.0](https://aiweekly.co/alerts/convai-ships-laya-a-421m-modernbert-decision-model-apache-20)
- [Besthub: Laya frente a Jev](https://www.besthub.dev/articles/open-source-decision-model-laya-vs-jev-speed-wins-zero-shot-fails-befced0a2228)
- [TypeSafe AI](https://typesafe.ai/)
- [Beam AI: Jev para agentes](https://beam.ai/agentic-insights/jev-typesafe-ai-agents)
- [arXiv: JEV y Laya como capas de decisión](https://arxiv.org/pdf/2609.28940)

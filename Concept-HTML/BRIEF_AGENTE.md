# Brief: el próximo juego (heredero de los prototipos HTML de Codemageddon)

## 1. Contexto y decisión

- Los prototipos de Codemageddon hechos en HTML + JavaScript se probaron con varias personas. Los programadores con experiencia reaccionaron muy bien aunque los usaron poco, y el autor se divirtió resolviendo los ejercicios.
- Lo que funcionó fue que la herramienta es **ligera, minimalista y muy legible**. Eso no se debe perder.
- **Decisión:** el estilo de esos prototipos se vuelve el **primer juego/producto**, con el que iteramos rápido el núcleo de mecánicas. El prototipo en Godot (Concepto2) queda como secuela o reimaginación futura y no se toca por ahora.
- **Se parte directamente del código de los prototipos HTML.** Se evolucionan esos archivos; no se empieza en limpio.
- Flujo de trabajo: Claude orquesta y hace lo visual/artístico, Codex lo técnico (conectado vía MCP, ramas/worktrees), y Claude revisa el código de Codex. Las features nuevas o complejas pasan por 2 ciclos de revisión adversarial.

## 2. Pilares (no negociables)

1. **Legibilidad primero.** Visualmente minimalista, todo se entiende a simple vista.
2. **Simulación determinista** sobre cuadrícula, independiente del renderizado.
3. **PC y móvil a la par desde la v1.** Un solo código web, empaquetado para tiendas.
4. **UI 100 % propia.** No se usan componentes nativos de Android/iOS; todo se diseña a medida para tener control total.

## 3. Alcance de la v1

- Escenarios acotados (niveles/ejercicios), como en los prototipos.
- Editor de código con tres modos de lenguaje (ver §6).
- Mapa con **vista 2D cenital fija por defecto** y **transición fluida a 3D** cuando se desbloquea la cámara.
- Máquinas en el campo como modelos **mínimos tipo silueta**.
- Al mantener presionada o seleccionar una máquina se muestran sus estadísticas en un panel propio sobre el mapa, con gráficos custom.

**Fuera de la v1, pero no hay que cerrarle la puerta:**
- Modo fábrica libre.
- Mundo abierto con relieve.
- Visor de modelos 3D detallados.

## 4. Layout

### Móvil (vertical)
- **Mitad superior:** mapa.
- **Mitad inferior:** editor de código.
- Cuando aparece el teclado, el editor **no cambia de tamaño**: se desplaza hacia arriba y cubre parte del mapa.
- Encima del teclado va una **barra propia de símbolos y palabras clave** (corchetes, operadores, palabras reservadas del lenguaje activo).
- Las estadísticas de la máquina seleccionada aparecen en la parte de arriba del mapa.
- El comportamiento del teclado en iOS es delicado, así que hay que **probarlo en dispositivo real desde el inicio**.

### PC
- Mismo concepto adaptado a horizontal: mapa y editor lado a lado, o divididos de forma redimensionable. Hay que proponer el diseño.

## 5. Render: 2D ↔ 3D sin cortes

- **Una sola escena 3D (Three.js).** El "2D" es esa escena vista con una **cámara ortográfica cenital** a cierta altura. No hay un segundo motor de dibujo.
- **Transición:** se mueve e inclina la cámara y se interpola de ortográfica a perspectiva (técnica tipo *dolly zoom*). La simulación no se entera.
- Etiquetas, íconos de estado y selección van como **billboards**, siempre legibles y nunca como texturas en el piso, porque en 3D unas cosas tapan a otras.
- Las máquinas se diseñan para leerse **desde arriba y de lado**.
- El 3D sirve para contemplar e inspeccionar. **Jugar normalmente ocurre en la vista cenital.**
- Rendimiento: low-poly y siluetas mínimas en el campo. Hay que medir en un celular de gama media.
- **Fase 2: visor de modelos.** Un menú aparte del juego donde se ve de cerca el modelo detallado de cada máquina. Ahí se gasta todo el cómputo en un solo modelo.

## 6. Sistema de lenguajes

- **Tres modos:** seudocódigo, JavaScript y Python. JavaScript tiene un **selector para cambiar a Python**.
- **Recomendación de arquitectura:** los tres lenguajes se compilan a una **representación intermedia común** que ejecuta una **VM propia del juego**. Esto da:
  - determinismo garantizado;
  - presupuesto de instrucciones por tick (sin bucles infinitos colgando la app);
  - ejecución paso a paso para depurar y visualizar;
  - el mismo comportamiento en PC y móvil.

  La alternativa, que no se recomienda, es ejecutar JS real en un sandbox (JS-Interpreter) y Python con Pyodide. Pyodide pesa unos 10 MB y arranca lento en móvil, y además la semántica sería difícil de controlar.
- **Hay que decidir:** si cada lenguaje respeta fielmente su semántica real (más educativo) o si se unifica (más simple).

### Diferencias JS vs Python que afectan los puzzles

| Tema | Python | JavaScript |
|---|---|---|
| Enteros | precisión arbitraria (`2**64` exacto) | float64; los enteros pierden precisión arriba de 2^53 (BigInt aparte) |
| División entera | `7 // 2 == 3` | `Math.floor(7 / 2)`; `7 / 2 == 3.5` |
| Módulo con negativos | `-7 % 3 == 2` | `-7 % 3 == -1` |
| Verdad de vacíos | `[]`, `""`, `{}` son falsos | `[]` y `{}` son verdaderos |
| Igualdad | `==` sin coerción rara | `==` con coerción; se recomienda `===` |
| Estructuras | tuplas, list comprehensions, slicing `a[1:3]`, `in` en listas | `map/filter/reduce`, spread, `includes` |
| Rangos | `range(n)` nativo | sin equivalente directo |

**Implicaciones de diseño:**
- Hay puzzles naturales en un lenguaje que en el otro se sienten raros. Por ejemplo, aritmética con números enormes o recorrer cuadrículas con índices negativos y módulo, como un mapa que "da la vuelta".
- Se pueden convertir en **lecciones de "trampas del lenguaje"**, por ejemplo un puzzle donde el módulo negativo rompe el código JS.
- Hay que validar cada nivel en los tres modos, con soluciones de referencia por lenguaje y tests automáticos.

## 7. Arquitectura propuesta

- **Núcleo de simulación** en TypeScript, puro y determinista, sin dependencias de render. Se extrae del código de los prototipos.
- **VM de lenguajes** con compiladores de seudocódigo/JS/Python hacia la representación intermedia.
- **Render:** Three.js con cámara ortográfica/perspectiva y modelos de silueta.
- **Editor:** CodeMirror 6 con un tema propio y la barra de símbolos móvil.
- **UI:** componentes propios (HTML/CSS o canvas) para paneles, estadísticas y gráficos.
- **Distribución:** web para PC y Capacitor para Android/iOS.
- **Modelo de datos con altura por casilla desde el día uno**, aunque todos los mapas de la v1 sean planos.

## 8. Futuro: viabilidad evaluada

**Viable, para fases posteriores:**
- **Modo fábrica libre.** Técnicamente es un escenario sin condición de victoria; el trabajo real es el balance de economía y desbloqueos.
- **Relieve en cuadrícula.** Alturas como niveles enteros por casilla (terrazas con rampas), de modo que la lógica sigue siendo de casillas.
- **Montañas en 2D como curvas de nivel**, círculos irregulares concéntricos generados desde el mapa de alturas con marching squares.
- **Mundo abierto acotado**, por chunks y procedural con semilla (determinista).

**Descartado por ahora:**
- Mundo infinito con fábricas enormes simuladas fuera de pantalla en celular.
- Terreno con pendientes continuas, que rompe la cuadrícula.
- Jugar con la cámara 3D libre.
- Multijugador.

## 9. Fases sugeridas

1. **Inventario** de los prototipos HTML: mecánicas, ejercicios, qué funciona. Hay que localizarlos en el repo (`~/Documents/Dev/Codemageddon`).
2. **Extraer el núcleo de simulación** a TypeScript, con tests de determinismo.
3. **VM y lenguajes:** primero el que ya usan los prototipos, después los otros dos y el selector JS↔Python.
4. **Escena Three.js** con cámara cenital, siluetas, billboards y la transición 2D↔3D.
5. **Layouts móvil y PC**, editor, teclado, barra de símbolos y panel de estadísticas.
6. **Empaquetado con Capacitor** y pruebas en dispositivos reales.
7. **Playtest** con más gente, luego pulir y lanzar.
8. **Fase 2:** visor de modelos detallados, fábrica libre, relieve y curvas de nivel.

## 10. Riesgos principales

- Que escribir código en el teclado del celular sea incómodo. Se mitiga con la barra de símbolos, autocompletado y quizá bloques o snippets táctiles.
- El teclado virtual de iOS y el layout.
- El costo de mantener tres lenguajes coherentes (tests por nivel y por lenguaje).
- Rendimiento de WebGL en gama baja.
- Que el 3D se coma el calendario. La transición debe quedarse simple y la v1 se juega en cenital.
- Perder la legibilidad minimalista al sumar 3D. Hay que comparar siempre contra los prototipos.

## 11. Preguntas abiertas para el autor

- ¿Semántica fiel por lenguaje o unificada?
- ¿Cómo es exactamente el seudocódigo de los prototipos y se mantiene igual?
- ¿Layout preferido en PC?
- ¿Nombre del nuevo juego? ¿Sigue llamándose Codemageddon?

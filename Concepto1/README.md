# Codemageddon · Concepto 1: estilo híbrido

Demo jugable mínima en JavaScript (Three.js 0.170) para explorar la dirección visual. No es el motor del juego: es una maqueta para decidir **cómo conviven pixel art 2D, modelos 3D y robots mixtos** antes de pasar a Godot. El [GDD](../../Cursos-templates/docs/CODEMAGEDDON_GDD.md) se usó como semilla, no como especificación.

## Abrirlo

Los módulos ES y el `.glb` no cargan desde `file://`, así que hace falta un servidor local:

- Doble clic en `iniciar.command` (abre `http://localhost:8765`). Si macOS lo bloquea la primera vez: clic derecho → Abrir.
- O en terminal: `python3 tools/servidor.py` y abrir `http://localhost:8765`.

Three.js se descarga del CDN jsDelivr, así que necesita internet.

**Controles:** clic en un robot para seleccionarlo; con un robot seleccionado, clic en una mena para asignarla o clic en el suelo para moverlo a mano (eso pausa su rutina; `R` la reanuda). Arrastrar o `WASD` desplaza, la rueda hace zoom, `Q`/`E` giran la cámara 45°, `Espacio` pausa, `1`/`2`/`3` cambian la velocidad, `B` construye un robot.

## Mecánica

Los robots recogen cobre de menas naturales y lo llevan a la tolva de la fundidora. La fundidora produce lingotes, que viajan por una cinta hasta la ensambladora. La ensambladora junta 2 lingotes en un chip y otra cinta lo lleva a la ciudad. Cada chip vendido da 6 ₵ y un robot nuevo cuesta 15 ₵. Las menas agotadas vuelven a crecer.

El inspector muestra la rutina del robot como pseudocódigo y resalta la línea que está ejecutando, como guiño a la idea central del juego.

## El enfoque visual

Una regla temática decide la técnica: **lo vivo se dibuja, lo fabricado se modela, y el robot está entre ambos.**

| Capa | Técnica | Por qué |
| --- | --- | --- |
| Terreno | Pixel art procedural en una sola textura (1024², 16 px/m) | Ocupa la mayor parte del mapa. Se genera con semilla y reacciona a lo que pasa. |
| Flora, menas, humo, chispas | Sprites pixel art en un atlas, una llamada de dibujo por capa | Lo orgánico y el VFX conservan trazo de mano y contorno. |
| Fábrica, cintas, ciudad humana | Modelos 3D iluminados, con sombras y texturas limpias y filtradas | La tecnología tiene volumen real, geometría precisa y animación rígida por piezas. |
| Robots | Volumen 3D por piezas, con «piel» pixel art | La cara es una pantalla con sprite sheet de expresiones. Orugas con textura que se desplaza. ID pintado en píxeles. |

Decisiones que hacen que las dos estéticas parezcan un solo mundo:

1. **Una sola densidad de píxel.** Terreno, sprites y pieles de robot usan 16 px por metro, así ningún píxel es más grande que otro. El zoom solo admite valores enteros de píxeles de pantalla por texel, y la cámara se ajusta a la rejilla de pantalla para que el pixel art no tiemble al desplazarse.
2. **Una sola luz.** El sombreado de los sprites (luz arriba a la izquierda), las sombras horneadas en el suelo y el sol 3D que proyecta las sombras de la fábrica y los robots vienen de la misma dirección.
3. **Sprites que ordenan como en 2D dentro de un mundo 3D.** Cada sprite mira a la cámara y toda su superficie queda a la profundidad de su base. Un robot detrás de un árbol queda tapado, uno delante lo tapa, y nada se corta contra el suelo. Las transparencias se resuelven con tramado ordenado (Bayer), no con mezcla alfa, así que el humo «se disuelve» en píxeles.
4. **El material cruza la frontera.** El cobre es un sprite mientras es naturaleza, también cuando lo carga el robot. Al pasar por la fundidora se convierte en lingote 3D y después en chip 3D. La historia de transformación se lee en el cambio de técnica.
5. **El 2D reacciona al 3D.** Las orugas desgastan el pasto y forman caminos de tierra donde los robots pasan más. Cada chip fabricado seca el terreno alrededor de la fábrica. Las dos cosas son puramente visuales y no tocan la simulación.
6. **Los árboles humanos son 3D.** Los parques de la ciudad tienen árboles modelados: «lo humano» es 3D aunque sea vegetal. El contraste con el bosque pixel es intencional.

Arquitectura: `sim.js` es solo datos, con reloj fijo de 20 Hz. Publica estados y eventos que la presentación traduce. Es el «contrato de estados» del estudio del motor ligero: cambiar un robot a otra técnica de dibujo no toca la lógica.

## ¿Herramienta para generar el pixel art del terreno?

Mi recomendación es **dibujar un set pequeño de piezas a mano y dejar la colocación al código**, no generar el arte entero proceduralmente:

- **En Godot:** `TileMapLayer` con *terrains* (autotiling de bordes) más `FastNoiseLite` para los biomas. La colocación de flora puede hacerse por muestreo de Poisson. Si el mapa necesita estructura (ríos, claros coherentes), Wave Function Collapse con un tileset propio.
- **Para dibujar el set:** [Pixelorama](https://pixelorama.org/) (gratis, hecho con Godot) o Aseprite (de pago, con scripts Lua y exportación por CLI). Kleki sirve para bocetar en el teléfono, como ya propone la guía de arte.
- En este concepto todo (tiles y sprites) sale de código para poder iterar rápido. Sirve para fijar paleta, densidad y reglas de luz, y deja claro qué hace falta pedirle al arte final. No sustituye a un artista.

## Pipeline probado con las apps instaladas

El modelo de la ensambladora (`assets/ensambladora.glb`, con pistón y ventilador animados) se generó con **Blender sin abrir su ventana**, usando un script paramétrico:

```bash
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python tools/blender/ensambladora.py -- assets/ensambladora.glb
```

Los parámetros (ancho, altura, carrera del pistón…) están arriba del script. Cambiarlos genera otra máquina de la misma familia. Es el flujo de «familias paramétricas» de la guía de arte, con Blender en lugar de JSCAD. El mismo `.glb` se importa tal cual en Godot.

## Herramientas y MCP

Verificado el 22 de octubre de 2026 en esta Mac:

| App | Ubicación | Sin ventana (CLI) | MCP recomendado |
| --- | --- | --- | --- |
| Blender 5.2.2 LTS | `/Applications/Blender.app` | ✅ `Blender -b --python …` (lo usé para el GLB) | **MCP for Blender** (antes `blender-mcp`, de ahujasid). `claude mcp add blender uvx mcp-for-blender`, después `uvx mcp-for-blender install-addon`, activar «Interface: MCP for Blender» y pulsar *Start MCP Server* en el panel N. |
| FreeCAD 1.1.4 | `/Applications/FreeCAD.app` | ✅ `Contents/Resources/bin/freecadcmd` | **neka-nat/freecad-mcp** (MIT). Copiar `addon/FreeCADMCP` a `~/Library/Application Support/FreeCAD/v1-1/Mod/`, elegir el workbench «MCP Addon» y pulsar *Start RPC Server*. Registro: `claude mcp add freecad -- uvx freecad-mcp`. |
| Godot 4.7.2 | `/Applications/Godot.app` | ✅ `Godot --headless` | **Coding-Solo/godot-mcp**: `claude mcp add godot -e GODOT_PATH=/Applications/Godot.app/Contents/MacOS/Godot -- npx @coding-solo/godot-mcp`. Permite lanzar el editor, ejecutar el proyecto y leer la salida de depuración. |

Requisitos ya presentes: `uv`/`uvx` y Node 22.

### Instalados (22 de octubre de 2026)

Los MCP de Godot y Blender están registrados en el ámbito de usuario de Claude Code (`~/.claude.json`), así que valen en cualquier proyecto. Aparecen en las sesiones nuevas, no en la que los instaló. FreeCAD queda pendiente.

- **godot**: `npx -y @coding-solo/godot-mcp` con `GODOT_PATH` apuntando a `/Applications/Godot.app` (movido desde el Escritorio el 22 de octubre de 2026). Probado: responde `get_godot_version` → `4.7.2.stable` y expone 14 herramientas.
- **blender**: `uvx mcp-for-blender` con `DISABLE_TELEMETRY=true`, lo que apaga incluso el registro anónimo mínimo. El complemento quedó copiado en `~/Library/Application Support/Blender/5.2/scripts/addons/blender_mcp.py`. Lo revisé: el consentimiento de telemetría viene desactivado, las integraciones externas (Poly Haven, Sketchfab, Meshy, Hyper3D, Poly Pizza) también, y el socket solo escucha en `localhost:9876`.
  - **Falta un paso manual en Blender:** Edit → Preferences → Add-ons → buscar «MCP for Blender» → activarlo, y dejar desmarcado «Allow Telemetry». Después, en el visor 3D: `N` → pestaña *MCP for Blender* → *Start MCP Server*. Hay que pulsar *Start* en cada sesión de Blender en la que quieras trabajar conmigo.

El CLI `claude` no está en el PATH de la terminal. El que trae la app de escritorio está en `~/Library/Application Support/Claude/claude-code/<versión>/…/claude.app/Contents/MacOS/claude`; con él se usa `claude mcp list` para revisar el estado.

### Observaciones

- **Los MCP no son imprescindibles para producir.** Las tres apps funcionan sin ventana desde la terminal, y los scripts quedan versionados y son reproducibles. El MCP aporta trabajar **sobre tu sesión abierta**: ver lo que tienes en pantalla y editar la escena mientras la usas.
- **Orden sugerido:** Godot MCP al empezar el prototipo en Godot; Blender MCP cuando quieras modelar «a cuatro manos»; FreeCAD al final, para piezas mecánicas que luego se exporten como malla.
- **Seguridad del MCP de Blender:** `execute_blender_code` ejecuta Python arbitrario y el socket local no tiene autenticación, así que hay que dejarlo solo en localhost. Por defecto envía telemetría anónima de uso; `DISABLE_TELEMETRY=true` la desactiva.
- Una fuente secundaria menciona un MCP oficial de Blender Lab (`projects.blender.org/lab/blender_mcp`). No pude verificarlo porque la página respondió 403.

## Cómo se traduciría a Godot

| Concepto | Equivalente en Godot |
| --- | --- |
| Textura de terreno + desgaste | `TileMapLayer` o un `Image` editable en una `ImageTexture` |
| Capa de sprites con shader | `MultiMeshInstance3D` con un shader de billboard, o `Sprite3D` con `billboard` + `texture_filter = nearest` |
| Transparencia tramada | El mismo `bayer4` en el shader de material |
| Fábrica GLB animada | Importación directa de escena + `AnimationPlayer` |
| Robot con cara-pantalla | Malla con material cuyo `uv1_offset` avanza por el sprite sheet |
| Simulación a reloj fijo | `_physics_process` o un nodo de simulación sin dependencias de dibujo |

## Límites conocidos de este concepto

- Al girar la cámara, el sombreado dibujado de los sprites deja de coincidir con el sol. Rotar libremente con árboles planos sigue siendo una decisión de diseño abierta, como ya advierte la guía de arte.
- Las sombras de los objetos 3D sobre el terreno pixel son suaves, no pixeladas. Pixelarlas exige un shader propio para el suelo. Es factible y más sencillo en Godot.
- Los robots van en línea recta, sin buscar ruta ni chocar con la flora. El mapa deja los pasillos despejados para que no se note.
- Solo lo probé en el navegador integrado (Chromium) de la app de Claude. No lo probé en móvil, Safari ni Firefox.

## Archivos

```
index.html            interfaz y carga de módulos
src/main.js           cámara, entrada, interfaz y bucle
src/sim.js            simulación a reloj fijo (solo datos)
src/world.js          terreno pixel, flora, menas, desgaste y contaminación
src/pixel.js          paleta y generadores de sprites pixel art
src/billboards.js     capa de sprites instanciada y partículas
src/industria.js      fábrica, cintas, ciudad y carga del GLB
src/robots.js         robot 3D con piel y cara pixel art
assets/               ensambladora.glb (generado por Blender)
tools/                servidor sin caché y script de Blender
```

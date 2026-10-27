# Flujo de colaboración Claude ↔ Codex

Claude orquesta y se encarga de lo visual; Codex se encarga de lo técnico; Claude revisa el código de Codex.

```
usuario ──► Claude (orquestador)
              │  1. descompone la tarea y fija/actualiza el CONTRATO
              ├──► worktree codex  ──► Codex implementa núcleo + pruebas
              │                          │
              │  3. revisión ◄───────────┘  (pruebas headless + juicio de Claude)
              └──► worktree claude ──► Claude implementa presentación (en paralelo, sobre el contrato)
                     4. integración en main con el visto bueno del usuario
```

## Propiedad por carpeta (todo bajo `Concepto2/`)

| Dueño | Carpetas |
| --- | --- |
| **Codex** | `scripts/sim/`, `scripts/db/`, `scripts/servicio/`, `servicio/`, `datos/`, `pruebas/` (salvo `guion_capturas.gd`), `tools/exportar_web.sh` |
| **Claude** | `scripts/vista/`, `scripts/ui/`, `scripts/mundo/`, `shaders/`, `tools/blender/`, `assets/`, `escenas/`, `docs/capturas/`, `pruebas/guion_capturas.gd` |
| **Compartido** (cambio mínimo y avisado) | `scripts/config.gd`, `scripts/principal.gd`, `docs/colaboracion/CONTRATO.md` |

Zonas grises: generación procedural del terreno. **Quien define cómo se ve decide los parámetros (paleta, tramado, densidad); quien define cómo se calcula decide el algoritmo (ruido, determinismo por seed).**

## Ramas y worktrees

- Rama por agente y feature: `agente/codex/<feature>` y `agente/claude/<feature>`.
- Crear: `sh tools/agentes/worktree.sh <codex|claude> <feature>`. El worktree queda en `../Codemageddon-wt/<agente>-<feature>`, fuera del repo, para que Godot no vea dos `project.godot` anidados.
- Delegar: `sh tools/agentes/codex.sh <nuevo|seguir> <worktree> <archivo_encargo>`. Envuelve `codex exec` con sandbox `workspace-write` y guarda el hilo y la traza en `<worktree>.codex/`.
- Codex no commitea: su sandbox no puede escribir en el `.git` del repo principal, donde vive el índice del worktree. Claude commitea en `agente/codex/<feature>` después de revisar.
- Nadie hace push ni merge a `main` sin aprobación del usuario. Claude integra.

## Flujo normal (cambio pequeño o mediano)

1. Claude define el alcance y, si hace falta, actualiza `CONTRATO.md`.
2. Claude crea el worktree y delega a Codex con `codex.sh nuevo`.
3. Codex implementa, corre las pruebas headless y entrega su resumen (formato en `AGENTS.md`), con los cambios sin commitear.
4. **Revisión de Claude** sobre `git diff` del worktree (plantilla abajo). Si hay hallazgos bloqueantes, vuelven a Codex con `codex.sh seguir` (mismo hilo). Al aprobar, Claude commitea en la rama de Codex.
5. Claude integra la parte visual sobre el contrato y verifica con los guiones con ventana.
6. Claude presenta el resultado al usuario; con su aprobación se fusiona a `main`. El usuario lo prueba antes de fusionar con `sh tools/agentes/probar.sh <worktree>`, que enlaza `node_modules`, importa los recursos y abre el juego.

## Flujo adversarial (features nuevas o complejas): máximo 2 ciclos

Se activa cuando la feature es nueva, cruza núcleo y presentación, o toca algo difícil de revertir (esquema SQL, API de programas JS, formato de guardado).

**Ciclo 1**
1. Codex implementa y entrega resumen.
2. Claude critica de forma adversarial: busca fallos de determinismo, casos borde, violaciones del contrato, deuda técnica. Hallazgos numerados con severidad (`bloqueante` / `importante` / `menor`).

**Ciclo 2**
3. Codex responde punto por punto: corrige o **refuta con evidencia** (prueba, traza, medición). No vale «no estoy de acuerdo» sin evidencia.
4. Claude verifica las correcciones y las refutaciones, y emite un veredicto: `aprobado` / `aprobado con reservas` / `rechazado`.

Reglas:
- **No hay tercer ciclo.** Si tras el ciclo 2 queda un desacuerdo bloqueante, Claude lo resume (posiciones y evidencia de ambos lados) y lo decide el usuario.
- Una refutación con evidencia reproducible gana a una opinión, venga de quien venga, incluido Claude.
- Los desacuerdos de gusto visual los decide Claude; los de corrección técnica los decide la evidencia.

## Compuertas objetivas (antes del juicio)

```bash
cd Concepto2
G=${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}
$G --headless --path . -s pruebas/prueba_sim.gd
$G --headless --path . -s pruebas/prueba_larga.gd
```

Si fallan, no hay revisión: vuelve a Codex. Los guiones con ventana (`guion_controles`, `guion_programas`, `guion_capturas`) los corre Claude o el usuario, porque necesitan pantalla.

## Plantilla de revisión

```
## Revisión de <feature> (rama agente/codex/<feature>)

Compuertas: prueba_sim ✅/❌ · prueba_larga ✅/❌ · prueba nueva ✅/❌/n.a.

Hallazgos
1. [bloqueante|importante|menor] archivo:línea — qué pasa, por qué importa, cómo reproducirlo / qué propongo.
2. ...

Contrato: sin cambios / cambió (y es coherente / rompe a la presentación).
Determinismo: ¿mismo seed ⇒ mismo resultado? cómo lo comprobé.
Veredicto: aprobado / aprobado con reservas / cambios requeridos.
```

## Imágenes y texturas generadas por IA (experimental)

Codex puede generar imágenes. Para este proyecto hay que tratarlo con cuidado:

- El pixel art de naturaleza ya se genera **proceduralmente** (`scripts/mundo/pixel.gd`), que es determinista y consistente. Una imagen generada solo debe usarse donde el procedural no llegue (texturas de referencia, caras de robot, iconos).
- Antes de adoptar una textura: paleta compatible con el resto, resolución múltiplo de 16 px/m, y que pase por la misma tramado/cuantización que el resto del arte.
- Los assets generados se guardan en `assets/` con el prompt usado en un `.md` al lado, para poder reproducirlos.
- Aún no se ha probado si la generación de imágenes está disponible desde `codex exec`; hay que comprobarlo antes de contar con ello.

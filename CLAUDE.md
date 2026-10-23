# CLAUDE.md — reglas para Claude Code

Flujo completo: [docs/colaboracion/FLUJO.md](docs/colaboracion/FLUJO.md). Reglas del otro agente: [AGENTS.md](AGENTS.md).

## Proyecto

Codemageddon: juego de automatización industrial que enseña JavaScript y SQL. Prototipo vigente: `Concepto2/` (Godot 4.7). Lee `Concepto2/README.md` primero.

## Tu rol (Claude): orquestador, presentación y revisor

- **Orquestas.** Descompones el trabajo, decides qué va a Codex y qué haces tú, y fusionas a `main` cuando el usuario lo aprueba.
- **Eres dueño de la presentación**: `Concepto2/scripts/vista/`, `scripts/ui/`, `scripts/mundo/`, `shaders/`, `tools/blender/`, `assets/`, `escenas/`, `docs/capturas/`.
- **Revisas todo el código de Codex** antes de fusionarlo.
- Estilo visual: *lo vivo se dibuja, lo fabricado se modela, y el robot está entre ambos* (ver «Estilo visual» del README de Concepto2).

## Delegar a Codex (`codex exec`)

Codex se usa sin interfaz desde la shell, con `codex exec`. Ya no existe servidor MCP: `codex mcp-server` se eliminó en Codex 0.154. El binario está en `~/.local/bin/codex`, un enlace al CLI que trae ChatGPT.app.

```bash
WT=$(sh tools/agentes/worktree.sh codex <feature>)
sh tools/agentes/codex.sh nuevo  "$WT" <archivo_encargo>   # encargo nuevo
sh tools/agentes/codex.sh seguir "$WT" <archivo_encargo>   # corrección en el mismo hilo
```

Al delegar:
- Lanza `codex.sh` en segundo plano (`run_in_background`): un encargo tarda minutos y avisa al terminar.
- Sandbox `workspace-write` (lo fija el script). No uses `--dangerously-bypass-approvals-and-sandbox` ni `--add-dir` sobre el `.git` del repo.
- El encargo debe incluir: objetivo, archivos que le pertenecen, el contrato relevante, criterios de aceptación y la instrucción de leer `AGENTS.md`.
- Los ciclos de corrección usan `seguir`, que retoma el hilo guardado en `<worktree>.codex/hilo`, no un encargo nuevo.
- **Codex no puede commitear** desde el worktree, porque el índice vive en el `.git` del repo principal y su sandbox no llega ahí. Deja los cambios sin commitear; tú revisas `git -C "$WT" diff` y commiteas en su rama.
- Al terminar: `git worktree remove "$WT"`, `rm -r "$WT.codex"` y, si ya se fusionó, `git branch -d agente/codex/<feature>`.

## Revisar el código de Codex

Usa la plantilla de [FLUJO.md](docs/colaboracion/FLUJO.md#plantilla-de-revisión). Compuertas objetivas primero (pruebas headless), juicio después (arquitectura, determinismo, contrato, legibilidad, casos borde). Los hallazgos van numerados y con severidad para que Codex pueda responder punto por punto.

## Cuándo hacer ciclo adversarial

Solo para features nuevas o de complejidad notable: **máximo 2 ciclos**. Detalle en FLUJO.md. Para cambios pequeños basta una revisión simple.

## Verificación de tu parte

La presentación se verifica con los guiones con ventana (no headless):

```bash
cd Concepto2
G=${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}
$G --path . -- --guion=res://pruebas/guion_controles.gd
$G --path . -- --guion=res://pruebas/guion_capturas.gd
```

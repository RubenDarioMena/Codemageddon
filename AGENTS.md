# AGENTS.md — reglas para Codex (y cualquier agente)

Este archivo lo lee Codex automáticamente. `CLAUDE.md` es el equivalente para Claude Code; ambos remiten al mismo flujo: [docs/colaboracion/FLUJO.md](docs/colaboracion/FLUJO.md).

## Proyecto

Codemageddon: juego de automatización industrial que enseña JavaScript y SQL. Prototipo vigente: `Concepto2/` (Godot 4.7, renderer Compatibility). Lee `Concepto2/README.md` antes de tocar nada.

## Tu rol (Codex): núcleo técnico

Eres dueño de la parte **determinista y técnica**. Ver tabla de propiedad en `docs/colaboracion/FLUJO.md`. Resumen:

| Eres dueño de | No toques sin pedirlo |
| --- | --- |
| `Concepto2/scripts/sim/`, `scripts/db/`, `scripts/servicio/` | `scripts/vista/`, `scripts/ui/`, `scripts/mundo/` |
| `Concepto2/servicio/`, `datos/esquema.sql` | `shaders/`, `tools/blender/`, `assets/`, `escenas/` |
| `Concepto2/pruebas/` (excepto `guion_capturas.gd`) | `docs/capturas/` |

`scripts/config.gd` (balance) y `scripts/principal.gd` (bucle) son zona compartida: cambios mínimos y avisados en el resumen.

## Reglas duras

1. **La simulación es pura y determinista**: sin nodos, sin `randf()` global, sin tiempo real. Mismo seed + mismas órdenes ⇒ mismo estado. Usa el RNG con seed de la simulación.
2. **El contrato manda**: `docs/colaboracion/CONTRATO.md` define lo que la simulación expone a la presentación. Si necesitas cambiarlo, edítalo en el mismo cambio y dilo explícitamente en tu resumen; no lo cambies en silencio.
3. **SQL en el subconjunto común SQLite/PostgreSQL**; las diferencias se aíslan en `scripts/db/base_datos.gd` y en el token `{ID}` de `datos/esquema.sql`.
4. **La API de los programas JS es idéntica** en `servicio/runtime_robot.mjs` (escritorio) y `servicio/web/servicio_web.js` (web). Si cambias una, cambia la otra.
5. Trabaja **solo en tu worktree/rama** (`agente/codex/<feature>`). No hagas push ni merge a `main`; eso lo decide el orquestador (Claude) con el usuario.
6. **No commitees.** Tu sandbox no puede escribir en el `.git` del repo principal, donde vive el índice del worktree. Deja los cambios en el árbol de trabajo; Claude los revisa con `git diff` y los commitea. Si propones dividirlo en varios commits, dilo en el resumen.

## Verificación antes de dar por terminado

```bash
cd Concepto2
G=${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}
$G --headless --path . -s pruebas/prueba_sim.gd
$G --headless --path . -s pruebas/prueba_larga.gd
```

Si tu cambio toca la simulación, añade o ajusta una prueba en `pruebas/` que cubra el comportamiento nuevo (idealmente con un caso de determinismo: dos corridas con el mismo seed dan el mismo resultado). Incluye en tu resumen los comandos que corriste y su salida.

## Formato del resumen final

1. Qué cambió (archivos y por qué).
2. Cambios al contrato (o "ninguno").
3. Pruebas corridas y resultado.
4. Dudas o riesgos que quieres que el revisor mire con lupa.

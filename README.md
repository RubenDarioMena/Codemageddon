# Codemageddon

Juego de automatización industrial para aprender a programar y a trabajar con bases de datos: programas robots en **JavaScript**, monitoreas tu fábrica con **PostgreSQL** y gestionas una ciudad que compra tus circuitos… y se queja de tu humo.

## ▶ Demo web: **https://codemageddon-demo.vercel.app**

Funciona en el navegador (Chrome o Edge recomendados; la primera carga son unos 67 MB). Incluye los programas JavaScript de los robots y PostgreSQL (PGlite) corriendo dentro de tu navegador. Pulsa **F1** para ver los controles y sigue el panel de **objetivos**.

Vercel publica la carpeta `demo/` en cada push a `main`. Para actualizarla, ejecuta `sh Concepto2/tools/exportar_web.sh` y sube el cambio.

La demo de pruebas incluye el laboratorio de jugabilidad (**F12**). La exportación pasa `--dev` al juego; para una versión sin devtools usa `CMG_DEVTOOLS_WEB=0 sh Concepto2/tools/exportar_web.sh`. Los paquetes llevan el identificador de la revisión para evitar mezclas de versiones en caché; `version.json` identifica el código y la huella del paquete publicado.

| Carpeta | Qué es |
| --- | --- |
| [Concepto2/](Concepto2/README.md) | Prototipo actual en **Godot 4.7**: controles estilo AoE2, construcción, robots T0–T2, programas JS, PostgreSQL (PGlite), ciudad con logit anidado. |
| [demo/](demo/) | Exportación web de Concepto 2 (estática, lista para Vercel). Se genera con `Concepto2/tools/exportar_web.sh`. |
| [Concepto1/](Concepto1/README.md) | Primera maqueta en Three.js para fijar el estilo visual híbrido (pixel art + 3D). |
| [Concepto2/docs/JEV.md](Concepto2/docs/JEV.md) | Análisis: ¿usar Jev (TypeSafe AI) para las decisiones del juego? |

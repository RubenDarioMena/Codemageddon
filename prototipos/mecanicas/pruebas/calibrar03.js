// Juega cada estrategia de un JSON con varias semillas y resume victorias, atascos y ₵ por derribo.
// Uso: node calibrar03.js calibracion03.json
const { abrir } = require('./comun');
const fs = require('fs');

(async () => {
  const casos = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
  const { b, p, errores } = await abrir('03_lanzamisiles.html');
  for (const c of casos) {
    const filas = [];
    for (const s of c.semillas) {
      await p.evaluate(({ c, s }) => {
        __banco.elegirReto(c.reto - 1);
        for (const [id, t] of Object.entries(c.programas)) __banco.programas[id] = t;
        __banco.fijarSemilla(s); __banco.turbo(25); __banco.ejecutar();
      }, { c, s });
      await p.waitForFunction(() => __banco.mundo.fin != null, null, { timeout: 120000 });
      filas.push(await p.evaluate(() => __banco.telemetria.at(-1)));
    }
    const v = filas.filter(r => r.resultado === 'victoria').length;
    console.log(`reto ${c.reto} · ${c.nombre.padEnd(30)} ${v}/${filas.length} victorias · brechas ${filas.map(r => r.brechas).join(' ')} · atascos ${filas.map(r => r.atascos).join(' ')}`);
  }
  if (errores.length) console.log('Errores:', errores);
  await b.close();
})();

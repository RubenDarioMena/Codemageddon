// Pruebas de lógica sin DOM ni dependencias: node Concept-HTML/juego/pruebas/interaccion.cjs
const { readFileSync } = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const src = readFileSync(require('node:path').join(__dirname, '../js/juego.js'), 'utf8');
const bloque = (inicio, fin) => src.slice(src.indexOf(inicio), src.indexOf(fin, src.indexOf(inicio)));
const ctx = vm.createContext({ console, Set, Map, Object, Promise });
vm.runInContext(`
const RE_ID = /[A-Za-z_$][\\w$]*/y, RE_NUM = /0x[0-9a-f]+|\\d*\\.?\\d+(?:e[+-]?\\d+)?/iy;
let $codigo = {value:''};
${bloque('  function lexico(src)', '  // Vecino significativo')}
${bloque('  function rangoCodigo(pos, triple)', '  $codigo.addEventListener("mousedown"')}
let ejec = null, edicion = {ids:['A','B'],mixto:true}, programas = {A:'uno();',B:'dos();'}, aplicandoMulti = false;
let aceptado = true, guardados = 0, refrescos = 0;
const confirmarReemplazo = async () => aceptado;
const guardarProgramas = () => guardados++;
const configurarEdicion = () => refrescos++;
const pintarInspector = () => {};
${bloque('  async function aplicarMulti(reemplazar)', '  $("b-add").addEventListener')}
`, ctx);
const run = code => vm.runInContext(code, ctx);
const selection = (text, pos, triple) => {
  ctx.textoPrueba = text;
  return JSON.parse(run(`$codigo.value=textoPrueba; JSON.stringify(rangoCodigo(${pos},${triple}))`));
};
let checks = 0;
function eq(actual, expected) { assert.deepEqual(actual, expected); checks++; }
(async () => {
  const text = 'fn({a: [1, (2)], b: "]" /* } */})';
  for (const [a,b] of [[0,text.length-1],[3,text.length-2],[7,14],[11,13]]) {
    // El par exterior de fn empieza después del identificador.
    const apertura = a === 0 ? 2 : a;
    eq(selection(text, apertura, true), [apertura+1,b]);
    eq(selection(text,b,true), [apertura+1,b]);
  }
  eq(selection('fn("crawler", "visual")', 6, false), [3,12]);
  eq(selection("fn('a\\'b')", 6, false), [3,9]);
  eq(selection('fn("", `x`)', 3, false), [3,5]);
  eq(selection('/* [ ] */ x', 3, true), null);
  run('$codigo.value="nuevo();"');
  await run('aplicarMulti(false)');
  eq(JSON.parse(run('JSON.stringify(programas)')), {A:'uno();\nnuevo();',B:'dos();\nnuevo();'});
  eq(run('guardados'), 1);
  run('aceptado=false; $codigo.value="reemplazo();"');
  await run('aplicarMulti(true)');
  eq(run('programas.A'), 'uno();\nnuevo();');
  eq(run('guardados'), 1);
  run('aceptado=true'); await run('aplicarMulti(true)');
  eq(JSON.parse(run('JSON.stringify(programas)')), {A:'reemplazo();',B:'reemplazo();'});
  run('ejec={}; $codigo.value="no"'); await run('aplicarMulti(false)');
  eq(run('programas.A'), 'reemplazo();');
  run('ejec=null; edicion.mixto=false'); await run('aplicarMulti(true)');
  eq(run('programas.A'), 'reemplazo();');
  console.log(`${checks} comprobaciones correctas`);
})().catch(e => { console.error(e); process.exitCode=1; });

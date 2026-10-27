// Abre un banco en Chromium sin ventana. Con LIBS=<carpeta> las librerías de CDN se sirven desde
// <carpeta>/three.min.js y <carpeta>/acorn.js (útil sin red); sin LIBS se cargan de internet.
const { chromium } = require('playwright');
const path = require('path');

async function abrir(archivo, { ancho = 1360, alto = 1000 } = {}) {
  const b = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
  const p = await (await b.newContext({ viewport: { width: ancho, height: alto } })).newPage();
  const errores = [];
  p.on('pageerror', e => errores.push('pageerror: ' + e.message));
  p.on('console', m => { if (m.type() === 'error') errores.push('console: ' + m.text()); });
  if (process.env.LIBS) {
    await p.route('https://cdnjs.cloudflare.com/**', r => r.fulfill({ path: path.join(process.env.LIBS, 'three.min.js'), contentType: 'text/javascript' }));
    await p.route('https://cdn.jsdelivr.net/**', r => r.fulfill({ path: path.join(process.env.LIBS, 'acorn.js'), contentType: 'text/javascript' }));
    await p.route('https://fonts.googleapis.com/**', r => r.fulfill({ body: '', contentType: 'text/css' }));
  }
  await p.goto('file://' + path.resolve(__dirname, '..', archivo));
  await p.waitForTimeout(600);
  return { b, p, errores };
}
module.exports = { abrir };

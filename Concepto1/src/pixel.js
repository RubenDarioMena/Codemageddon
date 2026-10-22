// Pixel art procedural: paleta, sprites de naturaleza y VFX, atlas y fuente diminuta.
// Densidad común: 16 píxeles por metro (1 casilla = 1 m = 16 px). Luz desde arriba a la izquierda.
import { mulberry32, valueNoise, bayer } from './rng.js';

export const PPM = 16;

export const PAL = {
  aguaProf: '#24477e', agua: '#34679f', aguaClara: '#4f8fc4', espuma: '#a9dcf2',
  arena0: '#bfa56c', arena1: '#d9c38a',
  pasto0: '#2b5f35', pasto1: '#36743d', pasto2: '#4a8c45', pasto3: '#6aa84f', pasto4: '#8fc463',
  pisado0: '#5d6b3b', pisado1: '#73784a',
  tierra0: '#5c4130', tierra1: '#7a573a', tierra2: '#977149',
  seco0: '#6b6a4e', seco1: '#858160', seco2: '#9c9672', ceniza: '#585852',
  hoja0: '#173d29', hoja1: '#245a33', hoja2: '#3a7d3c', hoja3: '#5fa449', hoja4: '#9fd36a',
  tronco0: '#3a281c', tronco1: '#5a3c27', tronco2: '#7a5536',
  roca0: '#3a3e4c', roca1: '#565b6c', roca2: '#7d8396', roca3: '#adb3c4',
  cobre0: '#7c3519', cobre1: '#c25f2a', cobre2: '#ee9550', cobre3: '#ffd7a0',
  contorno: '#10201a',
  humo0: '#7d8896', humo1: '#b3bdc8', humo2: '#e4eaf0',
  polvo0: '#8f7754', polvo1: '#bfa47a',
  chispa0: '#ff9d2e', chispa1: '#fff2a8',
  cian: '#59f0ff', cianOsc: '#1b6f80',
};

export function rgb(hex) {
  const n = parseInt(hex.slice(1), 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

class Lienzo {
  constructor(w, h) {
    this.w = w; this.h = h;
    this.px = new Array(w * h).fill(null);
  }
  set(x, y, c) { if (x >= 0 && y >= 0 && x < this.w && y < this.h) this.px[y * this.w + x] = c; }
  get(x, y) { return (x >= 0 && y >= 0 && x < this.w && y < this.h) ? this.px[y * this.w + x] : null; }
  // Contorno exterior de 1 px (vecindad 4), estilo «sprite» clásico.
  contorno(color = PAL.contorno) {
    const marca = [];
    for (let y = 0; y < this.h; y++) for (let x = 0; x < this.w; x++) {
      if (this.get(x, y)) continue;
      if (this.get(x - 1, y) || this.get(x + 1, y) || this.get(x, y - 1) || this.get(x, y + 1)) marca.push([x, y]);
    }
    for (const [x, y] of marca) this.set(x, y, color);
    return this;
  }
  dibujar(ctx, ox, oy) {
    for (let y = 0; y < this.h; y++) for (let x = 0; x < this.w; x++) {
      const c = this.px[y * this.w + x];
      if (!c) continue;
      ctx.fillStyle = c;
      ctx.fillRect(ox + x, oy + y, 1, 1);
    }
  }
}

// Elige un tono de una rampa según luz 0..1, con tramado de Bayer en las fronteras.
function rampa(colores, luz, x, y, fuerza = 0.7) {
  const v = luz * colores.length + (bayer(x, y) - 0.5) * fuerza;
  return colores[Math.max(0, Math.min(colores.length - 1, Math.floor(v)))];
}

const HOJAS = [PAL.hoja0, PAL.hoja1, PAL.hoja2, PAL.hoja3, PAL.hoja4];
const ROCAS = [PAL.roca0, PAL.roca1, PAL.roca2, PAL.roca3];
const COBRE = [PAL.cobre0, PAL.cobre1, PAL.cobre2, PAL.cobre3];

function tronco(L, cx, y0, y1, ancho = 3) {
  for (let y = y0; y <= y1; y++) for (let i = 0; i < ancho; i++) {
    const x = cx - (ancho >> 1) + i;
    L.set(x, y, i === 0 ? PAL.tronco2 : i === ancho - 1 ? PAL.tronco0 : PAL.tronco1);
  }
  L.set(cx - (ancho >> 1) - 1, y1, PAL.tronco1);
  L.set(cx + (ancho >> 1) + 1, y1, PAL.tronco0);
}

export function pino(seed) {
  const r = mulberry32(seed);
  const w = 24, h = 48, cx = 12, L = new Lienzo(w, h);
  tronco(L, cx, h - 9, h - 2, 3);
  const pisos = 4;
  for (let i = 0; i < pisos; i++) {
    const y0 = 2 + i * 9, y1 = y0 + 13, hwMax = 3 + i * 2.4 + r() * 1.2;
    for (let y = y0; y <= y1; y++) {
      const t = (y - y0) / (y1 - y0);
      const hw = Math.round(t * hwMax);
      for (let x = cx - hw; x <= cx + hw; x++) {
        if (y === y1 && (x + i) % 3 === 0) continue; // borde inferior dentado
        const rx = (x - cx) / (hw + 1);
        const luz = 0.62 - rx * 0.42 - t * 0.28 + (valueNoise(x * 0.7, y * 0.7, seed) - 0.5) * 0.3;
        L.set(x, y, rampa(HOJAS.slice(0, 4), luz, x, y));
      }
    }
  }
  L.set(cx, 1, PAL.hoja3); L.set(cx, 2, PAL.hoja4);
  return L.contorno();
}

function copa(L, blobs, seed, paleta = HOJAS, base = 0.55) {
  for (let y = 0; y < L.h; y++) for (let x = 0; x < L.w; x++) {
    let mejor = null, f = 0;
    for (const b of blobs) {
      const dx = (x + 0.5 - b.x) / b.r, dy = (y + 0.5 - b.y) / b.r;
      const d = dx * dx + dy * dy;
      if (d < 1 && 1 - d > f) { f = 1 - d; mejor = { dx, dy }; }
    }
    if (!mejor) continue;
    const luz = base - mejor.dx * 0.32 - mejor.dy * 0.4 + f * 0.15 + (valueNoise(x * 0.9, y * 0.9, seed) - 0.5) * 0.35;
    L.set(x, y, rampa(paleta, luz, x, y));
  }
}

export function arbol(seed) {
  const r = mulberry32(seed);
  const w = 34, h = 40, L = new Lienzo(w, h);
  tronco(L, 17, 24, h - 2, 4);
  const blobs = [{ x: 17, y: 14, r: 10 }];
  for (let i = 0; i < 5; i++) blobs.push({ x: 9 + r() * 16, y: 8 + r() * 14, r: 5 + r() * 4 });
  copa(L, blobs, seed);
  return L.contorno();
}

export function arbusto(seed) {
  const r = mulberry32(seed);
  const L = new Lienzo(16, 11);
  const blobs = [{ x: 8, y: 7, r: 5 }, { x: 4 + r() * 3, y: 6.5, r: 3.5 }, { x: 10 + r() * 2, y: 6, r: 3.8 }];
  copa(L, blobs, seed, HOJAS, 0.6);
  if (r() < 0.5) for (let i = 0; i < 3; i++) L.set(3 + ((r() * 10) | 0), 3 + ((r() * 5) | 0), '#e2504c');
  return L.contorno();
}

export function pasto(seed) {
  const r = mulberry32(seed);
  const L = new Lienzo(9, 7);
  const n = 3 + ((r() * 3) | 0);
  for (let i = 0; i < n; i++) {
    const x0 = 1 + ((r() * 7) | 0), alto = 3 + ((r() * 4) | 0), inclin = r() < 0.5 ? -1 : 1;
    for (let k = 0; k < alto; k++) {
      const x = x0 + (k > alto * 0.6 ? inclin : 0);
      L.set(x, 6 - k, k > alto - 2 ? PAL.pasto4 : k > 1 ? PAL.pasto3 : PAL.pasto1);
    }
  }
  return L;
}

export function flores(seed) {
  const r = mulberry32(seed);
  const L = new Lienzo(8, 6);
  const col = ['#e2504c', '#f4d35e', '#f2efe6', '#b48ae0'][(r() * 4) | 0];
  for (let i = 0; i < 3; i++) {
    const x = 1 + ((r() * 6) | 0), y = 1 + ((r() * 2) | 0);
    L.set(x, y + 1, PAL.pasto2); L.set(x, y + 2, PAL.pasto1);
    L.set(x, y, col);
  }
  return L;
}

function rocaBase(L, cx, cy, rx, ry, seed) {
  for (let y = 0; y < L.h; y++) for (let x = 0; x < L.w; x++) {
    const dx = (x + 0.5 - cx) / rx, dy = (y + 0.5 - cy) / ry;
    if (dx * dx + dy * dy > 1 || y > cy + ry * 0.55) continue;
    const luz = 0.6 - dx * 0.35 - dy * 0.45 + (valueNoise(x * 0.8, y * 0.8, seed) - 0.5) * 0.3;
    L.set(x, y, rampa(ROCAS, luz, x, y));
  }
}

export function roca(seed) {
  const r = mulberry32(seed);
  const L = new Lienzo(15, 11);
  rocaBase(L, 7.5, 7, 6.5 + r(), 5.5, seed);
  for (let i = 0; i < 3; i++) L.set(5 + i + ((r() * 2) | 0), 4 + i, PAL.roca0);
  return L.contorno();
}

// Mena de cobre en 4 fases: 3 cristales, 2, 1 y escombro (agotada).
export function cobre(seed) {
  const r = mulberry32(seed);
  const cristales = [];
  for (let i = 0; i < 3; i++) cristales.push({ x: 4 + i * 4 + ((r() * 2) | 0), y: 6 + ((r() * 2) | 0), alto: 4 + ((r() * 3) | 0) });
  const fases = [];
  for (let f = 0; f < 4; f++) {
    const L = new Lienzo(19, 15);
    if (f < 3) rocaBase(L, 9.5, 10, 8, 5.5, seed);
    else rocaBase(L, 9.5, 11.5, 5.5, 3.5, seed);
    for (const c of cristales.slice(0, 3 - f)) {
      for (let k = 0; k < c.alto; k++) {
        const ancho = k < c.alto - 1 ? 1 : 0;
        for (let dx = -ancho; dx <= ancho; dx++) {
          const col = dx < 0 ? PAL.cobre3 : dx > 0 ? PAL.cobre1 : (k > c.alto - 3 ? PAL.cobre3 : PAL.cobre2);
          L.set(c.x + dx, c.y + 2 - k, col);
        }
      }
      L.set(c.x - 1, c.y + 3, PAL.cobre0); L.set(c.x + 1, c.y + 3, PAL.cobre0);
    }
    fases.push(L.contorno());
  }
  return fases;
}

export function mena() {
  const L = new Lienzo(8, 7);
  rocaBase(L, 4, 4.2, 3.6, 3.2, 3);
  L.set(3, 2, PAL.cobre3); L.set(4, 2, PAL.cobre2); L.set(4, 3, PAL.cobre1); L.set(3, 3, PAL.cobre2);
  return L.contorno();
}

function bocanada(colores, n) {
  const L = new Lienzo(n * 2 + 2, n * 2 + 2);
  const c = n + 1;
  for (let y = 0; y < L.h; y++) for (let x = 0; x < L.w; x++) {
    const dx = (x + 0.5 - c) / n, dy = (y + 0.5 - c) / n;
    if (dx * dx + dy * dy > 1) continue;
    L.set(x, y, rampa(colores, 0.55 - dx * 0.35 - dy * 0.45, x, y, 0.9));
  }
  return L;
}

export function humo() { return [2, 3, 4, 5, 6].map(n => bocanada([PAL.humo0, PAL.humo1, PAL.humo2], n)); }
export function polvo() { return [1, 2, 3].map(n => bocanada([PAL.polvo0, PAL.polvo1], n)); }

export function chispa() {
  const a = new Lienzo(3, 3);
  a.set(1, 0, PAL.chispa0); a.set(0, 1, PAL.chispa0); a.set(2, 1, PAL.chispa0); a.set(1, 2, PAL.chispa0); a.set(1, 1, PAL.chispa1);
  const b = new Lienzo(3, 3); b.set(1, 1, PAL.chispa1);
  return [a, b];
}

export function destello() {
  const L = new Lienzo(7, 7);
  for (let i = 0; i < 7; i++) { L.set(3, i, PAL.cian); L.set(i, 3, PAL.cian); }
  L.set(3, 3, '#ffffff'); L.set(2, 2, PAL.espuma); L.set(4, 4, PAL.espuma); L.set(2, 4, PAL.espuma); L.set(4, 2, PAL.espuma);
  return L;
}

// Empaquetado en estantes. Devuelve el lienzo y rectángulos en UV (flipY de Three.js).
export function crearAtlas(entradas, tam = 512) {
  const canvas = document.createElement('canvas');
  canvas.width = canvas.height = tam;
  const ctx = canvas.getContext('2d');
  const orden = [...entradas].sort((a, b) => b.lienzo.h - a.lienzo.h);
  let x = 1, y = 1, altoFila = 0;
  const rects = {};
  for (const e of orden) {
    const { w, h } = e.lienzo;
    if (x + w + 2 > tam) { x = 1; y += altoFila + 2; altoFila = 0; }
    if (y + h + 1 > tam) throw new Error('Atlas lleno');
    e.lienzo.dibujar(ctx, x, y);
    rects[e.nombre] = { w, h, uv: [x / tam, 1 - (y + h) / tam, (x + w) / tam, 1 - y / tam] };
    x += w + 2;
    altoFila = Math.max(altoFila, h);
  }
  return { canvas, rects };
}

// Fuente de 3x5 para identificadores de robots.
const GLIFOS = {
  0: '111101101101111', 1: '010110010010111', 2: '111001111100111', 3: '111001111001111',
  4: '101101111001001', 5: '111100111001111', 6: '111100111101111', 7: '111001010010010',
  8: '111101111101111', 9: '111101111001111', R: '110101110101101',
};
export function texto3x5(ctx, texto, x, y, color) {
  ctx.fillStyle = color;
  [...texto].forEach((ch, i) => {
    const g = GLIFOS[ch];
    if (!g) return;
    for (let k = 0; k < 15; k++) if (g[k] === '1') ctx.fillRect(x + i * 4 + (k % 3), y + ((k / 3) | 0), 1, 1);
  });
}

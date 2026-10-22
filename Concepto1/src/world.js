// Mundo natural: terreno pixel art generado con semilla, colocación de flora y menas,
// sombras horneadas a píxel y un suelo que reacciona (caminos por desgaste, contaminación).
import * as THREE from 'three';
import { fbm, valueNoise, hash2, bayer, mulberry32 } from './rng.js';
import { PAL, PPM, rgb } from './pixel.js';

export const MAPA = 64;
export const MITAD = MAPA / 2;
const RES = MAPA * PPM;

// Zonas ocupadas por la industria (coordenadas de mundo, metros).
export const ZONAS = {
  fabrica: { x0: -1.5, x1: 14, z0: -6, z1: 6 },
  ciudad: { x0: 19, x1: 31, z0: -9, z1: 9 },
  cinta: { x0: 14, x1: 19, z0: -0.8, z1: 0.8 },
  muelle: { x0: -5.4, x1: -2.2, z0: 3.2, z1: 6.4 },
};
export const DESCARGA = { x: -2.7, z: 0 };

const C = Object.fromEntries(Object.entries(PAL).map(([k, v]) => [k, rgb(v)]));
const PASTOS = [C.pasto0, C.pasto1, C.pasto2, C.pasto3];
const AGUA = 2, ARENA = 1, PASTO = 0, TIERRA = 3;

function distRect(x, z, r) {
  const dx = Math.max(r.x0 - x, 0, x - r.x1), dz = Math.max(r.z0 - z, 0, z - r.z1);
  return Math.hypot(dx, dz);
}
const LISTA_ZONAS = Object.values(ZONAS);
function distZonas(x, z) {
  let m = Infinity;
  for (const r of LISTA_ZONAS) m = Math.min(m, distRect(x, z, r));
  return m;
}

function distSegmento(px, pz, ax, az, bx, bz) {
  const vx = bx - ax, vz = bz - az;
  const t = Math.max(0, Math.min(1, ((px - ax) * vx + (pz - az) * vz) / (vx * vx + vz * vz)));
  return Math.hypot(px - ax - vx * t, pz - az - vz * t);
}

export class Mundo {
  constructor(seed = 7) {
    this.seed = seed;
    const n = RES * RES;
    this.data = new Uint8Array(n * 4);
    this.base = new Uint8Array(n * 3);
    this.bioma = new Uint8Array(n);
    this.prof = new Float32Array(n);
    this.desgaste = new Uint8Array(n);
    this.contam = new Uint8Array(n);
    this.sombra = new Uint8Array(n);
    this.agua = [];
    this.menas = [];
    this.flora = [];
    this.nivelContam = 0;
    this.generarTerreno();
    this.colocarMenas();
    this.colocarFlora();
    for (let i = 0; i < n; i++) this.pintar(i);
    this.textura = new THREE.DataTexture(this.data, RES, RES, THREE.RGBAFormat);
    this.textura.colorSpace = THREE.SRGBColorSpace;
    this.textura.magFilter = this.textura.minFilter = THREE.NearestFilter;
    this.textura.generateMipmaps = false;
    this.textura.needsUpdate = true;
    this.sucio = false;
  }

  // Columna/fila del texel. La fila 0 es z = +MITAD (así cae la DataTexture en el plano).
  texel(x, z) {
    const c = Math.floor((x + MITAD) * PPM), r = Math.floor((MITAD - z) * PPM);
    if (c < 0 || r < 0 || c >= RES || r >= RES) return -1;
    return r * RES + c;
  }
  esAgua(x, z, conArena = true) { const i = this.texel(x, z); return i < 0 || this.bioma[i] === AGUA || (conArena && this.bioma[i] === ARENA); }

  generarTerreno() {
    const s = this.seed;
    for (let r = 0; r < RES; r++) for (let c = 0; c < RES; c++) {
      const i = r * RES + c;
      const x = -MITAD + (c + 0.5) / PPM, z = MITAD - (r + 0.5) / PPM;
      const dz = distZonas(x, z);
      let w = fbm(x * 0.045, z * 0.045, s + 1) + Math.max(0, valueNoise(x * 0.02, z * 0.02, s + 9) - 0.5) * 0.4;
      w -= Math.max(0, 9 - dz) * 0.045 + Math.max(0, 12 - Math.hypot(x - DESCARGA.x, z - DESCARGA.z)) * 0.03;
      const d = bayer(c, r);
      let col, bioma = PASTO;
      if (w + (d - 0.5) * 0.012 > 0.655) {
        bioma = AGUA;
        this.prof[i] = w;
        col = w > 0.72 ? C.aguaProf : w > 0.68 ? C.agua : C.aguaClara;
        this.agua.push(i);
      } else if (w + (d - 0.5) * 0.02 > 0.625) {
        bioma = ARENA;
        col = (w > 0.64 || hash2(c, r, s) < 0.15) ? C.arena0 : C.arena1;
      } else if (dz < 1.1 + valueNoise(x * 0.8, z * 0.8, s + 4) * 1.4) {
        bioma = TIERRA; // tierra removida alrededor de las obras
        col = d < 0.35 ? C.tierra1 : d < 0.8 ? C.tierra2 : C.pisado1;
      } else {
        const bosque = fbm(x * 0.06, z * 0.06, s + 2);
        const tono = fbm(x * 0.2, z * 0.2, s + 3) * 0.75 + valueNoise(x * 1.1, z * 1.1, s + 5) * 0.25 - Math.max(0, bosque - 0.55) * 0.9;
        const v = tono * 4.6 - 1.1 + (d - 0.5) * 0.9;
        col = PASTOS[Math.max(0, Math.min(3, Math.floor(v)))];
      }
      this.bioma[i] = bioma;
      this.base.set(col, i * 3);
    }
    // Briznas: 1 px claro sobre 1 px oscuro, el detalle mínimo que lee como «pasto».
    for (let r = 1; r < RES; r++) for (let c = 0; c < RES; c++) {
      const i = r * RES + c;
      if (this.bioma[i] !== PASTO || this.bioma[i - RES] !== PASTO) continue;
      if (hash2(c, r, s + 11) < 0.03) { this.base.set(C.pasto4, (i - RES) * 3); this.base.set(C.pasto1, i * 3); }
    }
  }

  colocarMenas() {
    const rnd = mulberry32(this.seed * 31);
    const p = ZONAS.fabrica, margen = { x0: p.x0 - 0.6, x1: p.x1 + 0.6, z0: p.z0 - 0.6, z1: p.z1 + 0.6 };
    const rutaLibre = (x, z) => {
      for (let t = 0; t <= 1; t += 0.03) {
        const qx = x + (DESCARGA.x - x) * t, qz = z + (DESCARGA.z - z) * t;
        if (this.esAgua(qx, qz, false) || distRect(qx, qz, margen) === 0 || distRect(qx, qz, ZONAS.muelle) === 0) return false;
      }
      return true;
    };
    let intentos = 0, grupos = 0;
    while (grupos < 10 && intentos++ < 800) {
      const ang = rnd() * Math.PI * 2, rad = 7 + rnd() * 21;
      const gx = DESCARGA.x + Math.cos(ang) * rad, gz = Math.sin(ang) * rad;
      if (Math.abs(gx) > MITAD - 3 || Math.abs(gz) > MITAD - 3 || distZonas(gx, gz) < 3) continue;
      const nuevas = [];
      for (let k = 0; k < 3; k++) {
        const x = gx + (rnd() - 0.5) * 3.4, z = gz + (rnd() - 0.5) * 3.4;
        if (!rutaLibre(x, z) || distZonas(x, z) < 2.5) continue;
        if ([...this.menas, ...nuevas].some(m => Math.hypot(m.x - x, m.z - z) < 1.4)) continue;
        nuevas.push({ x, z });
      }
      if (nuevas.length < 2) continue;
      this.menas.push(...nuevas);
      grupos++;
    }
    this.menas.forEach((m, i) => { m.id = i + 1; m.variante = i % 3; this.hornearSombra(m.x, m.z, 0.6, 0.3); });
  }

  colocarFlora() {
    const rnd = mulberry32(this.seed * 57);
    const paso = 1.15;
    const rutas = this.menas.map(m => [m.x, m.z, DESCARGA.x, DESCARGA.z]);
    const enRuta = (x, z, d) => rutas.some(s => distSegmento(x, z, ...s) < d);
    for (let gz = -MITAD + 1; gz < MITAD - 0.5; gz += paso) for (let gx = -MITAD + 1; gx < MITAD - 0.5; gx += paso) {
      const x = gx + (rnd() - 0.5) * paso * 0.9, z = gz + (rnd() - 0.5) * paso * 0.9;
      if (this.esAgua(x, z)) continue;
      const dz = distZonas(x, z);
      if (dz < 1.2) continue;
      const bosque = fbm(x * 0.06, z * 0.06, this.seed + 2);
      const cercaMena = this.menas.some(m => Math.hypot(m.x - x, m.z - z) < 1.5);
      const libre = !enRuta(x, z, 1.25) && !cercaMena && dz > 2.2;
      const u = rnd();
      let tipo = null;
      if (bosque > 0.58) tipo = libre && u < 0.6 ? (bosque > 0.66 || rnd() < 0.4 ? 'pino' : 'arbol') : u < 0.8 ? 'pasto' : null;
      else if (bosque > 0.47) tipo = libre && u < 0.13 ? 'arbol' : libre && u < 0.3 ? 'arbusto' : u < 0.55 ? 'pasto' : null;
      else tipo = u < 0.36 ? 'pasto' : u < 0.43 ? 'flores' : libre && u < 0.47 ? 'arbusto' : libre && u < 0.49 ? 'roca' : null;
      if (!tipo) continue;
      this.flora.push({ tipo, x, z, variante: (rnd() * 4) | 0 });
      if (tipo === 'pino') this.hornearSombra(x, z, 0.85, 0.4);
      else if (tipo === 'arbol') this.hornearSombra(x, z, 1.15, 0.5);
      else if (tipo === 'arbusto' || tipo === 'roca') this.hornearSombra(x, z, 0.5, 0.22);
    }
  }

  // Sombra elíptica tramada, desplazada hacia abajo-derecha (sol arriba-izquierda).
  hornearSombra(x, z, rx, rz) {
    const cx = x + rx * 0.35, cz = z + rz * 0.5;
    for (let zz = cz - rz; zz <= cz + rz; zz += 1 / PPM) for (let xx = cx - rx; xx <= cx + rx; xx += 1 / PPM) {
      const i = this.texel(xx, zz);
      if (i < 0 || this.bioma[i] === AGUA) continue;
      const dx = (xx - cx) / rx, dzz = (zz - cz) / rz, d = dx * dx + dzz * dzz;
      if (d < 1 - bayer(i % RES, (i / RES) | 0) * 0.35) this.sombra[i] = 1;
    }
  }

  pintar(i) {
    let col;
    const b = this.bioma[i];
    if (b === AGUA) {
      col = [this.base[i * 3], this.base[i * 3 + 1], this.base[i * 3 + 2]];
    } else {
      const c = i % RES, r = (i / RES) | 0, d = bayer(c, r);
      const w = this.desgaste[i];
      if (w >= 40) col = d < 0.5 ? C.tierra1 : C.tierra0;
      else if (w >= 16) col = d < 0.6 ? C.tierra2 : C.tierra1;
      else if (w >= 6) col = d < 0.5 ? C.pisado0 : C.pisado1;
      else if (this.contam[i]) col = this.contam[i] > 2 ? (d < 0.4 ? C.ceniza : C.seco0) : (d < 0.5 ? C.seco1 : this.contam[i] > 1 ? C.seco0 : C.seco2);
      else col = [this.base[i * 3], this.base[i * 3 + 1], this.base[i * 3 + 2]];
    }
    const o = i * 4;
    if (this.sombra[i]) {
      this.data[o] = col[0] * 0.58; this.data[o + 1] = col[1] * 0.66; this.data[o + 2] = Math.min(255, col[2] * 0.8 + 10);
    } else {
      this.data[o] = col[0]; this.data[o + 1] = col[1]; this.data[o + 2] = col[2];
    }
    this.data[o + 3] = 255;
  }

  // Desgaste por orugas: el camino aparece donde los robots pasan una y otra vez.
  pisar(x, z) {
    const i = this.texel(x, z);
    if (i < 0) return;
    for (const j of [i, i + 1, i + RES, i + RES + 1]) {
      if (j >= this.desgaste.length || this.bioma[j] === AGUA) continue;
      const antes = this.desgaste[j];
      if (antes < 255) this.desgaste[j] = antes + 1;
      if (antes === 5 || antes === 15 || antes === 39) { this.pintar(j); this.sucio = true; }
    }
  }

  // Cada chip fabricado degrada un poco el entorno de la fábrica.
  contaminar(nivel) {
    if (nivel === this.nivelContam) return;
    this.nivelContam = nivel;
    const R = Math.min(10, 1 + Math.sqrt(nivel) * 0.75);
    const p = ZONAS.fabrica;
    const s = this.seed;
    for (let z = p.z0 - R - 2; z <= p.z1 + R + 2; z += 1 / PPM) for (let x = p.x0 - R - 2; x <= p.x1 + R + 2; x += 1 / PPM) {
      const i = this.texel(x, z);
      if (i < 0 || this.bioma[i] === AGUA) continue;
      const d = distRect(x, z, p) + (valueNoise(x * 0.5, z * 0.5, s + 21) - 0.5) * 3;
      const nv = d < R * 0.35 ? 3 : d < R * 0.7 ? 2 : d < R ? 1 : 0;
      if (nv > this.contam[i]) { this.contam[i] = nv; this.pintar(i); this.sucio = true; }
    }
  }

  // Agua animada: destellos y espuma por ciclo de paleta, cuantizados a ~4 fps.
  animarAgua(t) {
    const fase = Math.floor(t * 4);
    if (fase === this.faseAgua) return;
    this.faseAgua = fase;
    for (const i of this.agua) {
      const c = i % RES, r = (i / RES) | 0, o = i * 4;
      const h = hash2(c >> 1, r, fase);
      const brillo = this.prof[i] < 0.7 && h < 0.004;
      const col = brillo ? C.espuma : (h < 0.03 && this.prof[i] > 0.68) ? C.agua : [this.base[i * 3], this.base[i * 3 + 1], this.base[i * 3 + 2]];
      this.data[o] = col[0]; this.data[o + 1] = col[1]; this.data[o + 2] = col[2];
    }
    this.sucio = true;
  }

  subir() {
    if (!this.sucio) return;
    this.textura.needsUpdate = true;
    this.sucio = false;
  }
}

// Industria y ciudad humana: todo 3D, con iluminación, sombras y texturas limpias
// (vectoriales, filtradas). Contrasta a propósito con el pixel art de la naturaleza.
import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { mulberry32 } from './rng.js';
import { ZONAS } from './world.js';

const ALTO_LOSA = 0.12;
const ALTO_CINTA = 0.55;
export const CINTA1 = { x0: 1.9, x1: 6.65, z: 0 };
export const CINTA2 = { x0: 9.5, x1: 20.5, z: 0 };

const mat = (color, o = {}) => new THREE.MeshStandardMaterial({ color, roughness: 0.6, metalness: 0.25, flatShading: true, ...o });
const M = {
  acero: mat('#2b3442'), aceroClaro: mat('#55657d'), ambar: mat('#f29421'),
  goma: mat('#15171b', { roughness: 0.9, metalness: 0 }),
  ladrillo: mat('#5c3a30', { roughness: 0.85, metalness: 0 }),
  brasa: new THREE.MeshStandardMaterial({ color: '#ff7a1a', emissive: '#ff5a00', emissiveIntensity: 2.2 }),
  lingote: mat('#d7793d', { metalness: 0.8, roughness: 0.3, emissive: '#7a2a00', emissiveIntensity: 0.6 }),
};

function canvasTex(w, h, dibujar, { repetir = false, filtro = true } = {}) {
  const c = document.createElement('canvas');
  c.width = w; c.height = h;
  dibujar(c.getContext('2d'), w, h);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = 4;
  if (repetir) t.wrapS = t.wrapT = THREE.RepeatWrapping;
  if (!filtro) t.magFilter = THREE.NearestFilter;
  return t;
}

function caja(w, h, d, material, x, y, z, padre) {
  const m = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), material);
  m.position.set(x, y, z);
  m.castShadow = m.receiveShadow = true;
  padre.add(m);
  return m;
}
function cil(r0, r1, h, material, x, y, z, padre, seg = 20) {
  const m = new THREE.Mesh(new THREE.CylinderGeometry(r0, r1, h, seg), material);
  m.position.set(x, y, z);
  m.castShadow = m.receiveShadow = true;
  padre.add(m);
  return m;
}

function losaFabrica(grupo) {
  const p = ZONAS.fabrica, w = p.x1 - p.x0, d = p.z1 - p.z0;
  const tex = canvasTex(1024, 792, (g, W, H) => {
    g.fillStyle = '#8e98a4'; g.fillRect(0, 0, W, H);
    const s = W / w;
    for (let i = 0; i < 9000; i++) { g.fillStyle = `rgba(${Math.random() < 0.5 ? '255,255,255' : '20,30,40'},0.05)`; g.fillRect(Math.random() * W, Math.random() * H, 3, 3); }
    g.strokeStyle = 'rgba(30,40,55,0.25)'; g.lineWidth = 2;
    for (let x = 0; x <= w; x += 2) { g.beginPath(); g.moveTo(x * s, 0); g.lineTo(x * s, H); g.stroke(); }
    for (let z = 0; z <= d; z += 2) { g.beginPath(); g.moveTo(0, z * s); g.lineTo(W, z * s); g.stroke(); }
    // borde de seguridad
    g.save(); g.beginPath(); g.rect(0, 0, W, H); g.rect(14, 14, W - 28, H - 28); g.clip('evenodd');
    for (let i = -H; i < W + H; i += 28) { g.fillStyle = (i / 28) % 2 ? '#f2b21b' : '#1d2129'; g.beginPath(); g.moveTo(i, 0); g.lineTo(i + 14, 0); g.lineTo(i + 14 - H, H); g.lineTo(i - H, H); g.fill(); }
    g.restore();
    // pasillo de cintas y rótulos de zona
    g.fillStyle = 'rgba(31,95,209,0.18)'; g.fillRect((CINTA1.x0 - p.x0 - 0.2) * s, (d / 2 - 0.6) * s, (p.x1 - CINTA1.x0) * s, 1.2 * s);
    g.fillStyle = 'rgba(19,35,58,0.75)'; g.font = `600 ${0.42 * s}px "Chakra Petch", sans-serif`;
    g.fillText('FUNDICIÓN', (0.1 - p.x0 - 1.4) * s + 30, (d / 2 + 2.2) * s);
    g.fillText('ENSAMBLE', (8 - p.x0 - 1.4) * s, (d / 2 + 2.2) * s);
    g.fillText('EXPEDICIÓN', (12.2 - p.x0 - 1.6) * s, (d / 2 + 2.2) * s);
  });
  const losa = new THREE.Mesh(new THREE.BoxGeometry(w, ALTO_LOSA, d), [M.aceroClaro, M.aceroClaro, new THREE.MeshStandardMaterial({ map: tex, roughness: 0.9 }), M.aceroClaro, M.aceroClaro, M.aceroClaro]);
  losa.position.set((p.x0 + p.x1) / 2, ALTO_LOSA / 2, 0);
  losa.receiveShadow = true;
  grupo.add(losa);
}

function luzEstado(x, y, z, padre) {
  const m = new THREE.Mesh(new THREE.SphereGeometry(0.09, 12, 8), new THREE.MeshStandardMaterial({ color: '#555', emissive: '#333', emissiveIntensity: 1 }));
  m.position.set(x, y, z);
  padre.add(m);
  return m;
}
const COLOR_ESTADO = { trabajando: '#3dff8b', esperando: '#ffb233', parada: '#3a4250' };
function ponerEstado(luz, estado) {
  luz.material.emissive.set(COLOR_ESTADO[estado]);
  luz.material.emissiveIntensity = estado === 'parada' ? 0.3 : 2.4;
}

function fundidora(grupo) {
  const g = new THREE.Group();
  g.position.set(0.55, ALTO_LOSA, 0);
  grupo.add(g);
  caja(2.4, 0.28, 2.4, M.acero, 0, 0.14, 0, g);
  const cuerpo = cil(0.85, 1.0, 1.7, M.ladrillo, 0, 1.13, 0, g, 10);
  cil(1.04, 1.04, 0.14, M.ambar, 0, 0.45, 0, g, 10);
  cil(0.88, 0.88, 0.12, M.acero, 0, 1.95, 0, g, 10);
  cil(0.32, 0.85, 0.5, M.acero, 0, 2.25, 0, g, 10);
  cil(0.2, 0.24, 1.5, M.acero, 0.1, 3.0, -0.1, g, 12);
  cil(0.26, 0.26, 0.12, M.ambar, 0.1, 3.7, -0.1, g, 12);
  const boca = caja(0.7, 0.42, 0.12, M.brasa, 0, 0.82, 0.94, g);
  // tolva: los robots descargan aquí desde el terreno natural
  const tolva = cil(0.62, 0.28, 0.6, M.aceroClaro, -1.85, 0.95, 0, g, 4);
  tolva.rotation.y = Math.PI / 4;
  caja(1.3, 0.1, 0.36, M.acero, -1.2, 0.85, 0, g).rotation.z = 0.5;
  for (const dz of [-0.35, 0.35]) caja(0.08, 0.7, 0.08, M.acero, -1.85, 0.35, dz, g);
  const luz = new THREE.PointLight('#ff7a1a', 3, 4, 2);
  luz.position.set(0, 0.9, 1.4);
  g.add(luz);
  const estado = luzEstado(0.75, 1.9, 0.5, g);
  return { g, boca, luz, estado, chimenea: new THREE.Vector3(0.65, ALTO_LOSA + 3.8, -0.1), tolva: new THREE.Vector3(-1.3, 1.25, 0), cuerpo };
}

function cinta(grupo, x0, x1, z) {
  const len = x1 - x0, cx = (x0 + x1) / 2;
  const tex = canvasTex(128, 64, (g, W, H) => {
    g.fillStyle = '#23272e'; g.fillRect(0, 0, W, H);
    g.strokeStyle = '#3c434f'; g.lineWidth = 10;
    for (let i = 0; i < 2; i++) { g.beginPath(); g.moveTo(i * 64 + 18, 6); g.lineTo(i * 64 + 40, H / 2); g.lineTo(i * 64 + 18, H - 6); g.stroke(); }
  }, { repetir: true });
  tex.repeat.set(len / 0.8, 1);
  const banda = new THREE.Mesh(new THREE.BoxGeometry(len, 0.06, 0.6), [M.goma, M.goma, new THREE.MeshStandardMaterial({ map: tex, roughness: 0.8 }), M.goma, M.goma, M.goma]);
  banda.position.set(cx, ALTO_CINTA, z);
  banda.receiveShadow = banda.castShadow = true;
  grupo.add(banda);
  for (const dz of [-0.36, 0.36]) {
    caja(len, 0.14, 0.08, M.acero, cx, ALTO_CINTA + 0.02, z + dz, grupo);
    caja(len, 0.03, 0.09, M.ambar, cx, ALTO_CINTA + 0.1, z + dz, grupo);
  }
  for (let x = x0 + 0.3; x < x1; x += 1.6) for (const dz of [-0.3, 0.3]) caja(0.09, ALTO_CINTA, 0.09, M.aceroClaro, x, ALTO_CINTA / 2, z + dz, grupo);
  for (const x of [x0, x1]) cil(0.07, 0.07, 0.7, M.aceroClaro, x, ALTO_CINTA, z, grupo, 10).rotation.x = Math.PI / 2;
  return { tex, x0, x1, z };
}

function texturaChip() {
  return canvasTex(64, 64, (g) => {
    g.fillStyle = '#1b6b45'; g.fillRect(0, 0, 64, 64);
    g.strokeStyle = '#d8b84a'; g.lineWidth = 2;
    for (let i = 0; i < 6; i++) { g.beginPath(); g.moveTo(4, 8 + i * 9); g.lineTo(18, 8 + i * 9); g.lineTo(24, 14 + i * 7); g.stroke(); }
    g.fillStyle = '#14161a'; g.fillRect(22, 18, 28, 28);
    g.fillStyle = '#59f0ff'; g.fillRect(33, 29, 6, 6);
  });
}

async function ensambladora(grupo) {
  const g = new THREE.Group();
  g.position.set(8.05, ALTO_LOSA, 0);
  grupo.add(g);
  let mixer = null, acciones = {};
  try {
    const gltf = await new GLTFLoader().loadAsync('assets/ensambladora.glb');
    const modelo = gltf.scene;
    modelo.rotation.y = Math.PI / 2; // la boca de salida mira hacia la cinta (este)
    modelo.traverse(o => {
      if (!o.isMesh) return;
      o.castShadow = o.receiveShadow = true;
      if (o.material.name === 'neon') { o.material.emissiveIntensity = 2.5; o.castShadow = false; }
    });
    g.add(modelo);
    mixer = new THREE.AnimationMixer(modelo);
    for (const clip of gltf.animations) acciones[clip.name] = mixer.clipAction(clip).play();
  } catch (e) {
    console.warn('No se pudo cargar assets/ensambladora.glb; uso una versión procedural.', e);
    caja(2.6, 1.6, 2.6, M.aceroClaro, 0, 0.8, 0, g);
  }
  const estado = luzEstado(-0.9, 1.95, 1.0, g);
  return { g, mixer, acciones, estado };
}

function ciudad(grupo) {
  const c = ZONAS.ciudad, w = c.x1 - c.x0, d = c.z1 - c.z0;
  const rnd = mulberry32(99);
  const acera = new THREE.Mesh(new THREE.BoxGeometry(w, 0.1, d), mat('#b8bcc2', { metalness: 0 }));
  acera.position.set((c.x0 + c.x1) / 2, 0.05, 0);
  acera.receiveShadow = true;
  grupo.add(acera);
  const asfalto = mat('#3b3f47', { metalness: 0, roughness: 0.95 });
  const linea = mat('#f2efe6', { metalness: 0 });
  const vias = [
    { x0: c.x0 + 0.5, x1: c.x1 - 0.5, z: c.z0 + 1, h: true }, { x0: c.x0 + 0.5, x1: c.x1 - 0.5, z: c.z1 - 1, h: true },
    { x0: c.x0 + 3.4, x1: c.x1 - 0.5, z: 3.4, h: true },
    { z0: c.z0 + 0.5, z1: c.z1 - 0.5, x: c.x1 - 1, h: false }, { z0: c.z0 + 0.5, z1: c.z1 - 0.5, x: c.x0 + 3.4, h: false },
    { z0: c.z0 + 0.5, z1: c.z1 - 0.5, x: 27.2, h: false },
  ];
  for (const v of vias) {
    if (v.h) {
      caja(v.x1 - v.x0, 0.03, 1, asfalto, (v.x0 + v.x1) / 2, 0.115, v.z, grupo).castShadow = false;
      for (let x = v.x0 + 0.4; x < v.x1 - 0.3; x += 0.8) caja(0.35, 0.01, 0.05, linea, x, 0.135, v.z, grupo).castShadow = false;
    } else {
      caja(1, 0.03, v.z1 - v.z0, asfalto, v.x, 0.116, (v.z0 + v.z1) / 2, grupo).castShadow = false;
      for (let z = v.z0 + 0.4; z < v.z1 - 0.3; z += 0.8) caja(0.05, 0.01, 0.35, linea, v.x, 0.136, z, grupo).castShadow = false;
    }
  }
  const enVia = (x, z, m) => vias.some(v => v.h ? (x > v.x0 - m && x < v.x1 + m && Math.abs(z - v.z) < 0.5 + m) : (z > v.z0 - m && z < v.z1 + m && Math.abs(x - v.x) < 0.5 + m));

  // recepción de chips, donde termina la cinta
  const rec = new THREE.Group();
  rec.position.set(c.x0 + 1.6, 0.1, 0);
  grupo.add(rec);
  caja(2.2, 1.3, 2.6, mat('#d9dde2', { metalness: 0.1 }), 0, 0.65, 0, rec);
  caja(2.4, 0.12, 2.8, mat('#1f5fd1'), 0, 1.36, 0, rec);
  caja(0.06, 0.6, 0.8, M.goma, -1.11, 0.55, 0, rec);
  const cartel = canvasTex(256, 64, (g) => {
    g.fillStyle = '#1f5fd1'; g.fillRect(0, 0, 256, 64);
    g.fillStyle = '#ffffff'; g.font = '600 30px "Chakra Petch", sans-serif'; g.textAlign = 'center'; g.fillText('RECEPCIÓN', 128, 43);
  });
  const placa = new THREE.Mesh(new THREE.PlaneGeometry(1.8, 0.45), new THREE.MeshStandardMaterial({ map: cartel }));
  placa.position.set(0, 0.95, 1.31);
  rec.add(placa);

  const fachadas = ['#e9e4da', '#d7c7b4', '#c9d3dc', '#b55d43', '#e3d6a8', '#8fa3b8'];
  const ventanas = (base) => canvasTex(64, 128, (g) => {
    g.fillStyle = base; g.fillRect(0, 0, 64, 128);
    for (let y = 6; y < 124; y += 16) for (let x = 6; x < 60; x += 14) {
      g.fillStyle = Math.random() < 0.25 ? '#ffd98a' : '#3d5a78'; g.fillRect(x, y, 8, 9);
      g.fillStyle = 'rgba(0,0,0,0.15)'; g.fillRect(x, y + 9, 8, 2);
    }
  }, { repetir: true });
  const tejado = mat('#a8452f', { metalness: 0 });
  const verde = mat('#5f9a4c', { metalness: 0 });
  const tronco = mat('#6b4a32', { metalness: 0 });
  const paso = 1.42;
  for (let x = c.x0 + 0.9; x < c.x1 - 0.5; x += paso) for (let z = c.z0 + 0.9; z < c.z1 - 0.5; z += paso) {
    if (enVia(x, z, 0.12) || (x < c.x0 + 3.2 && Math.abs(z) < 1.9)) continue;
    const u = rnd();
    const fx = x + (rnd() - 0.5) * 0.15, fz = z + (rnd() - 0.5) * 0.15;
    if (u < 0.16) {
      // parque: árboles humanos, modelados en 3D (contraste deliberado con la flora pixel)
      caja(1.3, 0.04, 1.3, verde, fx, 0.12, fz, grupo).castShadow = false;
      for (let k = 0; k < 2; k++) {
        const ax = fx + (rnd() - 0.5) * 0.7, az = fz + (rnd() - 0.5) * 0.7;
        cil(0.05, 0.06, 0.4, tronco, ax, 0.32, az, grupo, 6);
        const copa = new THREE.Mesh(new THREE.IcosahedronGeometry(0.32, 0), mat('#4f8f3f', { metalness: 0 }));
        copa.position.set(ax, 0.7, az); copa.castShadow = true; grupo.add(copa);
      }
    } else if (u < 0.5) {
      const h = 0.7 + rnd() * 0.4, col = fachadas[(rnd() * fachadas.length) | 0];
      caja(1.1, h, 1.1, mat(col, { metalness: 0 }), fx, 0.1 + h / 2, fz, grupo);
      const techo = new THREE.Mesh(new THREE.ConeGeometry(0.85, 0.5, 4), tejado);
      techo.position.set(fx, 0.1 + h + 0.25, fz); techo.rotation.y = Math.PI / 4; techo.castShadow = true;
      grupo.add(techo);
    } else {
      const h = 1.4 + Math.pow(rnd(), 1.6) * 4.6 * (1 - Math.abs(z) / 14), col = fachadas[(rnd() * fachadas.length) | 0];
      const t = ventanas(col);
      t.repeat.set(1, h / 1.4);
      const lado = new THREE.MeshStandardMaterial({ map: t, roughness: 0.7, metalness: 0.05 });
      const techo = mat('#5d6470');
      caja(1.2, h, 1.2, [lado, lado, techo, techo, lado, lado], fx, 0.1 + h / 2, fz, grupo);
      if (h > 3.5) caja(0.3, 0.5, 0.3, M.aceroClaro, fx + 0.25, 0.1 + h + 0.25, fz - 0.2, grupo);
    }
  }

  // tráfico: coches que recorren el anillo exterior
  const ruta = [[c.x0 + 3.4, c.z0 + 1], [c.x1 - 1, c.z0 + 1], [c.x1 - 1, c.z1 - 1], [c.x0 + 3.4, c.z1 - 1]];
  const per = ruta.reduce((s, p, i) => s + Math.hypot(ruta[(i + 1) % 4][0] - p[0], ruta[(i + 1) % 4][1] - p[1]), 0);
  const coches = [];
  const colores = ['#d9483b', '#f2efe6', '#2f6fd1', '#f2b21b', '#3a3f47', '#4fa36a'];
  for (let i = 0; i < 7; i++) {
    const car = new THREE.Group();
    caja(0.42, 0.14, 0.22, mat(colores[i % colores.length], { metalness: 0.4, roughness: 0.4 }), 0, 0.2, 0, car);
    caja(0.22, 0.1, 0.19, mat('#1d2633', { metalness: 0.6, roughness: 0.2 }), -0.02, 0.32, 0, car);
    grupo.add(car);
    coches.push({ car, s: (per / 7) * i, v: 0.9 + rnd() * 0.4 });
  }
  const moverCoches = (dt) => {
    for (const k of coches) {
      k.s = (k.s + k.v * dt) % per;
      let s = k.s;
      for (let i = 0; i < 4; i++) {
        const a = ruta[i], b = ruta[(i + 1) % 4], L = Math.hypot(b[0] - a[0], b[1] - a[1]);
        if (s > L) { s -= L; continue; }
        const dx = (b[0] - a[0]) / L, dz = (b[1] - a[1]) / L;
        k.car.position.set(a[0] + dx * s - dz * 0.22, 0.03, a[1] + dz * s + dx * 0.22);
        k.car.rotation.y = Math.atan2(-dz, dx);
        break;
      }
    }
  };
  return { moverCoches, recepcion: new THREE.Vector3(c.x0 + 1.6, 1.6, 0) };
}

export async function crearIndustria(escena) {
  const fabrica = new THREE.Group();
  const urbe = new THREE.Group();
  escena.add(fabrica, urbe);
  losaFabrica(fabrica);
  const fun = fundidora(fabrica);
  const c1 = cinta(fabrica, CINTA1.x0, CINTA1.x1, CINTA1.z);
  const c2 = cinta(fabrica, CINTA2.x0, CINTA2.x1, CINTA2.z);
  const ens = await ensambladora(fabrica);
  const city = ciudad(urbe);

  // muelle de carga de robots: plataforma 3D sobre el terreno natural
  const mu = ZONAS.muelle;
  caja(mu.x1 - mu.x0, 0.08, mu.z1 - mu.z0, mat('#3a4558'), (mu.x0 + mu.x1) / 2, 0.04, (mu.z0 + mu.z1) / 2, fabrica);
  for (let i = 0; i < 3; i++) caja(0.7, 0.012, 0.7, mat('#59f0ff', { emissive: '#1b6f80', emissiveIntensity: 1 }), mu.x0 + 0.7 + i * 0.9, 0.09, mu.z0 + 1.6, fabrica).castShadow = false;

  // objetos de cinta: lingotes y chips (3D: ya son producto industrial)
  const geoLingote = new THREE.BoxGeometry(0.34, 0.13, 0.2);
  const matChip = new THREE.MeshStandardMaterial({ map: texturaChip(), roughness: 0.5, emissive: '#0b3b2a', emissiveIntensity: 0.4 });
  const geoChip = new THREE.BoxGeometry(0.36, 0.05, 0.36);
  const mallas = new Map();
  const malla = (it) => {
    let m = mallas.get(it.id);
    if (!m) {
      m = new THREE.Mesh(it.tipo === 'lingote' ? geoLingote : geoChip, it.tipo === 'lingote' ? M.lingote : matChip);
      m.castShadow = true;
      fabrica.add(m);
      mallas.set(it.id, m);
    }
    m.userData.vivo = true;
    return m;
  };

  let reloj = 0;
  function actualizar(dt, sim, alfa) {
    reloj += dt;
    c1.tex.offset.x -= dt * 1.25 / 0.8 * (sim.cinta1.items.length ? 1 : 0.15);
    c2.tex.offset.x -= dt * 1.25 / 0.8;
    for (const m of mallas.values()) m.userData.vivo = false;
    for (const [c, cfg] of [[sim.cinta1, CINTA1], [sim.cinta2, CINTA2]]) for (const it of c.items) {
      const s = it.ps + (it.s - it.ps) * alfa;
      const m = malla(it);
      m.position.set(cfg.x0 + s, ALTO_CINTA + 0.1, cfg.z);
      if (it.tipo === 'chip') m.rotation.y = 0;
    }
    for (const [id, m] of mallas) if (!m.userData.vivo) { fabrica.remove(m); mallas.delete(id); }

    const f = sim.fundidora;
    const parpadeo = 0.75 + Math.sin(reloj * 17) * 0.12 + Math.sin(reloj * 7.3) * 0.1;
    fun.boca.material.emissiveIntensity = f.trabajando ? 2.6 * parpadeo : 0.6;
    fun.luz.intensity = f.trabajando ? 4 * parpadeo : 0.6;
    ponerEstado(fun.estado, f.trabajando ? 'trabajando' : f.listo ? 'esperando' : 'parada');

    const e = sim.ensambladora;
    if (ens.mixer) {
      for (const [nombre, a] of Object.entries(ens.acciones)) {
        if (nombre.startsWith('piston')) a.paused = !e.trabajando;
        else a.timeScale = e.trabajando ? 2.5 : 0.4;
      }
      ens.mixer.update(dt);
    }
    ponerEstado(ens.estado, e.trabajando ? 'trabajando' : e.listo ? 'esperando' : 'parada');
    city.moverCoches(dt);
  }

  return {
    fabrica, urbe, actualizar,
    anclas: {
      chimenea: fun.chimenea, tolva: fun.tolva, recepcion: city.recepcion,
      fundidora: new THREE.Vector3(0.55, 2.6, 0), ensambladora: new THREE.Vector3(8.05, 2.8, 0),
      chimeneaEns: new THREE.Vector3(8.05 - 0.62, ALTO_LOSA + 2.7, -0.78),
    },
  };
}

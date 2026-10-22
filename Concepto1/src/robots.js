// Robots: volumen 3D por piezas rígidas, piel pixel art. La cara es una pantalla cuyo
// «sprite sheet» cambia según el estado de la simulación; la carga natural sigue siendo 2D.
import * as THREE from 'three';
import { PAL, texto3x5 } from './pixel.js';

const CARAS = ['reposo', 'parpadeo', 'mover', 'minar', 'cargado', 'esperando', 'manual'];
const FW = 12, FH = 8;

function lienzo(w, h, dibujar) {
  const c = document.createElement('canvas');
  c.width = w; c.height = h;
  dibujar(c.getContext('2d'));
  return c;
}
function pixelTex(canvas) {
  const t = new THREE.CanvasTexture(canvas);
  t.magFilter = t.minFilter = THREE.NearestFilter;
  t.generateMipmaps = false;
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}

const hojaCaras = lienzo(FW * CARAS.length, FH, (g) => {
  const px = (f, x, y, c) => { g.fillStyle = c; g.fillRect(f * FW + x, y, 1, 1); };
  const ojo = (f, x, y, c, w = 2, h = 2) => { for (let i = 0; i < w; i++) for (let j = 0; j < h; j++) px(f, x + i, y + j, c); };
  for (let f = 0; f < CARAS.length; f++) {
    g.fillStyle = '#081620'; g.fillRect(f * FW, 0, FW, FH);
    g.fillStyle = '#0e2533'; g.fillRect(f * FW, 0, FW, 1);
  }
  const C = PAL.cian, A = PAL.chispa0;
  ojo(0, 3, 3, C); ojo(0, 7, 3, C);
  ojo(1, 3, 4, C, 2, 1); ojo(1, 7, 4, C, 2, 1);
  ojo(2, 4, 3, C); ojo(2, 8, 3, C); px(2, 1, 4, PAL.cianOsc); px(2, 2, 4, PAL.cianOsc);
  for (const [x, y] of [[2, 2], [3, 3], [2, 4], [9, 2], [8, 3], [9, 4]]) px(3, x, y, A);
  for (const [x, y] of [[2, 4], [3, 3], [4, 4], [7, 4], [8, 3], [9, 4]]) px(4, x, y, C);
  for (const x of [3, 6, 9]) px(5, x - 1, 4, '#ffb233');
  for (const [x, y] of [[2, 2], [3, 2], [4, 2], [2, 3], [4, 3], [2, 4], [3, 4], [4, 4]]) { px(6, x, y, '#ff5fd2'); px(6, x + 5, y, '#ff5fd2'); }
});

const orugaLado = lienzo(16, 8, (g) => {
  g.fillStyle = '#1b1d22'; g.fillRect(0, 0, 16, 8);
  g.fillStyle = '#41454f';
  for (let x = 0; x < 16; x += 4) g.fillRect(x, 0, 2, 8);
  g.fillStyle = '#2a2d34'; g.fillRect(0, 3, 16, 2);
});
const orugaArriba = lienzo(8, 16, (g) => {
  g.fillStyle = '#1b1d22'; g.fillRect(0, 0, 8, 16);
  g.fillStyle = '#4a4f5a';
  for (let y = 0; y < 16; y += 4) g.fillRect(0, y, 8, 2);
});

function texCuerpo(id) {
  return pixelTex(lienzo(16, 10, (g) => {
    g.fillStyle = '#e8b13a'; g.fillRect(0, 0, 16, 10);
    g.fillStyle = '#b07a1e'; g.fillRect(0, 9, 16, 1); g.fillRect(15, 0, 1, 10);
    g.fillStyle = '#f7d77e'; g.fillRect(0, 0, 16, 1); g.fillRect(0, 0, 1, 10);
    for (const [x, y] of [[1, 1], [14, 1], [1, 8], [14, 8]]) { g.fillStyle = '#8a5d16'; g.fillRect(x, y, 1, 1); }
    texto3x5(g, `R${id}`, 2, 3, '#24180c');
    g.fillStyle = '#24180c'; for (let y = 3; y < 8; y += 2) g.fillRect(11, y, 3, 1);
  }));
}
const texLiso = pixelTex(lienzo(8, 8, (g) => {
  g.fillStyle = '#e8b13a'; g.fillRect(0, 0, 8, 8);
  g.fillStyle = '#d29a2c'; g.fillRect(0, 7, 8, 1); g.fillRect(7, 0, 1, 8);
}));

const geo = {
  oruga: new THREE.BoxGeometry(0.26, 0.3, 1.0),
  chasis: new THREE.BoxGeometry(0.6, 0.12, 0.84),
  cuerpo: new THREE.BoxGeometry(0.8, 0.46, 0.78),
  cuello: new THREE.CylinderGeometry(0.08, 0.1, 0.18, 8),
  cabeza: new THREE.BoxGeometry(0.68, 0.42, 0.5),
  antena: new THREE.CylinderGeometry(0.018, 0.018, 0.32, 6),
  punta: new THREE.SphereGeometry(0.05, 8, 6),
  diente: new THREE.BoxGeometry(0.06, 0.05, 0.36),
  bandeja: new THREE.BoxGeometry(0.5, 0.04, 0.3),
  anillo: new THREE.RingGeometry(0.72, 0.84, 40),
};
const oscuro = new THREE.MeshStandardMaterial({ color: '#2a2f38', roughness: 0.7, metalness: 0.4, flatShading: true });

export class RobotVisual {
  constructor(datos, escena) {
    this.id = datos.id;
    const g = new THREE.Group();
    this.g = g;
    const piel = new THREE.MeshStandardMaterial({ map: texCuerpo(datos.id), roughness: 0.55, metalness: 0.1 });
    const liso = new THREE.MeshStandardMaterial({ map: texLiso, roughness: 0.55, metalness: 0.1 });

    this.lado = pixelTex(orugaLado); this.lado.wrapS = THREE.RepeatWrapping; this.lado.repeat.set(4, 1);
    this.arriba = pixelTex(orugaArriba); this.arriba.wrapT = THREE.RepeatWrapping; this.arriba.repeat.set(1, 4);
    const matLado = new THREE.MeshStandardMaterial({ map: this.lado, roughness: 0.9 });
    const matArriba = new THREE.MeshStandardMaterial({ map: this.arriba, roughness: 0.9 });
    const orugaMats = [matLado, matLado, matArriba, oscuro, oscuro, oscuro];
    for (const x of [-0.38, 0.38]) this.pieza(geo.oruga, orugaMats, x, 0.15, 0);
    this.pieza(geo.chasis, oscuro, 0, 0.3, 0);
    this.cuerpo = this.pieza(geo.cuerpo, [piel, piel, liso, oscuro, piel, piel], 0, 0.59, -0.02);
    this.pieza(geo.cuello, oscuro, 0, 0.9, -0.05);

    this.cara = pixelTex(hojaCaras);
    this.cara.repeat.set(1 / CARAS.length, 1);
    const pantalla = new THREE.MeshStandardMaterial({ map: this.cara, emissiveMap: this.cara, emissive: '#ffffff', emissiveIntensity: 1.3, roughness: 0.3 });
    this.cabeza = new THREE.Group();
    this.cabeza.position.set(0, 1.12, -0.04);
    g.add(this.cabeza);
    this.pieza(geo.cabeza, [liso, liso, liso, oscuro, pantalla, liso], 0, 0, 0, this.cabeza);
    this.pieza(geo.antena, oscuro, 0.22, 0.36, -0.12, this.cabeza);
    this.punta = this.pieza(geo.punta, new THREE.MeshStandardMaterial({ color: '#0e3a44', emissive: PAL.cian, emissiveIntensity: 2 }), 0.22, 0.54, -0.12, this.cabeza);

    for (const x of [-0.16, 0.16]) this.pieza(geo.diente, oscuro, x, 0.33, 0.62);
    this.pieza(geo.bandeja, oscuro, 0, 0.37, 0.66);

    this.anillo = new THREE.Mesh(geo.anillo, new THREE.MeshBasicMaterial({ color: PAL.cian, transparent: true, opacity: 0.95, depthWrite: false }));
    this.anillo.rotation.x = -Math.PI / 2;
    this.anillo.position.y = 0.03;
    this.anillo.visible = false;
    g.add(this.anillo);

    g.traverse(o => { o.userData.robotId = datos.id; });
    escena.add(g);
    this.ultimaDist = datos.distancia;
    this.parpadeo = Math.random() * 3;
    this.aparicion = 0;
  }

  pieza(geometria, material, x, y, z, padre = this.g) {
    const m = new THREE.Mesh(geometria, material);
    m.position.set(x, y, z);
    m.castShadow = true;
    padre.add(m);
    return m;
  }

  ponerCara(nombre) { this.cara.offset.x = CARAS.indexOf(nombre) / CARAS.length; }

  actualizar(r, alfa, dt, t, seleccionado) {
    const x = r.px + (r.x - r.px) * alfa, z = r.pz + (r.z - r.pz) * alfa;
    const giro = ((r.rumbo - r.prumbo + Math.PI * 3) % (Math.PI * 2)) - Math.PI;
    const avance = r.distancia - this.ultimaDist;
    this.ultimaDist = r.distancia;
    this.recorrido = (this.recorrido || 0) + avance;
    this.aparicion = Math.min(1, this.aparicion + dt * 2.5);
    const s = 0.4 + 0.6 * (1 - Math.pow(1 - this.aparicion, 3));
    this.g.scale.setScalar(s);
    const enMarcha = avance > 1e-4;
    this.g.position.set(x, enMarcha ? Math.abs(Math.sin(this.recorrido * 9)) * 0.025 : 0, z);
    this.g.rotation.y = r.prumbo + giro * alfa;
    this.lado.offset.x = -this.recorrido * 1.6;
    this.arriba.offset.y = this.recorrido * 1.6;

    this.parpadeo -= dt;
    let cara = 'reposo';
    if (r.modo === 'manual') cara = 'manual';
    else if (r.estado === 'minando') cara = 'minar';
    else if (r.estado === 'esperando') cara = 'esperando';
    else if (r.carga) cara = 'cargado';
    else if (enMarcha) cara = 'mover';
    if ((cara === 'reposo' || cara === 'mover') && this.parpadeo < 0.12) cara = 'parpadeo';
    if (this.parpadeo < 0) this.parpadeo = 2 + Math.random() * 3;
    this.ponerCara(cara);

    this.cabeza.rotation.x = r.estado === 'minando' ? 0.18 + Math.sin(t * 16) * 0.1 : 0;
    this.cabeza.rotation.z = r.estado === 'esperando' ? Math.sin(t * 2) * 0.08 : 0;
    this.punta.material.emissiveIntensity = (Math.sin(t * 4 + this.id) > 0.6) ? 3 : 0.6;
    this.anillo.visible = seleccionado;
    if (seleccionado) this.anillo.material.opacity = 0.65 + Math.sin(t * 5) * 0.3;
    return enMarcha;
  }

  puntoCarga(v) { return this.g.localToWorld(v.set(0, 0.4, 0.62)); }
}

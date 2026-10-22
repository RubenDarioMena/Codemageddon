// Capa de sprites 2D dentro del mundo 3D: un solo draw call por capa.
// Cada sprite es un plano alineado con la pantalla y anclado por la base. En cámara
// ortográfica toda su superficie queda a la profundidad de su base, que es justo la
// regla de orden de un juego 2D («lo que está más abajo en pantalla tapa»), y además
// convive con el depth buffer de los modelos 3D sin cortes contra el suelo.
import * as THREE from 'three';
import { PPM } from './pixel.js';

const VERT = /* glsl */`
attribute vec3 iPos;
attribute vec2 iSize;
attribute vec4 iRect;
attribute float iAlpha;
attribute float iSway;
uniform float uTime;
varying vec2 vUv;
varying float vAlpha;
void main() {
  vec3 right = vec3(viewMatrix[0][0], viewMatrix[1][0], viewMatrix[2][0]);
  vec3 up = vec3(viewMatrix[0][1], viewMatrix[1][1], viewMatrix[2][1]);
  // Viento a pasos enteros de píxel: la copa se desplaza 0, 1 o 2 px, nunca medio.
  float paso = floor(sin(uTime * 1.6 + iPos.x * 0.7 + iPos.z * 0.45) * 1.4 + 0.5);
  float sway = paso / ${PPM.toFixed(1)} * iSway * position.y;
  vec3 world = iPos + right * (position.x * iSize.x + sway) + up * (position.y * iSize.y);
  vUv = mix(iRect.xy, iRect.zw, uv);
  vAlpha = iAlpha;
  gl_Position = projectionMatrix * viewMatrix * vec4(world, 1.0);
}`;

const FRAG = /* glsl */`
uniform sampler2D uMap;
uniform vec2 uAtlas;
uniform vec3 uTint;
varying vec2 vUv;
varying float vAlpha;
float bayer4(vec2 p) {
  int x = int(mod(p.x, 4.0)), y = int(mod(p.y, 4.0));
  float m[16] = float[16](0., 8., 2., 10., 12., 4., 14., 6., 3., 11., 1., 9., 15., 7., 13., 5.);
  return (m[y * 4 + x] + 0.5) / 16.0;
}
void main() {
  vec4 c = texture2D(uMap, vUv);
  if (c.a < 0.5) discard;
  // Transparencia tramada por texel del sprite: se disuelve como pixel art, sin mezcla alfa.
  if (vAlpha < 0.999 && vAlpha <= bayer4(floor(vUv * uAtlas))) discard;
  gl_FragColor = vec4(c.rgb * uTint, 1.0);
}`;

export function texturaAtlas(canvas) {
  const t = new THREE.CanvasTexture(canvas);
  t.magFilter = t.minFilter = THREE.NearestFilter;
  t.generateMipmaps = false;
  t.colorSpace = THREE.NoColorSpace; // el shader escribe el color tal cual: paleta exacta
  return t;
}

export class CapaSprites {
  constructor(capacidad, textura, tamAtlas) {
    this.cap = capacidad;
    const base = new THREE.PlaneGeometry(1, 1);
    base.translate(0, 0.5, 0);
    const g = new THREE.InstancedBufferGeometry();
    g.index = base.index;
    g.setAttribute('position', base.getAttribute('position'));
    g.setAttribute('uv', base.getAttribute('uv'));
    const attr = (n, size) => {
      const a = new THREE.InstancedBufferAttribute(new Float32Array(capacidad * size), size);
      a.setUsage(THREE.DynamicDrawUsage);
      g.setAttribute(n, a);
      return a;
    };
    this.pos = attr('iPos', 3);
    this.size = attr('iSize', 2);
    this.rect = attr('iRect', 4);
    this.alpha = attr('iAlpha', 1);
    this.sway = attr('iSway', 1);
    g.instanceCount = 0;
    this.geo = g;
    this.material = new THREE.ShaderMaterial({
      vertexShader: VERT,
      fragmentShader: FRAG,
      uniforms: {
        uMap: { value: textura },
        uAtlas: { value: new THREE.Vector2(tamAtlas, tamAtlas) },
        uTint: { value: new THREE.Color(1, 1, 1) },
        uTime: { value: 0 },
      },
    });
    this.mesh = new THREE.Mesh(g, this.material);
    this.mesh.frustumCulled = false;
    this.n = 0;
  }

  agregar(x, y, z, sprite, { alpha = 1, sway = 0, escala = 1 } = {}) {
    const i = this.n++;
    if (i >= this.cap) throw new Error('Capa de sprites llena');
    this.escribir(i, x, y, z, sprite, alpha, sway, escala);
    this.geo.instanceCount = this.n;
    return i;
  }

  escribir(i, x, y, z, sprite, alpha = 1, sway = 0, escala = 1) {
    this.pos.setXYZ(i, x, y, z);
    this.size.setXY(i, (sprite.w / PPM) * escala, (sprite.h / PPM) * escala);
    this.rect.setXYZW(i, ...sprite.uv);
    this.alpha.setX(i, alpha);
    this.sway.setX(i, sway);
    for (const a of [this.pos, this.size, this.rect, this.alpha, this.sway]) a.needsUpdate = true;
  }

  cambiarSprite(i, sprite) {
    this.size.setXY(i, sprite.w / PPM, sprite.h / PPM);
    this.rect.setXYZW(i, ...sprite.uv);
    this.size.needsUpdate = this.rect.needsUpdate = true;
  }

  // Modo dinámico: vaciar y volver a llenar cada fotograma (partículas, carga).
  vaciar() { this.n = 0; }
  cerrar() { this.geo.instanceCount = this.n; }
}

// Partículas pixel art (humo, polvo, chispas, destellos) sobre la capa dinámica.
export class Particulas {
  constructor(rects) {
    this.r = rects;
    this.lista = [];
  }

  emitir(tipo, x, y, z, n = 1) {
    for (let k = 0; k < n; k++) {
      const p = { tipo, x, y, z, vx: 0, vy: 0, vz: 0, t: 0, vida: 1 };
      if (tipo === 'humo') { p.vida = 2.6 + Math.random(); p.vy = 0.55; p.vx = 0.25; p.vz = 0.05; }
      else if (tipo === 'polvo') { const a = Math.random() * 6.28; p.vida = 0.55; p.vx = Math.cos(a) * 0.6; p.vz = Math.sin(a) * 0.6; p.vy = 0.5; }
      else if (tipo === 'chispa') { const a = Math.random() * 6.28; p.vida = 0.45 + Math.random() * 0.2; p.vx = Math.cos(a) * 1.4; p.vz = Math.sin(a) * 1.4; p.vy = 2.2 + Math.random(); }
      else if (tipo === 'destello') { p.vida = 0.9; p.vy = 0.4; }
      this.lista.push(p);
    }
  }

  actualizar(dt) {
    for (const p of this.lista) {
      p.t += dt;
      if (p.tipo === 'chispa' || p.tipo === 'polvo') p.vy -= (p.tipo === 'chispa' ? 7 : 1.5) * dt;
      p.x += p.vx * dt; p.y = Math.max(0, p.y + p.vy * dt); p.z += p.vz * dt;
    }
    this.lista = this.lista.filter(p => p.t < p.vida);
  }

  dibujar(capa) {
    const r = this.r;
    for (const p of this.lista) {
      const f = p.t / p.vida;
      let sprite, alpha = 1;
      if (p.tipo === 'humo') { sprite = r[`humo${Math.min(4, (f * 5) | 0)}`]; alpha = f > 0.55 ? 1 - (f - 0.55) / 0.45 : 1; }
      else if (p.tipo === 'polvo') { sprite = r[`polvo${Math.min(2, (f * 3) | 0)}`]; alpha = 1 - f * 0.8; }
      else if (p.tipo === 'chispa') sprite = r[`chispa${((p.t * 20) | 0) % 2}`];
      else { sprite = r.destello; alpha = 1 - f; }
      if (capa.n < capa.cap) capa.escribir(capa.n++, p.x, p.y, p.z, sprite, alpha);
    }
  }
}

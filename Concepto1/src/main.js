import * as THREE from 'three';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';
import * as P from './pixel.js';
import { CapaSprites, Particulas, texturaAtlas } from './billboards.js';
import { Mundo, MAPA, MITAD, DESCARGA, ZONAS } from './world.js';
import { Simulacion, CFG, PROGRAMA, LINEA } from './sim.js';
import { crearIndustria, CINTA1, CINTA2 } from './industria.js';
import { RobotVisual } from './robots.js';

const $ = (s) => document.querySelector(s);
const esperarPintado = () => new Promise(r => setTimeout(r, 50)); // deja pintar «Generando…»

async function iniciar() {
  await esperarPintado();

  // --- render ---------------------------------------------------------------
  const lienzo = $('#c');
  const renderer = new THREE.WebGLRenderer({ canvas: lienzo, antialias: true });
  const dpr = Math.min(window.devicePixelRatio || 1, 2);
  renderer.setPixelRatio(dpr);
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFSoftShadowMap;
  const escena = new THREE.Scene();
  escena.background = new THREE.Color('#122019');
  // Reflejos suaves para los metales 3D (no afecta a los sprites ni al terreno).
  const pmrem = new THREE.PMREMGenerator(renderer);
  escena.environment = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;
  escena.environmentIntensity = 0.45;

  escena.add(new THREE.HemisphereLight('#e2f0ff', '#4f6b45', 1.25));
  const sol = new THREE.DirectionalLight('#fff0d4', 2.3);
  sol.position.set(-16, 26, -10);
  sol.castShadow = true;
  sol.shadow.mapSize.set(4096, 4096);
  Object.assign(sol.shadow.camera, { left: -42, right: 42, top: 42, bottom: -42, near: 1, far: 90 });
  sol.shadow.bias = -0.0004;
  sol.shadow.normalBias = 0.03;
  escena.add(sol, sol.target);

  // --- mundo natural (2D pixel art) ----------------------------------------
  const mundo = new Mundo(7);
  const suelo = new THREE.Mesh(new THREE.PlaneGeometry(MAPA, MAPA), new THREE.MeshBasicMaterial({ map: mundo.textura }));
  suelo.rotation.x = -Math.PI / 2;
  escena.add(suelo);
  const receptorSombras = new THREE.Mesh(new THREE.PlaneGeometry(MAPA, MAPA), new THREE.ShadowMaterial({ color: '#0a1830', opacity: 0.4 }));
  receptorSombras.rotation.x = -Math.PI / 2;
  receptorSombras.position.y = 0.004;
  receptorSombras.receiveShadow = true;
  escena.add(receptorSombras);

  const entradas = [];
  for (let v = 0; v < 4; v++) {
    entradas.push({ nombre: `pino${v}`, lienzo: P.pino(100 + v) }, { nombre: `arbol${v}`, lienzo: P.arbol(200 + v) },
      { nombre: `arbusto${v}`, lienzo: P.arbusto(300 + v) }, { nombre: `pasto${v}`, lienzo: P.pasto(400 + v) },
      { nombre: `flores${v}`, lienzo: P.flores(500 + v) }, { nombre: `roca${v}`, lienzo: P.roca(600 + v) });
  }
  for (let v = 0; v < 3; v++) P.cobre(700 + v).forEach((l, f) => entradas.push({ nombre: `cobre${v}_${f}`, lienzo: l }));
  P.humo().forEach((l, f) => entradas.push({ nombre: `humo${f}`, lienzo: l }));
  P.polvo().forEach((l, f) => entradas.push({ nombre: `polvo${f}`, lienzo: l }));
  P.chispa().forEach((l, f) => entradas.push({ nombre: `chispa${f}`, lienzo: l }));
  entradas.push({ nombre: 'destello', lienzo: P.destello() }, { nombre: 'mena', lienzo: P.mena() });
  const atlas = P.crearAtlas(entradas, 512);
  const R = atlas.rects;
  const texAtlas = texturaAtlas(atlas.canvas);

  const flora = new CapaSprites(mundo.flora.length + mundo.menas.length, texAtlas, 512);
  const BALANCEO = { pino: 0.6, arbol: 1, arbusto: 0.5, pasto: 1, flores: 1, roca: 0 };
  for (const f of mundo.flora) flora.agregar(f.x, 0.02, f.z, R[`${f.tipo}${f.variante}`], { sway: BALANCEO[f.tipo] });
  const indiceMena = new Map();
  for (const m of mundo.menas) indiceMena.set(m.id, flora.agregar(m.x, 0.02, m.z, R[`cobre${m.variante}_0`]));
  escena.add(flora.mesh);

  const vfx = new CapaSprites(600, texAtlas, 512);
  escena.add(vfx.mesh);
  const particulas = new Particulas(R);

  // --- industria y ciudad (3D) ------------------------------------------------
  const industria = await crearIndustria(escena);

  // --- simulación -------------------------------------------------------------
  const sim = new Simulacion({
    menas: mundo.menas, descarga: DESCARGA,
    muelle: { x: (ZONAS.muelle.x0 + ZONAS.muelle.x1) / 2, z: ZONAS.muelle.z0 + 1.6 },
    cinta1: CINTA1.x1 - CINTA1.x0, cinta2: CINTA2.x1 - CINTA2.x0,
  });
  const visuales = new Map();

  // --- cámara ortográfica con zoom entero por texel ----------------------------
  const camara = new THREE.OrthographicCamera(-1, 1, 1, -1, 1, 300);
  const niveles = [1, 2, 3, 4, 6, 8].filter(k => k <= 4 * dpr);
  const cam = { x: 5, z: 2, yaw: 0, yawObj: 0, pitch: THREE.MathUtils.degToRad(52), nivel: niveles.indexOf(2 * dpr), k: 2 * dpr };
  if (cam.nivel < 0) { cam.nivel = 1; cam.k = niveles[1]; }

  function ajustarCamara() {
    const W = renderer.domElement.width, H = renderer.domElement.height;
    const mh = H / (2 * P.PPM * cam.k), mw = W / (2 * P.PPM * cam.k);
    Object.assign(camara, { left: -mw, right: mw, top: mh, bottom: -mh });
    camara.updateProjectionMatrix();
    const cp = Math.cos(cam.pitch), sp = Math.sin(cam.pitch);
    const fwd = new THREE.Vector3(-Math.sin(cam.yaw) * cp, -sp, -Math.cos(cam.yaw) * cp);
    const right = new THREE.Vector3(Math.cos(cam.yaw), 0, -Math.sin(cam.yaw));
    const up = new THREE.Vector3().crossVectors(right, fwd);
    // Ajuste a la rejilla de píxeles de pantalla: evita el «temblor» del pixel art al desplazar.
    const paso = 1 / (P.PPM * cam.k);
    const t = new THREE.Vector3(cam.x, 0, cam.z);
    const a = Math.round(t.dot(right) / paso) * paso, b = Math.round(t.dot(up) / paso) * paso, c = t.dot(fwd);
    const ts = right.multiplyScalar(a).add(up.clone().multiplyScalar(b)).add(fwd.clone().multiplyScalar(c));
    camara.position.copy(ts).addScaledVector(fwd, -120);
    camara.up.copy(up);
    camara.lookAt(ts);
  }

  function redimensionar() {
    renderer.setSize(window.innerWidth, window.innerHeight, false);
    ajustarCamara();
  }
  window.addEventListener('resize', redimensionar);
  redimensionar();

  // --- capas visibles -----------------------------------------------------------
  const capas = {
    terreno: [suelo],
    flora: [flora.mesh],
    vfx: [vfx.mesh],
    fabrica: [industria.fabrica],
    ciudad: [industria.urbe],
    robots: [],
  };
  const capaRobots = new THREE.Group();
  escena.add(capaRobots);
  capas.robots.push(capaRobots);
  document.querySelectorAll('[data-capa]').forEach(chk => chk.addEventListener('change', () => {
    for (const o of capas[chk.dataset.capa]) o.visible = chk.checked;
  }));

  // --- proyección a pantalla para etiquetas y selección de menas --------------------
  const v3 = new THREE.Vector3();
  function aPantalla(p) {
    v3.copy(p).project(camara);
    return { x: (v3.x * 0.5 + 0.5) * window.innerWidth, y: (-v3.y * 0.5 + 0.5) * window.innerHeight };
  }
  const etiquetas = $('#etiquetas');
  function etiqueta(clase) { const d = document.createElement('div'); d.className = `etq ${clase}`; etiquetas.appendChild(d); return d; }
  const etqFun = etiqueta('maquina'), etqEns = etiqueta('maquina'), etqRec = etiqueta('maquina');
  const etqSel = etiqueta('robot');
  const flotantes = [];
  function flotante(texto, pos, clase = '') {
    const d = etiqueta(`flota ${clase}`);
    d.textContent = texto;
    flotantes.push({ d, pos: pos.clone(), t: 0 });
  }

  // --- entrada ---------------------------------------------------------------
  let seleccion = null, pausa = false, velocidad = 1;
  const teclas = new Set();
  window.addEventListener('keydown', (e) => {
    teclas.add(e.key.toLowerCase());
    if (e.key === ' ') { e.preventDefault(); alternarPausa(); }
    if (e.key === 'q') cam.yawObj += Math.PI / 4;
    if (e.key === 'e') cam.yawObj -= Math.PI / 4;
    if (e.key === 'Escape') seleccionar(null);
    if (e.key === 'r' && seleccion) sim.reanudar(robotSel());
    if (e.key === 'b') comprar();
    if (['1', '2', '3'].includes(e.key)) ponerVelocidad([1, 2, 4][+e.key - 1]);
  });
  window.addEventListener('keyup', (e) => teclas.delete(e.key.toLowerCase()));
  window.addEventListener('blur', () => teclas.clear());

  lienzo.addEventListener('wheel', (e) => {
    e.preventDefault();
    cam.nivel = THREE.MathUtils.clamp(cam.nivel + (e.deltaY < 0 ? 1 : -1), 0, niveles.length - 1);
  }, { passive: false });

  let arrastre = null;
  lienzo.addEventListener('pointerdown', (e) => {
    arrastre = { x: e.clientX, y: e.clientY, cx: cam.x, cz: cam.z, movio: false, boton: e.button };
    lienzo.setPointerCapture(e.pointerId);
  });
  lienzo.addEventListener('pointermove', (e) => {
    if (!arrastre) { lienzo.style.cursor = objetoBajo(e.clientX, e.clientY) ? 'pointer' : 'default'; return; }
    const dx = e.clientX - arrastre.x, dy = e.clientY - arrastre.y;
    if (Math.hypot(dx, dy) > 5) arrastre.movio = true;
    if (!arrastre.movio) return;
    const ppm = (P.PPM * cam.k) / dpr; // píxeles CSS por metro
    const s = Math.sin(cam.yaw), c = Math.cos(cam.yaw);
    const mx = -dx / ppm, mz = -dy / (ppm * Math.sin(cam.pitch));
    cam.x = arrastre.cx + mx * c + mz * s;
    cam.z = arrastre.cz - mx * s + mz * c;
    lienzo.style.cursor = 'grabbing';
  });
  lienzo.addEventListener('pointerup', (e) => {
    const a = arrastre;
    arrastre = null;
    lienzo.style.cursor = 'default';
    if (!a || a.movio || a.boton !== 0) return;
    clic(e.clientX, e.clientY);
  });
  lienzo.addEventListener('contextmenu', (e) => e.preventDefault());

  const raycaster = new THREE.Raycaster();
  const plano = new THREE.Plane(new THREE.Vector3(0, 1, 0), 0);
  function rayo(cx, cy) {
    raycaster.setFromCamera(new THREE.Vector2((cx / window.innerWidth) * 2 - 1, -(cy / window.innerHeight) * 2 + 1), camara);
    return raycaster;
  }
  function robotBajo(cx, cy) {
    const hit = rayo(cx, cy).intersectObjects(capaRobots.children, true)[0];
    return hit ? hit.object.userData.robotId : null;
  }
  function menaBajo(cx, cy) {
    const escala = cam.k / dpr;
    let mejor = null, dist = Infinity;
    for (const m of mundo.menas) {
      const p = aPantalla(v3.set(m.x, 0.02, m.z).clone());
      const w = 19 * escala, h = 15 * escala;
      if (cx < p.x - w / 2 || cx > p.x + w / 2 || cy < p.y - h || cy > p.y) continue;
      const d = Math.abs(cy - (p.y - h / 2));
      if (d < dist) { dist = d; mejor = m; }
    }
    return mejor;
  }
  const objetoBajo = (cx, cy) => robotBajo(cx, cy) || (seleccion && menaBajo(cx, cy));
  const robotSel = () => sim.robots.find(r => r.id === seleccion);

  function seleccionar(id) {
    seleccion = id;
    $('#inspector').hidden = !id;
    actualizarInspector();
  }

  function clic(cx, cy) {
    const id = robotBajo(cx, cy);
    if (id) { seleccionar(id); return; }
    const r = robotSel();
    if (!r) return;
    const m = menaBajo(cx, cy);
    if (m) {
      sim.asignarMena(r, m.id);
      particulas.emitir('destello', m.x, 0.5, m.z);
      aviso(`R${r.id} → mena #${m.id}`);
      return;
    }
    const p = rayo(cx, cy).ray.intersectPlane(plano, new THREE.Vector3());
    if (!p || Math.abs(p.x) > MITAD - 0.5 || Math.abs(p.z) > MITAD - 0.5) return;
    sim.moverManual(r, p.x, p.z);
    particulas.emitir('destello', p.x, 0.05, p.z);
    aviso(`R${r.id}: control manual. Pulsa R para reanudar la rutina.`);
  }

  // --- interfaz ----------------------------------------------------------------
  function alternarPausa() {
    pausa = !pausa;
    $('#pausa').textContent = pausa ? 'Reanudar' : 'Pausa';
    $('#pausa').setAttribute('aria-pressed', pausa);
    document.body.classList.toggle('pausado', pausa);
  }
  function ponerVelocidad(v) {
    velocidad = v;
    document.querySelectorAll('[data-vel]').forEach(b => b.setAttribute('aria-pressed', +b.dataset.vel === v));
  }
  function comprar() {
    if (!sim.comprarRobot()) { aviso(`Faltan créditos: un robot cuesta ${CFG.costoRobot} ₵.`); return; }
  }
  let temporizadorAviso;
  function aviso(texto) {
    const a = $('#aviso');
    a.textContent = texto;
    a.classList.add('visible');
    clearTimeout(temporizadorAviso);
    temporizadorAviso = setTimeout(() => a.classList.remove('visible'), 2600);
  }
  $('#pausa').addEventListener('click', alternarPausa);
  document.querySelectorAll('[data-vel]').forEach(b => b.addEventListener('click', () => ponerVelocidad(+b.dataset.vel)));
  $('#comprar').addEventListener('click', comprar);
  $('#reanudar').addEventListener('click', () => { const r = robotSel(); if (r) sim.reanudar(r); });
  $('#cerrar-inspector').addEventListener('click', () => seleccionar(null));

  const NOMBRE_ESTADO = {
    buscando: 'Buscando mena', yendo_mena: 'Yendo a la mena', minando: 'Recogiendo cobre',
    yendo_fundidora: 'Llevando cobre', descargando: 'Entregando', esperando: 'Esperando: tolva llena',
    manual: 'Control manual', detenido: 'Detenido (manual)',
  };
  function actualizarInspector() {
    const r = robotSel();
    if (!r) return;
    $('#ins-id').textContent = `R${r.id}`;
    $('#ins-estado').textContent = NOMBRE_ESTADO[r.estado] || r.estado;
    $('#ins-carga').textContent = r.carga ? 'cobre (sprite 2D)' : 'vacío';
    $('#ins-mena').textContent = r.menaAsignada ? `#${r.menaAsignada} (asignada)` : r.mena ? `#${r.mena} (la elige la rutina)` : '—';
    $('#reanudar').hidden = r.modo !== 'manual';
    const activa = r.modo === 'manual' ? -1 : LINEA[r.estado];
    $('#programa').innerHTML = (r.modo === 'manual'
      ? ['// rutina en pausa: control manual', ...PROGRAMA]
      : PROGRAMA).map((l, i) => {
        const idx = r.modo === 'manual' ? i - 1 : i;
        const texto = l.replaceAll('{id}', `r${r.id}`).replace(/[<>&]/g, c => ({ '<': '&lt;', '>': '&gt;', '&': '&amp;' }[c]));
        return `<span class="${idx === activa ? 'activa' : ''}${l.startsWith('//') ? ' comentario' : ''}">${texto}</span>`;
      }).join('');
  }
  function actualizarHUD() {
    $('#creditos').textContent = sim.creditos;
    $('#n-robots').textContent = sim.robots.length;
    $('#n-cobre').textContent = sim.fundidora.cobre;
    $('#n-lingotes').textContent = sim.ensambladora.lingotes + sim.cinta1.items.length;
    $('#n-chips').textContent = sim.vendidos;
    $('#comprar').disabled = sim.creditos < CFG.costoRobot;
    etqFun.innerHTML = `<b>Fundidora</b> ${sim.fundidora.cobre}/${CFG.capFundidora} cobre`;
    etqEns.innerHTML = `<b>Ensambladora</b> ${sim.ensambladora.lingotes}/${CFG.capEnsambladora} lingotes`;
    etqRec.innerHTML = `<b>Ciudad</b> ${sim.vendidos} chips`;
    actualizarInspector();
  }

  // --- eventos de simulación → presentación -----------------------------------
  const frameMena = (n) => n >= 4 ? 0 : n >= 2 ? 1 : n >= 1 ? 2 : 3;
  function procesarEventos() {
    for (const ev of sim.eventos) {
      switch (ev.tipo) {
        case 'robot': {
          const vis = new RobotVisual(ev.robot, capaRobots);
          visuales.set(ev.robot.id, vis);
          particulas.emitir('destello', ev.robot.x, 0.9, ev.robot.z);
          if (ev.robot.id > 2) aviso(`Nuevo robot R${ev.robot.id} en el muelle.`);
          break;
        }
        case 'minado':
          particulas.emitir('polvo', ev.mena.x, 0.1, ev.mena.z, 4);
          particulas.emitir('chispa', ev.mena.x, 0.45, ev.mena.z, 5);
        // fallthrough
        case 'agotada':
        case 'regenera': {
          const m = mundo.menas.find(q => q.id === ev.mena.id);
          flora.cambiarSprite(indiceMena.get(m.id), R[`cobre${m.variante}_${frameMena(ev.mena.cantidad)}`]);
          if (ev.tipo === 'regenera') particulas.emitir('destello', m.x, 0.5, m.z);
          break;
        }
        case 'descarga':
          particulas.emitir('polvo', industria.anclas.tolva.x, industria.anclas.tolva.y, industria.anclas.tolva.z, 3);
          break;
        case 'chip':
          particulas.emitir('humo', industria.anclas.chimeneaEns.x, industria.anclas.chimeneaEns.y, industria.anclas.chimeneaEns.z, 2);
          mundo.contaminar(sim.fabricados);
          break;
        case 'venta':
          flotante(`+${ev.valor} ₵`, industria.anclas.recepcion, 'credito');
          particulas.emitir('destello', industria.anclas.recepcion.x, industria.anclas.recepcion.y, industria.anclas.recepcion.z);
          break;
      }
    }
    sim.eventos.length = 0;
  }

  // --- bucle ------------------------------------------------------------------
  const vCarga = new THREE.Vector3();
  let acumulado = 0, anterior = performance.now(), reloj = 0, tHumo = 0, tHumoEns = 0, tHUD = 0, tSuelo = 0;
  procesarEventos();
  actualizarHUD();
  $('#carga').classList.add('oculto');

  function cuadro(ahora) {
    const dt = Math.min(0.1, (ahora - anterior) / 1000);
    anterior = ahora;
    reloj += dt;
    const dtSim = pausa ? 0 : dt * velocidad;

    // cámara
    const s = Math.sin(cam.yaw), c = Math.cos(cam.yaw), vel = 14 * dt * (4 * dpr / cam.k);
    let mx = 0, mz = 0;
    if (teclas.has('a') || teclas.has('arrowleft')) mx -= 1;
    if (teclas.has('d') || teclas.has('arrowright')) mx += 1;
    if (teclas.has('w') || teclas.has('arrowup')) mz -= 1;
    if (teclas.has('s') || teclas.has('arrowdown')) mz += 1;
    cam.x += (mx * c + mz * s) * vel;
    cam.z += (-mx * s + mz * c) * vel;
    cam.x = THREE.MathUtils.clamp(cam.x, -MITAD + 4, MITAD - 4);
    cam.z = THREE.MathUtils.clamp(cam.z, -MITAD + 4, MITAD - 4);
    cam.yaw += (cam.yawObj - cam.yaw) * Math.min(1, dt * 8);
    if (Math.abs(cam.yawObj - cam.yaw) < 1e-3) cam.yaw = cam.yawObj;
    const kObj = niveles[cam.nivel];
    cam.k += (kObj - cam.k) * Math.min(1, dt * 12);
    if (Math.abs(kObj - cam.k) < 0.01) cam.k = kObj;
    ajustarCamara();

    // simulación a paso fijo
    acumulado += dtSim;
    const pasoSim = 1 / CFG.hz;
    while (acumulado >= pasoSim) { sim.paso(); acumulado -= pasoSim; }
    const alfa = acumulado / pasoSim;
    procesarEventos();

    // robots y carga natural
    vfx.vaciar();
    for (const r of sim.robots) {
      const vis = visuales.get(r.id);
      const enMarcha = vis.actualizar(r, alfa, dt, reloj, r.id === seleccion);
      if (enMarcha) {
        const rx = Math.cos(r.rumbo), rz = -Math.sin(r.rumbo);
        for (const lado of [-0.38, 0.38]) mundo.pisar(vis.g.position.x + rx * lado, vis.g.position.z + rz * lado);
      }
      if (r.carga) {
        const p = vis.puntoCarga(vCarga);
        vfx.escribir(vfx.n++, p.x, p.y, p.z, R.mena);
      }
    }

    // humo de chimeneas
    tHumo -= dtSim; tHumoEns -= dtSim;
    if (tHumo < 0) { const a = industria.anclas.chimenea; particulas.emitir('humo', a.x, a.y, a.z); tHumo = sim.fundidora.trabajando ? 0.35 : 1.6; }
    if (sim.ensambladora.trabajando && tHumoEns < 0) { const a = industria.anclas.chimeneaEns; particulas.emitir('humo', a.x, a.y, a.z); tHumoEns = 0.6; }
    particulas.actualizar(dtSim);
    particulas.dibujar(vfx);
    vfx.cerrar();

    industria.actualizar(dtSim, sim, alfa);
    flora.material.uniforms.uTime.value = reloj;
    mundo.animarAgua(reloj);
    tSuelo -= dt;
    if (tSuelo < 0) { mundo.subir(); tSuelo = 0.2; }

    renderer.render(escena, camara);

    // etiquetas HTML
    const colocar = (el, p, dy = 0) => {
      const q = aPantalla(p);
      el.style.transform = `translate(${q.x}px, ${q.y + dy}px) translate(-50%, -100%)`;
    };
    colocar(etqFun, industria.anclas.fundidora.clone().setY(4.4));
    colocar(etqEns, industria.anclas.ensambladora.clone().setY(3.3));
    colocar(etqRec, industria.anclas.recepcion.clone().setY(2.2));
    const rs = robotSel();
    etqSel.hidden = !rs;
    if (rs) {
      etqSel.textContent = `R${rs.id}`;
      colocar(etqSel, visuales.get(rs.id).g.position.clone().setY(1.9));
    }
    for (const f of flotantes) {
      f.t += dt;
      colocar(f.d, f.pos, -f.t * 40);
      f.d.style.opacity = 1 - f.t / 1.6;
    }
    for (let i = flotantes.length - 1; i >= 0; i--) if (flotantes[i].t > 1.6) { flotantes[i].d.remove(); flotantes.splice(i, 1); }

    tHUD -= dt;
    if (tHUD < 0) { actualizarHUD(); tHUD = 0.2; }
    requestAnimationFrame(cuadro);
  }
  requestAnimationFrame(cuadro);

  // Ganchos de inspección para pruebas automatizadas desde la consola.
  window.codemageddon = { sim, mundo, camara, renderer, cam };
}

iniciar().catch((e) => {
  console.error(e);
  $('#carga').textContent = `Error al iniciar: ${e.message}`;
});

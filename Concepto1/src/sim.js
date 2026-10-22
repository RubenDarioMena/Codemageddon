// Simulación a reloj fijo, solo datos. No conoce Three.js ni cómo se dibuja cada cosa:
// publica estados y eventos que la presentación traduce (sprite, piezas 3D o mezcla).
export const CFG = {
  hz: 20,
  velRobot: 2.3,
  tMinar: 1.3,
  tDescargar: 0.45,
  tFundir: 1.8,
  tEnsamblar: 2.6,
  lingotesPorChip: 2,
  valorChip: 6,
  costoRobot: 15,
  capFundidora: 8,
  capEnsambladora: 4,
  velCinta: 1.25,
  separacion: 0.6,
  cobrePorMena: 6,
  tRegenerar: 35,
};

// Líneas del pseudoprograma que se resaltan según el estado del robot.
export const PROGRAMA = [
  'while (true) {',
  '  const m = {id}.buscarMena();',
  '  await {id}.ir(m);',
  '  await {id}.recoger(m);',
  '  await {id}.ir("fundidora");',
  '  await {id}.entregar("fundidora");',
  '}',
];
export const LINEA = { buscando: 1, yendo_mena: 2, minando: 3, yendo_fundidora: 4, descargando: 5, esperando: 5 };

export class Simulacion {
  constructor({ menas, descarga, muelle, cinta1, cinta2 }) {
    this.t = 0;
    this.creditos = 0;
    this.vendidos = 0;
    this.fabricados = 0;
    this.eventos = [];
    this.descarga = descarga;
    this.muelle = muelle;
    this.menas = menas.map(m => ({ id: m.id, x: m.x, z: m.z, cantidad: CFG.cobrePorMena, regen: 0 }));
    this.fundidora = { cobre: 0, progreso: 0, trabajando: false, listo: false };
    this.ensambladora = { lingotes: 0, progreso: 0, trabajando: false, listo: false };
    this.cinta1 = { largo: cinta1, items: [] };
    this.cinta2 = { largo: cinta2, items: [] };
    this.robots = [];
    this.siguienteItem = 1;
    this.nuevoRobot();
    this.nuevoRobot();
  }

  nuevoRobot() {
    const n = this.robots.length;
    const r = {
      id: n + 1, x: this.muelle.x + (n % 3) * 0.9 - 0.9, z: this.muelle.z + ((n / 3) | 0) * 0.9,
      rumbo: Math.PI, estado: 'buscando', carga: null, modo: 'rutina', menaAsignada: null,
      mena: null, objetivo: null, timer: 0, distancia: 0,
    };
    r.px = r.x; r.pz = r.z; r.prumbo = r.rumbo;
    this.robots.push(r);
    this.eventos.push({ tipo: 'robot', robot: r });
    return r;
  }

  comprarRobot() {
    if (this.creditos < CFG.costoRobot) return false;
    this.creditos -= CFG.costoRobot;
    this.nuevoRobot();
    return true;
  }

  // Órdenes del jugador: las mismas reglas que la rutina, sin atajos «inteligentes».
  asignarMena(robot, menaId) {
    robot.menaAsignada = menaId;
    robot.modo = 'rutina';
    if (!robot.carga) { robot.estado = 'buscando'; robot.timer = 0; }
  }
  moverManual(robot, x, z) {
    robot.modo = 'manual';
    robot.estado = 'manual';
    robot.objetivo = { x, z };
  }
  reanudar(robot) {
    robot.modo = 'rutina';
    robot.estado = robot.carga ? 'yendo_fundidora' : 'buscando';
    robot.objetivo = robot.carga ? this.puntoDescarga(robot) : null;
  }

  puntoDescarga(robot) {
    return { x: this.descarga.x - 0.15, z: this.descarga.z + ((robot.id % 3) - 1) * 0.7 };
  }

  paso() {
    const dt = 1 / CFG.hz;
    this.t += dt;
    for (const r of this.robots) {
      r.px = r.x; r.pz = r.z; r.prumbo = r.rumbo;
      this.pasoRobot(r, dt);
      r.rumbo = Math.atan2(Math.sin(r.rumbo), Math.cos(r.rumbo));
    }
    this.separar();
    for (const c of [this.cinta1, this.cinta2]) for (const it of c.items) it.ps = it.s;
    this.pasoFundidora(dt);
    this.pasoCinta(this.cinta1, dt, () => {
      if (this.ensambladora.lingotes >= CFG.capEnsambladora) return false;
      this.ensambladora.lingotes++;
      return true;
    });
    this.pasoEnsambladora(dt);
    this.pasoCinta(this.cinta2, dt, () => {
      this.creditos += CFG.valorChip;
      this.vendidos++;
      this.eventos.push({ tipo: 'venta', valor: CFG.valorChip });
      return true;
    });
    for (const m of this.menas) {
      if (m.cantidad > 0) continue;
      m.regen += dt;
      if (m.regen >= CFG.tRegenerar) { m.cantidad = CFG.cobrePorMena; m.regen = 0; this.eventos.push({ tipo: 'regenera', mena: m }); }
    }
  }

  elegirMena(r) {
    const asignada = this.menas.find(m => m.id === r.menaAsignada && m.cantidad > 0);
    if (asignada) return asignada;
    let mejor = null, coste = Infinity;
    for (const m of this.menas) {
      if (m.cantidad <= 0) continue;
      const ocupacion = this.robots.filter(o => o !== r && o.mena === m.id).length;
      const c = Math.hypot(m.x - this.descarga.x, m.z - this.descarga.z) + ocupacion * 6 + Math.hypot(m.x - r.x, m.z - r.z) * 0.3;
      if (c < coste) { coste = c; mejor = m; }
    }
    return mejor;
  }

  mover(r, dt) {
    const dx = r.objetivo.x - r.x, dz = r.objetivo.z - r.z, d = Math.hypot(dx, dz);
    const deseado = Math.atan2(dx, dz);
    let giro = ((deseado - r.rumbo + Math.PI * 3) % (Math.PI * 2)) - Math.PI;
    r.rumbo += Math.max(-7 * dt, Math.min(7 * dt, giro));
    const v = CFG.velRobot * dt * (Math.abs(giro) > 1.2 ? 0.35 : 1);
    if (d <= v) { r.x = r.objetivo.x; r.z = r.objetivo.z; r.distancia += d; return true; }
    r.x += (dx / d) * v; r.z += (dz / d) * v; r.distancia += v;
    return false;
  }

  pasoRobot(r, dt) {
    switch (r.estado) {
      case 'buscando': {
        const m = this.elegirMena(r);
        if (!m) { r.mena = null; break; }
        r.mena = m.id;
        const ang = Math.atan2(this.descarga.x - m.x, this.descarga.z - m.z);
        r.objetivo = { x: m.x + Math.sin(ang) * 0.8, z: m.z + Math.cos(ang) * 0.8 };
        r.estado = 'yendo_mena';
        break;
      }
      case 'yendo_mena':
        if (this.mover(r, dt)) { r.estado = 'minando'; r.timer = 0; }
        break;
      case 'minando': {
        const m = this.menas.find(q => q.id === r.mena);
        const ang = Math.atan2(m.x - r.x, m.z - r.z);
        r.rumbo += (((ang - r.rumbo + Math.PI * 3) % (Math.PI * 2)) - Math.PI) * Math.min(1, dt * 8);
        r.timer += dt;
        if (r.timer < CFG.tMinar) break;
        if (m.cantidad > 0) {
          // Recoger en una mena agotada es un movimiento vacío, no un error de programa.
          m.cantidad--;
          r.carga = 'cobre';
          this.eventos.push({ tipo: 'minado', mena: m, robot: r });
          if (m.cantidad === 0) this.eventos.push({ tipo: 'agotada', mena: m });
          r.estado = 'yendo_fundidora';
          r.objetivo = this.puntoDescarga(r);
        } else r.estado = 'buscando';
        break;
      }
      case 'yendo_fundidora':
        if (this.mover(r, dt)) { r.estado = 'descargando'; r.timer = 0; }
        break;
      case 'descargando':
      case 'esperando': {
        r.rumbo += (((Math.PI / 2 - r.rumbo + Math.PI * 3) % (Math.PI * 2)) - Math.PI) * Math.min(1, dt * 8);
        if (this.fundidora.cobre >= CFG.capFundidora) { r.estado = 'esperando'; break; }
        r.estado = 'descargando';
        r.timer += dt;
        if (r.timer < CFG.tDescargar) break;
        this.fundidora.cobre++;
        r.carga = null;
        this.eventos.push({ tipo: 'descarga', robot: r });
        r.estado = 'buscando';
        break;
      }
      case 'manual':
        if (this.mover(r, dt)) r.estado = 'detenido';
        break;
    }
  }

  separar() {
    const rs = this.robots;
    for (let i = 0; i < rs.length; i++) for (let j = i + 1; j < rs.length; j++) {
      const a = rs[i], b = rs[j];
      const dx = b.x - a.x, dz = b.z - a.z, d = Math.hypot(dx, dz);
      if (d > 0.95 || d < 1e-4) continue;
      const k = (0.95 - d) * 0.25;
      a.x -= (dx / d) * k; a.z -= (dz / d) * k;
      b.x += (dx / d) * k; b.z += (dz / d) * k;
    }
  }

  meter(cinta, tipo) {
    if (cinta.items.length && cinta.items[cinta.items.length - 1].s < CFG.separacion) return false;
    cinta.items.push({ id: this.siguienteItem++, tipo, s: 0, ps: 0 });
    return true;
  }

  pasoCinta(c, dt, entregar) {
    for (let k = 0; k < c.items.length; k++) {
      const it = c.items[k];
      const limite = k === 0 ? c.largo : c.items[k - 1].s - CFG.separacion;
      it.s = Math.min(it.s + CFG.velCinta * dt, Math.max(it.s, limite));
    }
    if (c.items.length && c.items[0].s >= c.largo && entregar()) c.items.shift();
  }

  pasoFundidora(dt) {
    const f = this.fundidora;
    if (f.listo && this.meter(this.cinta1, 'lingote')) f.listo = false;
    if (!f.trabajando && !f.listo && f.cobre > 0) { f.cobre--; f.trabajando = true; f.progreso = 0; }
    if (!f.trabajando) return;
    f.progreso += dt / CFG.tFundir;
    if (f.progreso >= 1) { f.trabajando = false; f.listo = true; this.eventos.push({ tipo: 'fundido' }); }
  }

  pasoEnsambladora(dt) {
    const e = this.ensambladora;
    if (e.listo && this.meter(this.cinta2, 'chip')) e.listo = false;
    if (!e.trabajando && !e.listo && e.lingotes >= CFG.lingotesPorChip) {
      e.lingotes -= CFG.lingotesPorChip; e.trabajando = true; e.progreso = 0;
    }
    if (!e.trabajando) return;
    e.progreso += dt / CFG.tEnsamblar;
    if (e.progreso >= 1) {
      e.trabajando = false; e.listo = true; this.fabricados++;
      this.eventos.push({ tipo: 'chip' });
    }
  }
}

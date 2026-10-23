// Servicio de Codemageddon para la versión WEB: el mismo protocolo que servicio/main.mjs (Node),
// pero dentro del navegador.
//
//  · PostgreSQL: PGlite (Postgres compilado a WASM), servido junto a la demo en ./pglite/.
//  · Programas de los robots: un Web Worker clásico por robot, creado desde un Blob que contiene
//    la API del juego (PRELUDIO) y el código del jugador. Mismas órdenes asíncronas, mismos
//    resultados, mismo vigilante de bucles sin await.
//
// Godot habla con este módulo mediante JavaScriptBridge:
//   window.cmg.enviar(json)  → Godot envía un mensaje
//   window.cmg.recibir()     → Godot recoge los mensajes pendientes (JSON de una lista)

import { PGlite } from './pglite/index.js'

const salida = []
const enviar = m => salida.push(m)
const json = v => JSON.stringify(v, (_, x) => (typeof x === 'bigint' ? Number(x) : x))

window.cmg = {
  listo: false,
  enviar(texto) {
    try { atender(JSON.parse(texto)) } catch (e) { console.error('cmg: mensaje inválido', e) }
  },
  recibir() {
    if (!salida.length) return ''
    const s = json(salida)
    salida.length = 0
    return s
  },
}

let db
let version = 'PostgreSQL'
try {
  db = await PGlite.create()
  version = (await db.query('SELECT version() AS v')).rows[0].v
  window.cmg.listo = true
} catch (e) {
  window.cmgError = 'PGlite no arrancó: ' + e.message
  throw e
}

let cola = Promise.resolve()
const enCola = fn => (cola = cola.then(fn).catch(e => console.error('cmg', e)))
const IDENT = /^[a-z_][a-z0-9_]*$/

async function insertar(tabla, filas) {
  if (!filas.length || !IDENT.test(tabla)) return
  const cols = Object.keys(filas[0]).filter(c => IDENT.test(c))
  for (let i = 0; i < filas.length; i += 200) {
    const lote = filas.slice(i, i + 200)
    const params = []
    const valores = lote.map(f => '(' + cols.map(c => { params.push(f[c] ?? null); return '$' + params.length }).join(', ') + ')')
    await db.query(`INSERT INTO ${tabla} (${cols.join(', ')}) VALUES ${valores.join(', ')}`, params)
  }
}

async function consultar(sql) {
  const t0 = performance.now()
  try {
    const res = await db.exec(sql)
    const ultima = res.length ? res[res.length - 1] : { fields: [], rows: [], affectedRows: 0 }
    const columnas = ultima.fields.map(f => f.name)
    return { ok: true, columnas, filas: ultima.rows.map(r => columnas.map(c => r[c])), afectadas: ultima.affectedRows ?? 0, ms: performance.now() - t0, error: '' }
  } catch (e) {
    return { ok: false, columnas: [], filas: [], afectadas: 0, ms: performance.now() - t0, error: e.message }
  }
}

// ---------------------------------------------------------------- programas de los robots

const workers = new Map()
let estado = {}

// API del juego dentro del worker. Debe coincidir con servicio/runtime_robot.mjs (Node).
const PRELUDIO = `
'use strict';
const ID = self.__ID, NIVEL = self.__NIVEL;
let estado = self.__ESTADO || {};
let ticket = 0, qid = 0;
const pendientes = new Map(), consultas = new Map();
const enviar = m => postMessage(m);
setInterval(() => enviar({ op: 'latido' }), 400);
onmessage = e => {
  const m = e.data;
  if (m.op === 'estado') estado = m.estado;
  else if (m.op === 'resultado') {
    if (m.estado) estado = m.estado;
    const r = pendientes.get(m.ticket);
    if (r) { pendientes.delete(m.ticket); r(m.resultado); }
  } else if (m.op === 'sql_res') {
    const p = consultas.get(m.qid);
    if (!p) return;
    consultas.delete(m.qid);
    if (m.error) p.rechazar(new Error('SQL: ' + m.error)); else p.resolver(m.filas);
  }
};
function lineaActual(err = new Error()) {
  for (const l of String(err.stack).split('\\n')) {
    const m = l.match(/:(\\d+):\\d+\\)?\\s*$/);
    if (m && Number(m[1]) > self.__DESPLAZAMIENTO) return Number(m[1]) - self.__DESPLAZAMIENTO;
  }
  return 0;
}
const texto = v => { if (typeof v === 'string') return v; try { return JSON.stringify(v); } catch { return String(v); } };
function orden(datos) {
  const t = ++ticket, linea = lineaActual();
  return new Promise(res => { pendientes.set(t, res); enviar({ op: 'accion', robot: ID, ticket: t, linea, orden: datos }); });
}
function requiereNivel(n, que) { if (NIVEL < n) throw new Error(que + ' requiere un robot T' + n + '. Este es T' + NIVEL + '.'); }
function idDe(x) {
  if (typeof x === 'string') return x;
  if (x && typeof x.id === 'string') return x.id;
  throw new Error('Se esperaba un identificador como "FUN-01" o un objeto con .id');
}
class RobotAPI {
  constructor(id) { this.id = id; }
  get _d() { return (estado.robots || {})[this.id] || {}; }
  get nivel() { return this._d.nivel; }
  get x() { return this._d.x; }
  get z() { return this._d.z; }
  get carga() { return this._d.carga ?? null; }
  get cantidad() { return this._d.cantidad ?? 0; }
  get capacidad() { return this._d.capacidad ?? 0; }
  get estado() { return this._d.estado; }
  _mio(que) { if (this.id !== ID) throw new Error('Solo puedes dar órdenes a tu propio robot (robots[' + ID + ']), no a robots[' + this.id + '] (' + que + ').'); }
  ir(x, z) { this._mio('ir'); return orden({ tipo: 'mover', x: Math.floor(x), z: Math.floor(z) }); }
  recoger(o, material = '') { this._mio('recoger'); return orden({ tipo: 'recoger', objetivo: idDe(o), material }); }
  entregar(o) { this._mio('entregar'); return orden({ tipo: 'entregar', objetivo: idDe(o) }); }
  reparar(o) { this._mio('reparar'); return orden({ tipo: 'reparar', objetivo: idDe(o) }); }
  esperar(s = 1) { this._mio('esperar'); return orden({ tipo: 'esperar', seg: Math.max(0.05, Number(s) || 0) }); }
  minar(m) { this._mio('minar'); requiereNivel(2, 'Minar (pala)'); return orden({ tipo: 'minar', objetivo: idDe(m) }); }
  buscarMena() {
    requiereNivel(2, 'buscarMena (sensor)');
    let mejor = null, d = Infinity;
    for (const m of estado.menas || []) {
      if (m.cantidad <= 0) continue;
      const dd = Math.hypot(m.x - this.x, m.z - this.z);
      if (dd < d) { d = dd; mejor = m; }
    }
    return mejor;
  }
  buscarMaquina(tipo, { conEspacio = false } = {}) {
    requiereNivel(2, 'buscarMaquina (sensor)');
    let mejor = null, d = Infinity;
    for (const id of Object.keys(estado.maquinas || {})) {
      const m = new MaquinaAPI(id);
      if (m.tipo !== tipo || m.estado === 'construyendo') continue;
      if (conEspacio && this.carga && m.espacio(this.carga) <= 0) continue;
      const dd = Math.hypot(m.x - this.x, m.z - this.z);
      if (dd < d) { d = dd; mejor = m; }
    }
    return mejor;
  }
  toString() { return 'robots[' + this.id + ']'; }
}
class MaquinaAPI {
  constructor(id) { this.id = id; }
  get _d() { return (estado.maquinas || {})[this.id]; }
  get existe() { return !!this._d; }
  get tipo() { return this._d?.tipo; }
  get estado() { return this._d?.estado; }
  get x() { return this._d?.x; }
  get z() { return this._d?.z; }
  get entrada() { return { ...(this._d?.entrada || {}) }; }
  get salida() { return { ...(this._d?.salida || {}) }; }
  espacio(material) {
    const d = this._d;
    if (!d || !(d.acepta || []).includes(material)) return 0;
    return Math.max(0, d.cap_entrada - ((d.entrada || {})[material] ?? 0));
  }
  toString() { return this.id; }
}
const robots = new Proxy({}, { get: (_, k) => (typeof k === 'string' && /^\\d+$/.test(k) ? new RobotAPI(Number(k)) : undefined) });
const maquinas = new Proxy({}, {
  get: (_, k) => (typeof k === 'string' && (estado.maquinas || {})[k] ? new MaquinaAPI(k) : undefined),
  ownKeys: () => Object.keys(estado.maquinas || {}),
  getOwnPropertyDescriptor: (_, k) => ((estado.maquinas || {})[k] ? { enumerable: true, configurable: true, value: new MaquinaAPI(k) } : undefined),
});
const db = {
  query(sql, params = []) {
    const q = ++qid;
    return new Promise((resolver, rechazar) => { consultas.set(q, { resolver, rechazar }); enviar({ op: 'sql', qid: q, sql: String(sql), params }); });
  },
};
function log(...xs) { enviar({ op: 'log', robot: ID, texto: xs.map(texto).join(' '), linea: lineaActual() }); }
const yo = new RobotAPI(ID);
const reloj = { get hora() { return estado.hora; }, get dia() { return estado.dia; }, get t() { return estado.t; } };
Object.defineProperty(self, 'menas', { get: () => (estado.menas || []).map(m => ({ ...m })) });
self.__terminar = e => {
  if (e) enviar({ op: 'error', robot: ID, mensaje: (e.name || 'Error') + ': ' + e.message, linea: lineaActual(e) });
  else enviar({ op: 'log', robot: ID, texto: '(el programa terminó)', linea: 0 });
  enviar({ op: 'fin', robot: ID });
  close();
};
`

// Líneas del blob antes del código del jugador: las cabeceras, el preludio y la línea del envoltorio.
function fuenteWorker(robot, nivel, codigo) {
  const cabecera = `self.__ID = ${Number(robot)}; self.__NIVEL = ${Number(nivel)}; self.__ESTADO = ${json(estado)};\n`
  const antes = cabecera + PRELUDIO + '\n(async () => {\n'
  const desplazamiento = antes.split('\n').length - 1
  return (cabecera.replace('self.__ID', `self.__DESPLAZAMIENTO = ${desplazamiento}; self.__ID`)) + PRELUDIO + '\n(async () => {\n' +
    codigo + '\n})().then(() => self.__terminar(), e => self.__terminar(e));\n'
}

function detener(robot, motivo) {
  const w = workers.get(robot)
  if (!w) return
  workers.delete(robot)
  w.worker.terminate()
  URL.revokeObjectURL(w.url)
  if (motivo) enviar({ op: 'error', robot, ejecucion: w.ejecucion, mensaje: motivo, linea: 0 })
  enviar({ op: 'fin', robot, ejecucion: w.ejecucion })
}

function ejecutar(robot, nivel, codigo, ejecucion) {
  detener(robot)
  const fuente = fuenteWorker(robot, nivel, codigo)
  const desplazamiento = Number(fuente.match(/__DESPLAZAMIENTO = (\d+)/)[1])
  const url = URL.createObjectURL(new Blob([fuente], { type: 'text/javascript' }))
  const worker = new Worker(url)
  const w = { worker, url, latido: Date.now(), ejecucion }
  workers.set(robot, w)
  worker.onmessage = e => {
    // Mismo aislamiento de ejecuciones que en el servicio de escritorio.
    if (workers.get(robot) !== w) return
    const m = e.data
    w.latido = Date.now()
    m.ejecucion = ejecucion
    switch (m.op) {
      case 'latido':
        break
      case 'sql':
        enCola(async () => {
          if (workers.get(robot) !== w) return
          try {
            const r = m.params?.length ? await db.query(m.sql, m.params) : (await db.exec(m.sql)).at(-1) ?? { rows: [] }
            worker.postMessage(JSON.parse(json({ op: 'sql_res', qid: m.qid, filas: r.rows })))
          } catch (err) {
            worker.postMessage({ op: 'sql_res', qid: m.qid, error: err.message })
          }
        })
        break
      case 'fin':
        if (workers.get(robot) === w) { workers.delete(robot); URL.revokeObjectURL(url) }
        enviar({ op: 'fin', robot, ejecucion })
        break
      default:
        enviar(m)
    }
  }
  // Errores de sintaxis: el navegador los informa con la línea del blob.
  worker.onerror = e => {
    e.preventDefault()
    if (workers.get(robot) !== w) return
    const linea = e.lineno > desplazamiento ? e.lineno - desplazamiento : 0
    enviar({ op: 'error', robot, ejecucion, mensaje: e.message.replace(/^Uncaught /, ''), linea })
    if (workers.get(robot) === w) { workers.delete(robot); worker.terminate(); URL.revokeObjectURL(url) }
    enviar({ op: 'fin', robot, ejecucion })
  }
}

setInterval(() => {
  const ahora = Date.now()
  for (const [robot, w] of workers) {
    if (ahora - w.latido > 3000) {
      detener(robot, 'El programa estuvo 3 s sin ceder el control y se detuvo. ¿Falta un await (o un esperar) dentro de un bucle?')
    }
  }
}, 500)

// ---------------------------------------------------------------- mensajes de Godot

function atender(m) {
  switch (m.op) {
    case 'iniciar':
      enCola(async () => {
        try {
          await db.exec(m.esquema)
          enviar({ op: 'listo', motor: version.split(',')[0], pg: 0 })
        } catch (e) {
          enviar({ op: 'listo', motor: version, error: e.message })
        }
      })
      break
    case 'sql':
      enCola(async () => enviar({ op: 'res', id: m.id, ...(await consultar(m.sql)) }))
      break
    case 'insertar':
      enCola(async () => {
        try { await insertar(m.tabla, m.filas) } catch (e) { enviar({ op: 'aviso_db', tabla: m.tabla, error: e.message }) }
      })
      break
    case 'proyectar':
      enCola(async () => {
        try {
          await db.exec('BEGIN')
          await db.exec('DELETE FROM maquinas; DELETE FROM robots;')
          await insertar('maquinas', m.maquinas)
          await insertar('robots', m.robots)
          await db.exec('COMMIT')
        } catch (e) {
          await db.exec('ROLLBACK').catch(() => {})
          enviar({ op: 'aviso_db', tabla: 'proyeccion', error: e.message })
        }
      })
      break
    case 'estado':
      estado = m.estado
      for (const w of workers.values()) w.worker.postMessage({ op: 'estado', estado })
      break
    case 'resultado': {
      if (m.estado) estado = m.estado
      const w = workers.get(m.robot)
      if (w && w.ejecucion === m.ejecucion) w.worker.postMessage({ op: 'resultado', ticket: m.ticket, resultado: m.resultado, estado })
      break
    }
    case 'ejecutar':
      ejecutar(m.robot, m.nivel, m.codigo, m.ejecucion)
      break
    case 'detener':
      detener(m.robot)
      break
  }
}

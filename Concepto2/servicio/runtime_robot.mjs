// Runtime de UN programa de robot (se ejecuta en un worker_thread).
//
// El programa del jugador es JavaScript real. Solo ve la API del juego: no tiene `require`,
// `process`, archivos ni red. Las órdenes son asíncronas y se resuelven cuando la simulación
// termina la acción (respeta la pausa y la velocidad del juego).
//
// Esto NO es un sandbox de seguridad para código ajeno (GDD §10): es un entorno educativo.

import { parentPort, workerData } from 'node:worker_threads'
import vm from 'node:vm'

const { robot: ID, nivel: NIVEL, codigo } = workerData
let estado = workerData.estado ?? {}
let ticket = 0
let qid = 0
const pendientes = new Map()
const consultas = new Map()
const ARCHIVO = `robot${ID}.js`

const enviar = m => parentPort.postMessage(m)
setInterval(() => enviar({ op: 'latido' }), 400)

parentPort.on('message', m => {
  if (m.op === 'estado') estado = m.estado
  else if (m.op === 'resultado') {
    if (m.estado) estado = m.estado
    const res = pendientes.get(m.ticket)
    if (res) { pendientes.delete(m.ticket); res(m.resultado) }
  } else if (m.op === 'sql_res') {
    const p = consultas.get(m.qid)
    if (!p) return
    consultas.delete(m.qid)
    if (m.error) p.rechazar(new Error('SQL: ' + m.error))
    else p.resolver(m.filas)
  }
})

// Línea del programa del jugador que hizo la llamada (para resaltarla en el editor).
function lineaActual(err = new Error()) {
  for (const l of String(err.stack).split('\n')) {
    const m = l.match(new RegExp(ARCHIVO.replace('.', '\\.') + ':(\\d+)'))
    if (m) return Number(m[1])
  }
  return 0
}

function texto(v) {
  if (typeof v === 'string') return v
  try { return JSON.stringify(v) } catch { return String(v) }
}

function orden(datos) {
  const t = ++ticket
  const linea = lineaActual()
  return new Promise(resolver => {
    pendientes.set(t, resolver)
    enviar({ op: 'accion', robot: ID, ticket: t, linea, orden: datos })
  })
}

function requiereNivel(n, que) {
  if (NIVEL < n) throw new Error(`${que} requiere un robot T${n}. Este es T${NIVEL}.`)
}

function idDe(x) {
  if (typeof x === 'string') return x
  if (x && typeof x.id === 'string') return x.id
  throw new Error('Se esperaba un identificador como "FUN-01" o un objeto con .id')
}

// ---------------------------------------------------------------- objetos del mundo

class RobotAPI {
  constructor(id) { this.id = id }
  get #d() { return estado.robots?.[this.id] ?? {} }
  get nivel() { return this.#d.nivel }
  get x() { return this.#d.x }
  get z() { return this.#d.z }
  get carga() { return this.#d.carga ?? null }
  get cantidad() { return this.#d.cantidad ?? 0 }
  get capacidad() { return this.#d.capacidad ?? 0 }
  get estado() { return this.#d.estado }
  #mio(que) {
    if (this.id !== ID) throw new Error(`Solo puedes dar órdenes a tu propio robot (robots[${ID}]), no a robots[${this.id}] (${que}).`)
  }
  ir(x, z) { this.#mio('ir'); return orden({ tipo: 'mover', x: Math.floor(x), z: Math.floor(z) }) }
  recoger(objetivo, material = '') { this.#mio('recoger'); return orden({ tipo: 'recoger', objetivo: idDe(objetivo), material }) }
  entregar(objetivo) { this.#mio('entregar'); return orden({ tipo: 'entregar', objetivo: idDe(objetivo) }) }
  reparar(objetivo) { this.#mio('reparar'); return orden({ tipo: 'reparar', objetivo: idDe(objetivo) }) }
  esperar(segundos = 1) { this.#mio('esperar'); return orden({ tipo: 'esperar', seg: Math.max(0.05, Number(segundos) || 0) }) }
  minar(mena) { this.#mio('minar'); requiereNivel(2, 'Minar (pala)'); return orden({ tipo: 'minar', objetivo: idDe(mena) }) }
  // Sensores del explorador.
  buscarMena() {
    requiereNivel(2, 'buscarMena (sensor)')
    let mejor = null, d = Infinity
    for (const m of estado.menas ?? []) {
      if (m.cantidad <= 0) continue
      const dd = Math.hypot(m.x - this.x, m.z - this.z)
      if (dd < d) { d = dd; mejor = m }
    }
    return mejor
  }
  buscarMaquina(tipo, { conEspacio = false } = {}) {
    requiereNivel(2, 'buscarMaquina (sensor)')
    let mejor = null, d = Infinity
    for (const m of Object.values(maquinas)) {
      if (m.tipo !== tipo || m.estado === 'construyendo') continue
      if (conEspacio && this.carga && m.espacio(this.carga) <= 0) continue
      const dd = Math.hypot(m.x - this.x, m.z - this.z)
      if (dd < d) { d = dd; mejor = m }
    }
    return mejor
  }
  toString() { return `robots[${this.id}]` }
}

class MaquinaAPI {
  constructor(id) { this.id = id }
  get #d() { return estado.maquinas?.[this.id] }
  get existe() { return !!this.#d }
  get tipo() { return this.#d?.tipo }
  get estado() { return this.#d?.estado }
  get x() { return this.#d?.x }
  get z() { return this.#d?.z }
  get entrada() { return { ...(this.#d?.entrada ?? {}) } }
  get salida() { return { ...(this.#d?.salida ?? {}) } }
  // Unidades de `material` que caben ahora en la entrada (0 si no lo usa).
  espacio(material) {
    const d = this.#d
    if (!d || !(d.acepta ?? []).includes(material)) return 0
    return Math.max(0, d.cap_entrada - (d.entrada?.[material] ?? 0))
  }
  toString() { return this.id }
}

const robots = new Proxy({}, { get: (_, k) => (typeof k === 'string' && /^\d+$/.test(k) ? new RobotAPI(Number(k)) : undefined) })
const maquinas = new Proxy({}, {
  get: (_, k) => (typeof k === 'string' && estado.maquinas?.[k] ? new MaquinaAPI(k) : undefined),
  ownKeys: () => Object.keys(estado.maquinas ?? {}),
  getOwnPropertyDescriptor: (_, k) => (estado.maquinas?.[k] ? { enumerable: true, configurable: true, value: new MaquinaAPI(k) } : undefined),
})

const db = {
  query(sql, params = []) {
    const q = ++qid
    return new Promise((resolver, rechazar) => {
      consultas.set(q, { resolver, rechazar })
      enviar({ op: 'sql', qid: q, sql: String(sql), params })
    })
  },
}

function log(...xs) {
  enviar({ op: 'log', robot: ID, texto: xs.map(texto).join(' '), linea: lineaActual() })
}

const contexto = vm.createContext({
  robots, yo: new RobotAPI(ID), maquinas, db, log,
  reloj: { get hora() { return estado.hora }, get dia() { return estado.dia }, get t() { return estado.t } },
  get menas() { return (estado.menas ?? []).map(m => ({ ...m })) },
  console: { log },
  Math, JSON, Date, Number, String, Array, Object, Boolean, Error, Map, Set, Promise,
})

// Las líneas del programa empiezan en la 1 (el envoltorio va en la misma línea 1).
const fuente = `(async () => { ${codigo}\n})()`
let programa
try {
  programa = new vm.Script(fuente, { filename: ARCHIVO })
} catch (e) {
  enviar({ op: 'error', robot: ID, mensaje: `${e.name}: ${e.message}`, linea: lineaActual(e) })
  enviar({ op: 'fin', robot: ID })
  process.exit(0)
}

try {
  // El timeout cubre la parte síncrona hasta el primer await.
  await programa.runInContext(contexto, { timeout: 2000 })
  enviar({ op: 'log', robot: ID, texto: '(el programa terminó)', linea: 0 })
} catch (e) {
  enviar({ op: 'error', robot: ID, mensaje: `${e.name ?? 'Error'}: ${e.message}`, linea: lineaActual(e) })
}
enviar({ op: 'fin', robot: ID })
process.exit(0)

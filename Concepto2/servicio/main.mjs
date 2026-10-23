// Servicio auxiliar de Codemageddon (escritorio).
//
//  · PostgreSQL de verdad: PGlite (Postgres compilado a WASM), sin instalar nada en el sistema.
//    También se expone por el protocolo de Postgres en 127.0.0.1:<pg> para psql, DBeaver, etc.
//  · Runtime JavaScript de los programas de los robots: un worker_thread por robot, con una API
//    asíncrona limitada a órdenes del juego (runtime_robot.mjs).
//
// Godot lanza este proceso y habla con él por TCP local con mensajes JSON, uno por línea.
// En la exportación web el plan es el mismo protocolo con PGlite y un Web Worker en el navegador.
//
// Uso: node main.mjs [--puerto 0] [--pg 5433] [--log ruta.log]
// Escribe en stdout una sola línea: «PUERTO <n>». El resto va al archivo de log.

import net from 'node:net'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { Worker } from 'node:worker_threads'
import { PGlite } from '@electric-sql/pglite'
import { PGLiteSocketServer } from '@electric-sql/pglite-socket'

const DIR = path.dirname(fileURLToPath(import.meta.url))
const args = Object.fromEntries(process.argv.slice(2).reduce((acc, v, i, a) => (v.startsWith('--') ? acc.concat([[v.slice(2), a[i + 1]]]) : acc), []))
const PUERTO = Number(args.puerto ?? 0)
const PUERTO_PG = Number(args.pg ?? 5433)
const LOG = args.log ?? null

function log(...xs) {
  const linea = `[${new Date().toISOString()}] ${xs.map(x => (typeof x === 'string' ? x : JSON.stringify(x))).join(' ')}\n`
  if (LOG) fs.appendFileSync(LOG, linea)
}

// JSON sin BigInt (Postgres devuelve int8 como BigInt en algunos casos).
const json = v => JSON.stringify(v, (_, x) => (typeof x === 'bigint' ? Number(x) : x))

// ---------------------------------------------------------------- base de datos

const db = await PGlite.create()
const version = (await db.query('SELECT version() AS v')).rows[0].v
log('PGlite listo:', version)
let servidorPg = null
try {
  servidorPg = new PGLiteSocketServer({ db, port: PUERTO_PG, host: '127.0.0.1' })
  await servidorPg.start()
  log('Protocolo Postgres en 127.0.0.1:' + PUERTO_PG)
} catch (e) {
  servidorPg = null
  log('Sin servidor de protocolo Postgres:', e.message)
}

// Todas las operaciones de base de datos van en una cola: el orden de los eventos se conserva.
let cola = Promise.resolve()
const enCola = fn => (cola = cola.then(fn).catch(e => log('error en cola', e.message)))

const IDENT = /^[a-z_][a-z0-9_]*$/

async function insertar(tabla, filas) {
  if (!filas.length || !IDENT.test(tabla)) return
  const cols = Object.keys(filas[0]).filter(c => IDENT.test(c))
  // Lotes de 200 filas por sentencia (límite de parámetros de Postgres: 65535).
  for (let i = 0; i < filas.length; i += 200) {
    const lote = filas.slice(i, i + 200)
    const params = []
    const valores = lote.map(f => '(' + cols.map(c => { params.push(f[c] ?? null); return '$' + params.length }).join(', ') + ')')
    await db.query(`INSERT INTO ${tabla} (${cols.join(', ')}) VALUES ${valores.join(', ')}`, params)
  }
}

// Consulta del jugador: varias sentencias permitidas, se devuelve la última con resultado.
async function consultar(sql) {
  const t0 = performance.now()
  try {
    const res = await db.exec(sql)
    const ultima = res.length ? res[res.length - 1] : { fields: [], rows: [], affectedRows: 0 }
    const columnas = ultima.fields.map(f => f.name)
    return {
      ok: true, columnas, filas: ultima.rows.map(r => columnas.map(c => r[c])),
      afectadas: ultima.affectedRows ?? 0, ms: performance.now() - t0, error: '',
    }
  } catch (e) {
    return { ok: false, columnas: [], filas: [], afectadas: 0, ms: performance.now() - t0, error: e.message }
  }
}

// ---------------------------------------------------------------- programas de los robots

const workers = new Map()       // robot -> { worker, latido, nivel }
let estado = {}                  // última foto del mundo enviada por Godot

function enviar(msg) {
  if (cliente && !cliente.destroyed) cliente.write(json(msg) + '\n')
}

// Cada ejecución lleva un número: los mensajes tardíos de un programa ya detenido se ignoran.
function detener(robot, motivo) {
  const w = workers.get(robot)
  if (!w) return
  workers.delete(robot)
  w.worker.terminate()
  if (motivo) enviar({ op: 'error', robot, ejecucion: w.ejecucion, mensaje: motivo, linea: 0 })
  enviar({ op: 'fin', robot, ejecucion: w.ejecucion })
}

function ejecutar(robot, nivel, codigo, ejecucion) {
  detener(robot)
  const worker = new Worker(path.join(DIR, 'runtime_robot.mjs'), {
    workerData: { robot, nivel, codigo, estado },
    resourceLimits: { maxOldGenerationSizeMb: 64 },
  })
  const w = { worker, latido: Date.now(), nivel, ejecucion }
  workers.set(robot, w)
  worker.on('message', async m => {
    // Un worker terminado puede tener mensajes en tránsito después de un reset.
    if (workers.get(robot) !== w) return
    w.latido = Date.now()
    m.ejecucion = ejecucion
    switch (m.op) {
      case 'latido':
        break
      case 'sql':
        enCola(async () => {
          // También se cancela SQL que esperaba turno cuando se detuvo el programa.
          if (workers.get(robot) !== w) return
          try {
            const r = m.params?.length ? await db.query(m.sql, m.params) : (await db.exec(m.sql)).at(-1) ?? { rows: [] }
            worker.postMessage(JSON.parse(json({ op: 'sql_res', qid: m.qid, filas: r.rows })))
          } catch (e) {
            worker.postMessage({ op: 'sql_res', qid: m.qid, error: e.message })
          }
        })
        break
      case 'fin':
        if (workers.get(robot) === w) workers.delete(robot)
        enviar({ op: 'fin', robot, ejecucion })
        break
      default:
        enviar(m)   // accion, log, error, linea
    }
  })
  worker.on('error', e => {
    if (workers.get(robot) !== w) return
    enviar({ op: 'error', robot, ejecucion, mensaje: e.message, linea: 0 })
    if (workers.get(robot) === w) workers.delete(robot)
    enviar({ op: 'fin', robot, ejecucion })
  })
}

// Vigilante: un bucle sin `await` bloquea el worker y deja de latir.
setInterval(() => {
  const ahora = Date.now()
  for (const [robot, w] of workers) {
    if (ahora - w.latido > 3000) {
      log('robot bloqueado', robot)
      detener(robot, 'El programa estuvo 3 s sin ceder el control y se detuvo. ¿Falta un await (o un esperar) dentro de un bucle?')
    }
  }
}, 500)

// ---------------------------------------------------------------- conexión con Godot

let cliente = null

async function atender(m) {
  switch (m.op) {
    case 'iniciar':
      await enCola(async () => {
        try {
          await db.exec(m.esquema)
          enviar({ op: 'listo', motor: version.split(',')[0], pg: servidorPg ? PUERTO_PG : 0 })
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
    case 'salir':
      process.exit(0)
  }
}

const servidor = net.createServer(socket => {
  if (cliente) { socket.destroy(); return }
  cliente = socket
  socket.setNoDelay(true)
  log('Godot conectado')
  let buffer = ''
  socket.on('data', d => {
    buffer += d.toString('utf8')
    let i
    while ((i = buffer.indexOf('\n')) >= 0) {
      const linea = buffer.slice(0, i)
      buffer = buffer.slice(i + 1)
      if (!linea.trim()) continue
      try { atender(JSON.parse(linea)) } catch (e) { log('mensaje inválido', e.message) }
    }
  })
  // Si el juego se cierra (o se cuelga), el servicio también termina.
  socket.on('close', () => { log('Godot desconectado'); process.exit(0) })
  socket.on('error', () => {})
})

servidor.listen(PUERTO, '127.0.0.1', () => {
  process.stdout.write(`PUERTO ${servidor.address().port}\n`)
  log('Escuchando en', servidor.address().port)
})

// Si nadie se conecta en 20 s, no queda un proceso huérfano.
setTimeout(() => { if (!cliente) process.exit(1) }, 20000)

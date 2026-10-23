// Ajustes exclusivos de la demo: argumentos del laboratorio y versión comprobable por HTTP.
import fs from 'node:fs'
import path from 'node:path'
import crypto from 'node:crypto'

const [directorio, revision, habilitar] = process.argv.slice(2)
if (!directorio || !/^[0-9a-f]{40}$/.test(revision ?? '') || !['0', '1'].includes(habilitar)) {
  throw new Error('Uso: preparar_demo.mjs directorio revision_git devtools(0|1)')
}
const ruta = path.join(directorio, 'index.html')
let html = fs.readFileSync(ruta, 'utf8')
const linea = /const GODOT_CONFIG = (\{[^\n]+\});/
const coincidencia = html.match(linea)
if (!coincidencia) throw new Error('No se encontró GODOT_CONFIG; no se publica una exportación incompleta.')
const config = JSON.parse(coincidencia[1])
config.args = habilitar === '1' ? ['--', '--dev'] : []
html = html.replace(linea, `const GODOT_CONFIG = ${JSON.stringify(config)};`)
fs.writeFileSync(ruta, html)
const paquete = `${config.executable}.pck`
fs.writeFileSync(path.join(directorio, 'version.json'), JSON.stringify({
  revision, devtools: habilitar === '1', paquete,
  sha256: crypto.createHash('sha256').update(fs.readFileSync(path.join(directorio, paquete))).digest('hex'),
}, null, 2) + '\n')

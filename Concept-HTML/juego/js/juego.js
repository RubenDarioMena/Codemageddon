/* Codemageddon · juego (heredero del banco de mecánicas 03, «lanzamisiles»).
 * Simulación determinista, runtime del jugador en Web Workers, vista 3D/plano, inspector y editor.
 * Viene casi intacto de prototipos/mecanicas/03_lanzamisiles.html; lo nuevo de la interfaz es:
 * inspector en tres estados con signos vitales, pulsación larga en el campo y paleta de iconos.
 * El reparto de pantalla, el teclado del teléfono y los tooltips viven en layout.js. */
(() => {
  "use strict";

  // ---------- Constantes del mundo ----------
  const COLS = 32, ROWS = 18;      // casillas de 1 m
  const LINEA_BASE = 3;            // x de la línea roja: cruzarla es una brecha
  const DT = 0.05;                 // paso fijo de simulación (tiempo de juego)
  const VIGIA_MS = 2500;           // bucle sin await
  const MAX_ORDENES = 4000;        // mensajes seguidos sin esperar
  const T_LIMITE = 400;            // tiempo de juego máximo de un intento
  const CLAVE = "cmg-banco03";
  const TIPOS = {
    crawler: { nombre: "oruga", suelo: true, z: 0, vel: 0.8, hp: 2, frio: false, letra: "O" },
    drone: { nombre: "dron", suelo: false, z: 2.5, vel: 2.0, hp: 1, frio: false, letra: "D" },
    stealth: { nombre: "dron frío", suelo: false, z: 2.0, vel: 1.5, hp: 1, frio: true, letra: "F" },
  };
  const SENSOR = {
    visual: { nombre: "cámara", alcance: 14, niebla: 5.5 },
    thermal: { nombre: "térmico", alcance: 11, niebla: 7 },
  };
  const LAU = { cadencia: 1, cadenciaRafaga: 2.2, cargador: 8, suministro: 1, fallaBase: 0.02, fallaRafaga: 0.04, subida: 0.06, bajada: 0.1, bajadaParado: 0.2 };
  const MISIL = { vel: 14, radio: 1.3 };
  const REP = { vel: 4, tBase: 1.5, tPorFallo: 12 };  // reparar tarda más si el fallo llegó con failureRate alto
  const COSTE = { misil: 10, reparacion: 40 };
  const NIVELES = ["log", "info", "warn", "error"];

  // ---------- Retos ----------
  // Las coordenadas son casillas; las oleadas entran por el borde derecho y avanzan hacia la izquierda.
  const RETOS = [
    {
      titulo: "Primer blanco",
      objetivo: "Seis orugas avanzan hacia la base. Que ninguna cruce la línea roja.",
      leccion: "Bucle con espera. autoTarget mira solo en el instante en que lo llamas.",
      pista: "autoTarget mira una vez y regularShoot sigue disparando a ese mismo lugar. Mételos en while (true) { … await esperar(0.5); } para volver a apuntar.",
      lanzadores: [{ id: "LAU-01", x: 6, y: 9 }],
      oleadas: [{ tipo: "crawler", n: 6, t: 1, cada: 3.5, carriles: [9, 6, 12, 8, 11, 7] }],
      metas: { brechasMax: 0 },
      inicial: { "LAU-01": ['const pos = autoTarget("crawler", "visual");', "regularShoot(pos);"] },
    },
    {
      titulo: "Prioridades",
      objetivo: "Primero orugas lentas; luego drones rápidos que vuelan a 2,5 m. Defiende la base sin brechas.",
      leccion: "if / else o ?? para decidir a quién apuntar primero.",
      pista: "autoTarget devuelve null si no ve ese tipo. Pide primero «drone» y, si no hay, «crawler»: con if/else o con ??.",
      lanzadores: [{ id: "LAU-01", x: 6, y: 9 }],
      oleadas: [
        { tipo: "crawler", n: 7, t: 0, cada: 2.2, carriles: [8, 11, 6, 12, 9, 7, 10] },
        { tipo: "drone", n: 6, t: 10, cada: 1.4, carriles: [9, 7, 11, 5, 13, 9] },
      ],
      metas: { brechasMax: 0 },
      inicial: { "LAU-01": ["while (true) {", '  const pos = autoTarget("crawler", "visual");', "  regularShoot(pos);", "  await esperar(0.5);", "}"] },
    },
    {
      titulo: "Niebla",
      objetivo: "Con niebla la cámara ve 4,5 casillas y el térmico 7. Llegan orugas blindadas (3 impactos), drones y drones fríos, que el térmico no ve. VIB-01 escucha el suelo desde lejos.",
      leccion: "Elegir el sensor según el enemigo, y la red de sensores (VIB_01.detect).",
      pista: "Los drones fríos solo salen en la cámara. Las orugas blindadas necesitan 3 impactos: empieza antes con VIB_01.detect(\"crawler\"), que las oye lejos.",
      niebla: true,
      lanzadores: [{ id: "LAU-01", x: 6, y: 9 }],
      sensores: [{ id: "VIB-01", x: 17, y: 9, alcance: 8 }],
      oleadas: [
        { tipo: "crawler", n: 6, t: 0, cada: 1.6, carriles: [9, 7, 11, 8, 10, 9], hp: 3 },
        { tipo: "stealth", n: 2, t: 15, cada: 3, carriles: [9, 10] },
        { tipo: "drone", n: 3, t: 20, cada: 1.8, carriles: [6, 12, 9] },
      ],
      metas: { brechasMax: 0 },
      inicial: { "LAU-01": ["while (true) {", '  const pos = autoTarget("drone", "visual") ?? autoTarget("crawler", "visual");', "  regularShoot(pos);", "  await esperar(0.5);", "}"] },
    },
    {
      titulo: "Enjambre",
      objetivo: "Dos enjambres de 18 drones casi pegados; deja pasar como mucho 1. A 1 disparo por segundo no alcanza. La ráfaga dispara 2,2 por segundo, pero cada segundo en ráfaga sube failureRate, y cuanto más alto esté al fallar, más tarda REP-01 en reparar el atasco.",
      leccion: "Leer una propiedad de la máquina (failureRate) para cambiar de modo.",
      pista: "El programa de partida espera a 0,35 para parar: es tarde. Prueba ráfaga mientras failureRate esté bajo, y regularShoot o stopFire hasta que se enfríe. Mira el globo de console.warn y el tiempo de cada reparación.",
      lanzadores: [{ id: "LAU-01", x: 6, y: 9 }],
      reparadores: 1, cargador: 10, suministro: 2,
      oleadas: [
        { tipo: "crawler", n: 2, t: 0, cada: 6, carriles: [8, 10] },
        { tipo: "drone", n: 18, t: 6, cada: 0.5, carriles: [7, 9, 11, 8, 10, 12, 6, 9, 11], vel: 2.4 },
        { tipo: "drone", n: 18, t: 30, cada: 0.5, carriles: [10, 8, 12, 6, 9, 11, 7, 9, 8], vel: 2.4 },
      ],
      metas: { brechasMax: 1 },
      inicial: { "LAU-01": [
        "while (true) {",
        '  const pos = autoTarget("drone", "visual") ?? autoTarget("crawler", "visual");',
        "  if (failureRate >= 0.25) {",
        "    console.warn(failureRate);",
        "  }",
        "  if (failureRate >= 0.35) {",
        "    stopFire();",
        "  } else {",
        "    burstFire(pos);",
        "  }",
        "  await esperar(0.4);",
        "}",
      ] },
    },
    {
      titulo: "Dos lanzadores",
      objetivo: "Dos enjambres a la vez, uno por el norte y otro por el sur; deja pasar como mucho 1. LAU-01 y LAU-02 tienen cada uno su programa y comparten un solo robot reparador. Si uno se atasca, el otro puede leerlo (LAU_01.jammed) y cubrirlo.",
      leccion: "Un programa por máquina; leer el estado de otra máquina.",
      pista: "Las órdenes solo valen para la máquina dueña del programa, pero puedes leer las demás: LAU_02.jammed, LAU_02.failureRate. «Copiar a los demás lanzadores» ahorra escribir dos veces.",
      lanzadores: [{ id: "LAU-01", x: 6, y: 5 }, { id: "LAU-02", x: 6, y: 13 }],
      sensores: [{ id: "VIB-01", x: 17, y: 9, alcance: 8 }],
      reparadores: 1, cargador: 12, suministro: 1.5,
      oleadas: [
        { tipo: "crawler", n: 4, t: 0, cada: 2.5, carriles: [3, 15, 5, 13], hp: 3 },
        { tipo: "drone", n: 12, t: 10, cada: 0.4, carriles: [2, 4, 3, 5], vel: 2.4 },
        { tipo: "drone", n: 12, t: 10.2, cada: 0.4, carriles: [15, 13, 16, 14], vel: 2.4 },
        { tipo: "stealth", n: 3, t: 24, cada: 1.5, carriles: [8, 10, 9] },
      ],
      metas: { brechasMax: 1 },
      inicial: {
        "LAU-01": ["while (true) {", '  const pos = autoTarget("drone", "visual") ?? autoTarget("crawler", "visual");', "  regularShoot(pos);", "  await esperar(0.5);", "}"],
        "LAU-02": ["while (true) {", '  const pos = autoTarget("drone", "visual") ?? autoTarget("crawler", "visual");', "  regularShoot(pos);", "  await esperar(0.5);", "}"],
      },
    },
  ];
  const PROPIO_BASE = {
    titulo: "Tu escenario",
    objetivo: "Escribe aquí tu enunciado: qué tiene que lograr el programa.",
    leccion: "Escenario propio · se edita en la pestaña Escenario.",
    pista: "Cambia oleadas, sensores y metas en la pestaña Escenario.",
    lanzadores: [{ id: "LAU-01", x: 6, y: 9 }],
    sensores: [{ id: "VIB-01", x: 17, y: 9, alcance: 8 }],
    reparadores: 1, cargador: 8, suministro: 1, niebla: false,
    oleadas: [
      { tipo: "crawler", n: 3, t: 0, cada: 4, carriles: [8, 10, 9] },
      { tipo: "drone", n: 6, t: 8, cada: 0.8, carriles: [7, 9, 11, 8, 10, 9] },
    ],
    metas: { brechasMax: 0 },
    inicial: {},
  };
  const POS_LANZADORES = { 1: [{ id: "LAU-01", x: 6, y: 9 }], 2: [{ id: "LAU-01", x: 6, y: 5 }, { id: "LAU-02", x: 6, y: 13 }] };

  function normalizar(d) {
    const num = (v, def, min, max) => { const n = Number(v); return Number.isFinite(n) ? Math.min(max, Math.max(min, n)) : def; };
    const metas = { ...(d.metas || {}) };
    for (const k of ["brechasMax", "atascosMax", "derribosMin", "tiempoMax"]) metas[k] = metas[k] == null || metas[k] === "" ? null : num(metas[k], null, 0, 999);
    if (metas.brechasMax == null) metas.brechasMax = 0;
    return {
      titulo: String(d.titulo || "Tu escenario").slice(0, 60), objetivo: String(d.objetivo || ""), leccion: String(d.leccion || ""), pista: String(d.pista || ""),
      lanzadores: (d.lanzadores && d.lanzadores.length ? d.lanzadores : POS_LANZADORES[1]).slice(0, 2).map(l => ({ id: l.id, x: num(l.x, 6, 1, COLS - 2), y: num(l.y, 9, 0, ROWS - 1) })),
      sensores: (d.sensores || []).slice(0, 2).map(s => ({ id: s.id, x: num(s.x, 17, 4, COLS - 2), y: num(s.y, 9, 0, ROWS - 1), alcance: num(s.alcance, 8, 2, 16) })),
      reparadores: Math.round(num(d.reparadores, 1, 0, 3)),
      cargador: Math.round(num(d.cargador, LAU.cargador, 1, 40)),
      suministro: num(d.suministro, LAU.suministro, 0, 5),
      niebla: !!d.niebla,
      oleadas: (d.oleadas || []).filter(o => TIPOS[o.tipo]).slice(0, 12).map(o => ({
        tipo: o.tipo, n: Math.round(num(o.n, 1, 0, 40)), t: num(o.t, 0, 0, 300), cada: num(o.cada, 1, 0.1, 60),
        carriles: (Array.isArray(o.carriles) ? o.carriles : [9]).map(c => Math.round(num(c, 9, 0, ROWS - 1))),
        ...(o.hp ? { hp: Math.round(num(o.hp, 1, 1, 9)) } : {}), ...(o.vel ? { vel: num(o.vel, 1, 0.2, 5) } : {}),
      })),
      metas,
      inicial: d.inicial || {},
    };
  }

  // ---------- Almacenamiento local (comodidad del jugador) ----------
  const guardado = {
    leer(k, def) { try { const v = localStorage.getItem(`${CLAVE}:${k}`); return v == null ? def : JSON.parse(v); } catch { return def; } },
    escribir(k, v) { try { localStorage.setItem(`${CLAVE}:${k}`, JSON.stringify(v)); } catch { /* sin almacenamiento */ } },
  };

  // ---------- Runtime del jugador (un Web Worker por lanzador) ----------
  // Las lecturas (autoTarget, propiedades, VIB_01.detect) salen de una instantánea del mundo que llega
  // cada vez que el programa despierta; las órdenes se mandan sin esperar respuesta. El tiempo de juego
  // solo avanza mientras todos los programas están en `await esperar(...)`.
  const WORKER_SRC = `
const AF = Object.getPrototypeOf(async function () {}).constructor;
let SNAP = null, PROPIA = null, NOMBRES = [], TIPOS = [], SENSORES = [], CONF = {}, OFF = null, seq = 0, espera = null;
const PROPS_LAU = ["failureRate", "missiles", "mode", "jammed", "fireRate", "sensors", "target"];
const nombreVar = (id) => id.replace(/-/g, "_");
function lineaDe(e) {
  const s = String((e && e.stack) || "");
  const m = s.match(/<anonymous>:(\\d+):\\d+/) || s.match(/> Function:(\\d+):\\d+/) || s.match(/(?:eval code|anonymous)[^\\n]*?:(\\d+):\\d+/);
  return m ? +m[1] : null;
}
const redondo = (x) => typeof x === "number" ? Math.round(x * 1000) / 1000 : x;
function fmt(v) {
  if (typeof v === "string") return v;
  if (typeof v === "number") return String(redondo(v));
  if (v === undefined) return "undefined";
  try { return JSON.stringify(v, (k, x) => redondo(x)); } catch (_) { return String(v); }
}
const q = (v) => typeof v === "string" ? JSON.stringify(v) : fmt(v);
const copia = (v) => v && typeof v === "object" ? JSON.parse(JSON.stringify(v)) : v;
function fallo(linea, msg) { const e = new Error(msg); e.__linea = linea; return e; }
const lista = (a) => a.map(x => '"' + x + '"').join(", ");
function apuntarAPI(linea, id, tipo, sensor) {
  if (!TIPOS.includes(tipo)) throw fallo(linea, "autoTarget necesita el tipo de enemigo como primer argumento: " + lista(TIPOS) + ". Recibió " + q(tipo) + ".");
  if (sensor === "vibration" || sensor === "vibracion") {
    const vib = NOMBRES.find(n => n.startsWith("VIB"));
    throw fallo(linea, "El sensor de vibración no va montado en el lanzador: es de la red de sensores. " + (vib ? "Usa " + nombreVar(vib) + '.detect("crawler").' : "En este mapa no hay ninguno."));
  }
  if (!SENSORES.includes(sensor)) throw fallo(linea, "autoTarget necesita el sensor como segundo argumento: " + lista(SENSORES) + ". Recibió " + q(sensor) + ".");
  const v = SNAP.auto[id][sensor][tipo];
  postMessage({ type: "lee", linea, maquina: id, que: (id === PROPIA ? "" : nombreVar(id) + ".") + "autoTarget(" + q(tipo) + ", " + q(sensor) + ")", valor: v, fn: "autoTarget" });
  return copia(v);
}
function detectarAPI(linea, id, tipo) {
  if (tipo !== undefined && !TIPOS.includes(tipo)) throw fallo(linea, nombreVar(id) + ".detect acepta un tipo de enemigo (" + lista(TIPOS) + ") o nada. Recibió " + q(tipo) + ".");
  const v = SNAP.vib[id][tipo || "*"];
  postMessage({ type: "lee", linea, maquina: id, que: nombreVar(id) + ".detect(" + (tipo === undefined ? "" : q(tipo)) + ")", valor: v, fn: "detect" });
  return copia(v);
}
function lugarDe(linea, fn, lugar) {
  if (lugar == null) return null;
  if (typeof lugar !== "object" || !Number.isFinite(+lugar.x) || !Number.isFinite(+lugar.y))
    throw fallo(linea, fn + " necesita un lugar con x e y, como el que devuelve autoTarget(). Recibió " + q(lugar) + ".");
  return { x: +lugar.x, y: +lugar.y, z: Number.isFinite(+lugar.z) ? +lugar.z : 0, id: typeof lugar.id === "string" ? lugar.id : null };
}
function orden(linea, id, verbo, args) {
  if (id !== PROPIA) throw fallo(linea, "Las órdenes de " + id + " van en su propio programa. Desde aquí puedes leer " + nombreVar(id) + ".failureRate, " + nombreVar(id) + ".jammed…");
  const d = SNAP.maq[id];
  let res = "ok", lugar = null;
  if (verbo === "stopFire") { d.mode = "idle"; d.target = null; d.fireRate = 0; }
  else {
    lugar = lugarDe(linea, verbo, args[0]);
    if (!lugar) { d.mode = "idle"; d.target = null; d.fireRate = 0; res = "sin_objetivo"; }
    else {
      const modo = verbo === "burstFire" ? "burst" : "regular";
      if (modo === "burst" && d.mode !== "burst") d.failureRate = Math.max(d.failureRate, CONF.fallaRafaga);
      d.mode = modo; d.target = lugar; d.fireRate = modo === "burst" ? CONF.cadenciaRafaga : CONF.cadencia;
      res = d.jammed ? "atascado" : d.missiles < 1 ? "sin_misiles" : "ok";
    }
  }
  postMessage({ type: "cmd", linea, verbo, lugar, res });
  return res;
}
function esperarAPI(linea, s) {
  if (typeof s !== "number" || !(s >= 0.05) || s > 30) throw fallo(linea, "esperar necesita segundos entre 0.05 y 30, por ejemplo await esperar(0.5). Recibió " + q(s) + ".");
  if (espera) throw fallo(linea, "Falta await en la línea " + espera.linea + ": el programa seguía esperando cuando llegó otra espera en la línea " + linea + ".");
  const id = ++seq;
  postMessage({ type: "espera", id, linea, s });
  return new Promise((resolve) => { espera = { id, resolve, linea }; });
}
function consola(linea, nivel, a) { postMessage({ type: "consola", linea, nivel, texto: a.map(fmt).join(" ") }); }
function maquina(id, linea) {
  const o = {};
  if (id.startsWith("LAU")) {
    o.autoTarget = (t, s) => apuntarAPI(linea, id, t, s);
    o.regularShoot = (...a) => orden(linea, id, "regularShoot", a);
    o.burstFire = (...a) => orden(linea, id, "burstFire", a);
    o.stopFire = (...a) => orden(linea, id, "stopFire", a);
    for (const p of PROPS_LAU) Object.defineProperty(o, p, { enumerable: true, get: () => copia(SNAP.maq[id][p]) });
  } else if (id.startsWith("VIB")) {
    o.detect = (t) => detectarAPI(linea, id, t);
    Object.defineProperty(o, "count", { enumerable: true, get: () => SNAP.maq[id].count });
  }
  Object.defineProperty(o, "id", { enumerable: true, value: id });
  return new Proxy(o, { get(t, p) {
    if (typeof p === "symbol" || p in t || p === "then" || p === "toJSON") return t[p];
    throw fallo(linea, nombreVar(id) + "." + String(p) + " no existe. " + nombreVar(id) + " tiene: " + Object.keys(t).join(", ") + ".");
  } });
}
function __L(linea) {
  const o = {
    autoTarget: (t, s) => apuntarAPI(linea, PROPIA, t, s),
    regularShoot: (...a) => orden(linea, PROPIA, "regularShoot", a),
    burstFire: (...a) => orden(linea, PROPIA, "burstFire", a),
    stopFire: (...a) => orden(linea, PROPIA, "stopFire", a),
    esperar: (s) => esperarAPI(linea, s),
    log: (...a) => consola(linea, "log", a),
    console: { log: (...a) => consola(linea, "log", a), info: (...a) => consola(linea, "info", a), warn: (...a) => consola(linea, "warn", a), error: (...a) => consola(linea, "error", a) },
  };
  Object.defineProperty(o, "yo", { get: () => maquina(PROPIA, linea) });
  for (const id of NOMBRES) Object.defineProperty(o, nombreVar(id), { get: () => maquina(id, linea) });
  return o;
}
// Sin instrumentar (dentro de plantillas de texto, por ejemplo) también funcionan, solo que sin línea.
function instalarGlobales() {
  const base = __L(null);
  for (const k of ["autoTarget", "regularShoot", "burstFire", "stopFire", "esperar", "log", "console"]) self[k] = base[k];
  Object.defineProperty(self, "yo", { configurable: true, get: () => maquina(PROPIA, null) });
  for (const id of NOMBRES) Object.defineProperty(self, nombreVar(id), { configurable: true, get: () => maquina(id, null) });
  for (const p of PROPS_LAU) Object.defineProperty(self, p, { configurable: true, get: () => copia(SNAP.maq[PROPIA][p]) });
}
onmessage = async (ev) => {
  const m = ev.data;
  if (m.type === "despierta") {
    SNAP = m.snap;
    const e = espera;
    if (e && e.id === m.id) { espera = null; e.resolve("ok"); }
    return;
  }
  if (m.type !== "run") return;
  SNAP = m.snap; PROPIA = m.propia; NOMBRES = m.nombres; TIPOS = m.tipos; SENSORES = m.sensores; CONF = m.conf;
  if (OFF === null) {
    try { await new AF("\\nthrow new Error('x')")(); } catch (e) { const n = lineaDe(e); OFF = n == null ? NaN : n - 2; }
  }
  instalarGlobales();
  let fn;
  try { fn = new AF("__L", m.codigo); }
  catch (e) { postMessage({ type: "error", mensaje: "Error de sintaxis: " + e.message, linea: null }); return; }
  try { await fn(__L); postMessage({ type: "done" }); }
  catch (e) {
    let linea = e && e.__linea;
    if (linea == null) { const n = lineaDe(e); if (n != null && !isNaN(OFF)) linea = n - OFF; }
    const msg = String((e && e.message) || e).replace(/__L\\((?:\\d+|null)\\)\\./g, "");
    postMessage({ type: "error", mensaje: msg, linea: linea == null ? null : linea });
  }
};
`;
  const WORKER_URL = URL.createObjectURL(new Blob([WORKER_SRC], { type: "text/javascript" }));

  // ---------- Léxico (resaltado e instrumentación comparten el mismo) ----------
  const KW = new Set("await async break case catch class const continue default delete do else false finally for function if in instanceof let new null of return switch this throw true try typeof undefined var void while".split(" "));
  const FN_PROPIAS = new Set(["autoTarget", "regularShoot", "burstFire", "stopFire", "esperar", "log"]);
  const FN_MIEMBRO = new Set(["autoTarget", "regularShoot", "burstFire", "stopFire", "detect", "log", "info", "warn", "error"]);
  const PROPS = new Set(["failureRate", "missiles", "mode", "jammed", "fireRate", "sensors", "target", "count"]);
  const HUECO = /^\/\*\s*(tipo|sensor|lugar)\s*\*\/$/;
  const RE_ID = /[A-Za-z_$][\w$]*/y, RE_NUM = /0x[0-9a-f]+|\d*\.?\d+(?:e[+-]?\d+)?/iy;
  function lexico(src) {
    const out = []; const n = src.length; let i = 0;
    while (i < n) {
      const c = src[i], d = src[i + 1];
      if (c === "/" && d === "/") { let j = src.indexOf("\n", i); if (j < 0) j = n; out.push(["com", src.slice(i, j)]); i = j; continue; }
      if (c === "/" && d === "*") { let j = src.indexOf("*/", i + 2); j = j < 0 ? n : j + 2; out.push(["com", src.slice(i, j)]); i = j; continue; }
      if (c === '"' || c === "'" || c === "`") {
        let j = i + 1;
        while (j < n) { const e = src[j]; if (e === "\\") { j += 2; continue; } if (e === c) { j++; break; } if (e === "\n" && c !== "`") break; j++; }
        j = Math.min(n, j); out.push(["str", src.slice(i, j)]); i = j; continue;
      }
      if (/[0-9]/.test(c) || (c === "." && /[0-9]/.test(d || ""))) { RE_NUM.lastIndex = i; const m = RE_NUM.exec(src); out.push(["num", m[0]]); i += m[0].length; continue; }
      if (/[A-Za-z_$]/.test(c)) { RE_ID.lastIndex = i; const m = RE_ID.exec(src); out.push(["id", m[0]]); i += m[0].length; continue; }
      if (c === "\n") { out.push(["nl", c]); i++; continue; }
      if (c === " " || c === "\t" || c === "\r") { let j = i; while (j < n && (src[j] === " " || src[j] === "\t" || src[j] === "\r")) j++; out.push(["esp", src.slice(i, j)]); i = j; continue; }
      out.push(["p", c]); i++;
    }
    return out;
  }
  // Vecino significativo (salta espacios y comentarios en la misma línea).
  function vecino(toks, i, dir) {
    for (let j = i + dir; j >= 0 && j < toks.length; j += dir) { const k = toks[j][0]; if (k !== "esp" && k !== "com") return toks[j]; }
    return null;
  }
  const esObjeto = (nombre) => nombre === "console" || nombre === "yo" || nombresVar().includes(nombre);

  // Cada llamada de la API lleva su número de línea, para iluminarla y para los mensajes de error.
  function instrumentar(src) {
    const toks = lexico(src); let linea = 1, out = "";
    toks.forEach(([k, t], i) => {
      if (k === "id") {
        const prev = vecino(toks, i, -1), sig = vecino(toks, i, 1);
        const miembro = prev && prev[1] === ".";
        if (!miembro && ((FN_PROPIAS.has(t) && sig && sig[1] === "(") || (esObjeto(t) && sig && sig[1] === "."))) { out += `__L(${linea}).${t}`; return; }
      }
      out += t;
      for (const ch of t) if (ch === "\n") linea++;
    });
    return out;
  }
  function clasificar(toks, i) {
    const [k, t] = toks[i];
    if (k === "com") return HUECO.test(t) ? "com hueco" : "com";
    if (k === "str") return "str";
    if (k === "num") return "num";
    if (k !== "id") return null;
    const prev = vecino(toks, i, -1);
    if (prev && prev[1] === ".") return FN_MIEMBRO.has(t) ? "fn" : PROPS.has(t) ? "prop" : null;
    if (KW.has(t)) return "kw";
    if (esObjeto(t)) return "maq";
    if (FN_PROPIAS.has(t)) return "fn";
    if (PROPS.has(t)) return "prop";
    return null;
  }

  // ---------- Simulación (determinista: paso fijo y una semilla para los fallos) ----------
  function mulberry32(a) {
    return function () { a |= 0; a = a + 0x6D2B79F5 | 0; let t = Math.imul(a ^ a >>> 15, 1 | a); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; };
  }
  const r2 = (v) => Math.round(v * 100) / 100, r3 = (v) => Math.round(v * 1000) / 1000;
  const coma = (v, d = 1) => v.toFixed(d).replace(".", ",");  // decimales en los textos para personas
  const cadencia = (modo) => modo === "burst" ? LAU.cadenciaRafaga : modo === "regular" ? LAU.cadencia : 0;
  const alcance = (sensor) => mundo.def.niebla ? SENSOR[sensor].niebla : SENSOR[sensor].alcance;

  function crearMundo(def, semilla) {
    const pendientes = []; let orden = 0;
    for (const o of def.oleadas) {
      const tp = TIPOS[o.tipo];
      const carriles = o.carriles.length ? o.carriles : [9];
      for (let i = 0; i < o.n; i++) pendientes.push({ tipo: o.tipo, nace: o.t + i * o.cada, y: carriles[i % carriles.length] + .5, hp: o.hp || tp.hp, vel: o.vel || tp.vel, orden: orden++ });
    }
    pendientes.sort((a, b) => a.nace - b.nace || a.orden - b.orden);
    const cuenta = {};
    for (const p of pendientes) { cuenta[p.tipo] = (cuenta[p.tipo] || 0) + 1; p.id = TIPOS[p.tipo].letra + cuenta[p.tipo]; }
    const lanzadores = def.lanzadores.map(l => ({
      id: l.id, clase: "lanzador", cx: l.x + .5, cy: l.y + .5, modo: "idle", lugar: null, cd: 0, misiles: def.cargador, carga: 0,
      falla: LAU.fallaBase, riesgo: 0, umbral: 1, tReparar: 0, atascado: false, yaw: Math.PI, sinMisiles: false,
      st: { consumidos: 0, lanzados: 0, impactos: 0, derribos: 0, atascos: 0, tRafaga: 0, fallaMax: LAU.fallaBase },
    }));
    const sensores = def.sensores.map(s => ({ id: s.id, clase: "vibracion", cx: s.x + .5, cy: s.y + .5, alcance: s.alcance, st: { lecturas: 0 } }));
    const deposito = { id: "DEP-01", clase: "deposito", cx: 1.5, cy: 9.5 };
    const reparadores = [];
    for (let i = 0; i < def.reparadores; i++) {
      const bx = 2.4, by = 7.4 + i * 1.1;
      reparadores.push({ id: `REP-0${i + 1}`, clase: "reparador", cx: bx, cy: by, bx, by, estado: "base", objetivo: null, t: 0, st: { reparaciones: 0 } });
    }
    const maquinas = [...lanzadores, ...sensores, deposito, ...reparadores];
    const rng = mulberry32((semilla * 2654435761) >>> 0);
    for (const l of lanzadores) l.umbral = .75 + rng() / 2;
    return {
      def, semilla, rng, t: 0, activo: false, fin: null,
      lanzadores, sensores, deposito, reparadores, maquinas, porId: Object.fromEntries(maquinas.map(e => [e.id, e])),
      colaReparar: [], pendientes, enemigos: [], misiles: [], explosiones: [], derribados: [], sigMisil: 1,
      brechas: 0, derribos: 0, consumidos: 0, impactos: 0, atascos: 0, reparaciones: 0, total: pendientes.length, detalleAtascos: [],
      eventos: [], uso: {}, consolas: { log: 0, info: 0, warn: 0, error: 0 },
    };
  }

  function visible(l, e, sensor) {
    if (sensor === "thermal" && TIPOS[e.tipo].frio) return false;
    return Math.hypot(e.x - l.cx, e.y - l.cy) <= alcance(sensor) + 1e-9;
  }
  // Dónde estará el enemigo cuando llegue el próximo misil de ese lanzador.
  function predecir(l, e) {
    const espera = Math.max(0, l.cd);
    let t = espera, px = e.x, py = e.y;
    for (let k = 0; k < 4; k++) { px = e.x + e.vx * t; py = e.y + e.vy * t; t = espera + Math.hypot(px - l.cx, py - l.cy) / MISIL.vel; }
    return { x: px, y: py };
  }
  // El más avanzado (el más cerca de la base) de ese tipo que vea ese sensor, salvo los que ya tienen
  // en el aire misiles suficientes para derribarlos.
  function apuntar(l, sensor, tipo, pend) {
    let mejor = null;
    for (const e of mundo.enemigos) {
      if (e.tipo !== tipo || !visible(l, e, sensor) || (pend[e.id] || 0) >= e.hp) continue;
      if (!mejor || e.x < mejor.x - 1e-9) mejor = e;
    }
    if (!mejor) return null;
    const p = predecir(l, mejor);
    return { x: r2(p.x), y: r2(p.y), z: mejor.z, id: mejor.id, tipo: mejor.tipo };
  }
  // La vibración da la posición actual (sin predicción) del enemigo de suelo más avanzado.
  function enRango(s) { return mundo.enemigos.filter(e => TIPOS[e.tipo].suelo && Math.hypot(e.x - s.cx, e.y - s.cy) <= s.alcance + 1e-9); }
  function detectar(s, tipo) {
    let mejor = null;
    for (const e of enRango(s)) if ((!tipo || e.tipo === tipo) && (!mejor || e.x < mejor.x - 1e-9)) mejor = e;
    return mejor ? { x: r2(mejor.x), y: r2(mejor.y), z: 0 } : null;
  }

  function instantanea() {
    const pend = {};
    for (const mi of mundo.misiles) if (mi.objetivo) pend[mi.objetivo] = (pend[mi.objetivo] || 0) + 1;
    const maq = {}, auto = {}, vib = {};
    for (const l of mundo.lanzadores) {
      maq[l.id] = { failureRate: r3(l.falla), missiles: l.misiles, mode: l.modo, jammed: l.atascado, fireRate: cadencia(l.modo), sensors: ["visual", "thermal"], target: l.lugar ? { ...l.lugar } : null };
      auto[l.id] = {};
      for (const s of Object.keys(SENSOR)) { auto[l.id][s] = {}; for (const tp of Object.keys(TIPOS)) auto[l.id][s][tp] = apuntar(l, s, tp, pend); }
    }
    for (const s of mundo.sensores) {
      vib[s.id] = { "*": detectar(s, null) };
      for (const tp of Object.keys(TIPOS)) vib[s.id][tp] = TIPOS[tp].suelo ? detectar(s, tp) : null;
      maq[s.id] = { count: enRango(s).length };
    }
    return { t: r2(mundo.t), maq, auto, vib };
  }

  function registrar(maquina, linea, que, resultado, clase) {
    mundo.eventos.push({ t: +mundo.t.toFixed(2), maquina, linea: linea ?? "", que, resultado, clase });
    eventosSucios = true;
  }

  function paso(dt) {
    const m = mundo;
    m.t += dt;
    while (m.pendientes.length && m.pendientes[0].nace <= m.t + 1e-9) {
      const p = m.pendientes.shift(), tp = TIPOS[p.tipo];
      m.enemigos.push({ id: p.id, tipo: p.tipo, x: COLS + .4, y: p.y, z: tp.z, vx: -p.vel, vy: 0, hp: p.hp, hpMax: p.hp, golpeT: -9 });
    }
    for (const e of m.enemigos) { e.x += e.vx * dt; e.y += e.vy * dt; }
    for (const e of m.enemigos) {
      if (e.x > LINEA_BASE) continue;
      e.fuera = true; m.brechas++;
      registrar("—", null, `${TIPOS[e.tipo].nombre} ${e.id}`, "brecha", "bad");
      avisoSistema(`Brecha: ${TIPOS[e.tipo].nombre} ${e.id} cruzó la línea de la base.`);
    }
    m.enemigos = m.enemigos.filter(e => !e.fuera);
    for (const l of m.lanzadores) pasoLanzador(l, dt);
    for (const mi of m.misiles) if (m.t >= mi.t0 + mi.dur - 1e-9) explotar(mi);
    m.misiles = m.misiles.filter(mi => !mi.hecho);
    for (const r of m.reparadores) pasoReparador(r, dt);
    m.explosiones = m.explosiones.filter(x => m.t - x.t0 < 0.8);
    m.derribados = m.derribados.filter(x => m.t - x.t0 < 1.2);
    evaluar();
  }

  function pasoLanzador(l, dt) {
    const m = mundo;
    if (l.modo === "burst" && !l.atascado) { l.falla = Math.min(0.95, l.falla + LAU.subida * dt); l.st.tRafaga += dt; }
    else l.falla = Math.max(LAU.fallaBase, l.falla - (l.modo === "idle" || l.atascado ? LAU.bajadaParado : LAU.bajada) * dt);
    l.st.fallaMax = Math.max(l.st.fallaMax, l.falla);
    if (l.misiles < m.def.cargador) { l.carga += m.def.suministro * dt; if (l.carga >= 1 - 1e-9) { l.misiles++; l.carga -= 1; } }
    else l.carga = 0;
    l.cd = Math.max(l.cd - dt, -dt);
    if (l.lugar) l.yaw = Math.atan2(l.lugar.y - l.cy, l.lugar.x - l.cx);
    if (l.modo === "idle" || !l.lugar || l.atascado || l.cd > 1e-9) return;
    if (l.misiles < 1) {
      if (!l.sinMisiles) { l.sinMisiles = true; registrar(l.id, null, "disparo", "sin_misiles", "warn"); globo(l.id, "sistema", "Sin misiles: espero al suministro"); }
      return;
    }
    l.sinMisiles = false;
    l.misiles--; l.st.consumidos++; m.consumidos++;
    l.cd += 1 / cadencia(l.modo);
    // failureRate es la probabilidad media de fallo por disparo. Se acumula como riesgo contra un umbral
    // aleatorio entre 0,75 y 1,25: en promedio falla 1 de cada 1/failureRate disparos, pero sin rachas extremas.
    l.riesgo += l.falla;
    if (l.riesgo >= l.umbral) {
      l.riesgo = 0; l.umbral = .75 + m.rng() / 2;
      l.atascado = true; l.st.atascos++; m.atascos++;
      l.tReparar = REP.tBase + REP.tPorFallo * l.falla;
      m.detalleAtascos.push({ t: r2(m.t), id: l.id, falla: r3(l.falla), tReparar: r2(l.tReparar) });
      m.colaReparar.push(l.id);
      m.explosiones.push({ x: l.cx, y: l.cy, z: 1, t0: m.t, atasco: true });
      registrar(l.id, null, `fallo con failureRate ${l.falla.toFixed(2)}`, "atasco", "bad");
      globo(l.id, "sistema", m.reparadores.length ? `¡Atasco con fallo al ${Math.round(l.falla * 100)} %! Reparar: ${coma(l.tReparar)} s` : `¡Atasco! No hay robot reparador.`);
      return;
    }
    const L = l.lugar, d = Math.hypot(L.x - l.cx, L.y - l.cy);
    m.misiles.push({ id: m.sigMisil++, de: l.id, x0: l.cx, y0: l.cy, z0: 1, x1: L.x, y1: L.y, z1: L.z || 0, t0: m.t, dur: Math.max(0.12, d / MISIL.vel), objetivo: L.id || null, arco: 0.6 + d * 0.16 });
    l.st.lanzados++;
  }

  function explotar(mi) {
    const m = mundo;
    mi.hecho = true;
    let golpe = false;
    for (const e of m.enemigos) {
      if (Math.hypot(e.x - mi.x1, e.y - mi.y1, e.z - mi.z1) > MISIL.radio) continue;
      e.hp--; e.golpeT = m.t; golpe = true;
      if (e.hp <= 0) {
        e.muerto = true; m.derribos++;
        const l = m.porId[mi.de]; if (l) l.st.derribos++;
        m.derribados.push({ x: e.x, y: e.y, z: e.z, t0: m.t, tipo: e.tipo });
        registrar(mi.de, null, `${TIPOS[e.tipo].nombre} ${e.id}`, "derribado", "ok");
      }
    }
    if (golpe) { m.impactos++; const l = m.porId[mi.de]; if (l) l.st.impactos++; }
    m.explosiones.push({ x: mi.x1, y: mi.y1, z: mi.z1, t0: m.t, golpe });
    m.enemigos = m.enemigos.filter(e => !e.muerto);
  }

  function moverHacia(e, x, y, d) {
    const dx = x - e.cx, dy = y - e.cy, dist = Math.hypot(dx, dy);
    if (dist <= d) { e.cx = x; e.cy = y; return true; }
    e.cx += dx / dist * d; e.cy += dy / dist * d; return false;
  }
  function pasoReparador(r, dt) {
    const m = mundo;
    if ((r.estado === "base" || r.estado === "volver") && m.colaReparar.length) { r.objetivo = m.colaReparar.shift(); r.estado = "ir"; }
    if (r.estado === "ir") {
      const l = m.porId[r.objetivo];
      if (moverHacia(r, l.cx - .9, l.cy + .7, REP.vel * dt)) { r.estado = "reparar"; r.t = l.tReparar; }
    } else if (r.estado === "volver") {
      if (moverHacia(r, r.bx, r.by, REP.vel * dt)) r.estado = "base";
    } else if (r.estado === "reparar") {
      r.t -= dt;
      if (r.t <= 1e-9) {
        const l = m.porId[r.objetivo];
        l.atascado = false; m.reparaciones++; r.st.reparaciones++;
        registrar(r.id, null, `reparar ${l.id}`, "reparado", "ok");
        globo(l.id, "sistema", "Reparado");
        r.objetivo = null;
        if (m.colaReparar.length) { r.objetivo = m.colaReparar.shift(); r.estado = "ir"; } else r.estado = "volver";
      }
    }
  }

  const coste = () => mundo.consumidos * COSTE.misil + mundo.reparaciones * COSTE.reparacion;
  function evaluar() {
    const m = mundo;
    if (!m.activo || m.fin) return;
    const me = m.def.metas;
    if (m.brechas > me.brechasMax) {
      const quietos = m.lanzadores.every(l => !l.st.consumidos);
      const peor = m.detalleAtascos.reduce((a, x) => !a || x.falla > a.falla ? x : a, null);
      const atascos = peor ? ` Hubo ${m.atascos} ${m.atascos === 1 ? "atasco" : "atascos"}; el peor, con failureRate ${peor.falla.toFixed(2)}, tardó ${coma(peor.tReparar)} s en repararse.` : "";
      return terminar("fallo", "brecha", `Hubo ${m.brechas} ${m.brechas === 1 ? "brecha" : "brechas"} (máximo ${me.brechasMax}).` + (quietos ? " Ningún lanzador llegó a disparar." : atascos));
    }
    if (me.atascosMax != null && m.atascos > me.atascosMax) return terminar("fallo", "atascos", `Hubo ${m.atascos} atascos (máximo ${me.atascosMax}).`);
    if (me.tiempoMax != null && m.t > me.tiempoMax + 1e-9) return terminar("fallo", "tiempo", `Se acabaron los ${me.tiempoMax} s y quedan enemigos.`);
    if (m.t > T_LIMITE) return terminar("fallo", "limite", `La defensa sigue después de ${T_LIMITE} s de juego.`);
    if (!m.pendientes.length && !m.enemigos.length && !m.misiles.length) {
      if (me.derribosMin != null && m.derribos < me.derribosMin) return terminar("fallo", "derribos", `Derribaste ${m.derribos}; la meta pedía ${me.derribosMin}.`);
      terminar("victoria", null, null);
    }
  }

  // ---------- Estado ----------
  const $ = (id) => document.getElementById(id);
  const esc = (s) => String(s).replace(/[&<>"]/g, ch => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[ch]));
  const varDe = (id) => id.replace(/-/g, "_");
  const nombresVar = () => mundo ? [...mundo.lanzadores, ...mundo.sensores].map(e => varDe(e.id)) : [];
  const RUTEO_DEF = { log: "globo", info: "globo", warn: "globo", error: "pantalla" };
  const IDX_PROPIO = RETOS.length;

  let retoIdx = Math.min(IDX_PROPIO, Math.max(0, guardado.leer("reto", 0) | 0));
  let propio = normalizar(guardado.leer("propio", PROPIO_BASE));
  let hechos = guardado.leer("hechos", []);
  let records = guardado.leer("records", {});
  let telemetria = guardado.leer("telemetria", []);
  let ruteo = { ...RUTEO_DEF, ...guardado.leer("ruteo", {}) };
  let vista = guardado.leer("vista", "3d");
  let colores = guardado.leer("colores", true);
  let tamLetra = guardado.leer("letra", 14);
  let semillaFija = !!guardado.leer("semillaFija", false);
  let def = null, programas = {}, progSel = "LAU-01";
  let mundo = null, ejec = null, pausa = false, velocidad = 1, turbo = 1, intento = 0, semilla = 1;
  let seleccion = null;
  let seleccionadas = new Set();
  let edicion = { ids: [], mixto: false };
  let lineaCorre = {}, lineaErr = null;
  let insercion = { dobleClic: 0, arrastre: 0, atajo: 0 };
  let eventosSucios = false, marcasSucias = false;
  const globos = new Map();   // id de máquina → { nivel, texto, hasta }

  const defActual = () => retoIdx === IDX_PROPIO ? propio : normalizar(RETOS[retoIdx]);
  const claveReto = () => retoIdx === IDX_PROPIO ? "propio" : String(retoIdx);

  // ---------- Ciclo de los programas (lockstep) ----------
  const algunoCorre = () => !!ejec && [...ejec.progs.values()].some(p => p.estado === "corre");
  function soloComentarios(src) { return lexico(src).every(([k]) => k === "com" || k === "esp" || k === "nl"); }

  // Antes de ejecutar: huecos /* … */ sin rellenar y errores de sintaxis, con su línea.
  function revisar(src) {
    const lineas = src.split("\n");
    for (let i = 0; i < lineas.length; i++) {
      const m = lineas[i].match(/\/\*\s*(tipo de enemigo|tipo|sensor|lugar)\s*\*\//);
      if (m && !/^\s*\/\//.test(lineas[i])) return { linea: i + 1, mensaje: `Rellena el hueco /* ${m[1]} */ antes de ejecutar. Doble clic en un valor del inspector lo pone en su lugar.` };
    }
    if (typeof acorn !== "undefined") {
      try { acorn.parse(src, { ecmaVersion: 2022, allowAwaitOutsideFunction: true, allowReturnOutsideFunction: true }); }
      catch (e) { return { linea: e.loc ? e.loc.line : null, mensaje: `Error de sintaxis: ${e.message.replace(/\s*\(\d+:\d+\)$/, "")}.` }; }
    }
    return null;
  }

  function ejecutar() {
    cerrarProgramas();
    for (const l of def.lanzadores) {
      const err = revisar(programas[l.id] || "");
      if (err) {
        abrirPrograma(l.id); lineaErr = { id: l.id, linea: err.linea }; marcasSucias = true;
        mostrarBanner("fallo", err.linea ? `Línea ${err.linea} de ${l.id}` : `Programa de ${l.id}`, esc(err.mensaje), null, [["Ir a la línea", "primario", () => { ocultarBanner(); irALinea(err.linea); }]]);
        return;
      }
    }
    intento++;
    if (!semillaFija) semilla = intento;
    nuevoMundo();
    mundo.activo = true;
    limpiarConsola(); ocultarBanner(); cerrarAvisos();
    lineaCorre = {}; lineaErr = null; marcasSucias = true;
    const snap = instantanea();
    const nombres = [...mundo.lanzadores, ...mundo.sensores].map(e => e.id);
    ejec = { progs: new Map(), inicio: new Date().toISOString(), codigos: {} };
    for (const l of mundo.lanzadores) {
      const codigo = programas[l.id] || "";
      const w = new Worker(WORKER_URL);
      const p = { id: l.id, worker: w, estado: "corre", desde: performance.now(), mensajes: 0, espera: null, despertar: 0 };
      w.onmessage = (ev) => alMensaje(p, ev.data);
      w.onerror = (ev) => { ev.preventDefault(); errorPrograma(p, ev.message || "Error en el programa.", null); };
      ejec.progs.set(l.id, p);
      ejec.codigos[l.id] = codigo;
      w.postMessage({ type: "run", codigo: instrumentar(codigo), propia: l.id, nombres, tipos: Object.keys(TIPOS), sensores: Object.keys(SENSOR),
        conf: { fallaRafaga: LAU.fallaRafaga, cadencia: LAU.cadencia, cadenciaRafaga: LAU.cadenciaRafaga }, snap });
    }
    pausa = false;
    pintarControles(); pintarProgs(); pintarEdicion();
  }

  const fmtLugar = (l) => l ? `{x: ${r2(l.x)}, y: ${r2(l.y)}, z: ${r2(l.z || 0)}${l.id ? `, id: "${l.id}"` : ""}}` : "null";
  const fmtValor = (v) => v == null ? "null" : typeof v === "object" ? fmtLugar(v) : String(v);
  function contarUso(id, fn) { const u = mundo.uso[id] || (mundo.uso[id] = {}); u[fn] = (u[fn] || 0) + 1; }

  function alMensaje(p, m) {
    if (!ejec || ejec.progs.get(p.id) !== p || !mundo.activo) return;
    if (m.type === "lee") {
      contarUso(p.id, m.fn);
      const s = mundo.porId[m.maquina]; if (s && s.st && s.st.lecturas != null) s.st.lecturas++;
      registrar(p.id, m.linea, m.que, fmtValor(m.valor), "sensor");
    } else if (m.type === "cmd") {
      contarUso(p.id, m.verbo);
      aplicarOrden(p.id, m);
    } else if (m.type === "consola") {
      mostrarConsola(p.id, m.linea, m.nivel, m.texto);
    } else if (m.type === "espera") {
      contarUso(p.id, "esperar");
      p.estado = "espera"; p.espera = m.id; p.despertar = mundo.t + m.s;
      lineaCorre[p.id] = m.linea; marcasSucias = true;
    } else if (m.type === "done") {
      p.estado = "fin"; p.finT = mundo.t; lineaCorre[p.id] = null; marcasSucias = true; pintarProgs();
    } else if (m.type === "error") {
      return errorPrograma(p, m.mensaje, m.linea);
    }
    if ((m.type === "lee" || m.type === "cmd" || m.type === "consola") && ++p.mensajes > MAX_ORDENES)
      return errorPrograma(p, `El programa de ${p.id} dio ${MAX_ORDENES} órdenes y lecturas sin esperar. ¿Falta await esperar(...) dentro del bucle?`, m.linea);
    if ((m.type === "espera" || m.type === "done") && !algunoCorre()) avanzar();
  }

  function aplicarOrden(id, m) {
    const l = mundo.porId[id];
    if (m.verbo === "stopFire" || !m.lugar) { l.modo = "idle"; l.lugar = null; }
    else {
      const modo = m.verbo === "burstFire" ? "burst" : "regular";
      if (modo === "burst" && l.modo !== "burst") l.falla = Math.max(l.falla, LAU.fallaRafaga);
      l.modo = modo; l.lugar = m.lugar;
    }
    const arg = m.verbo === "stopFire" ? "" : fmtLugar(m.lugar);
    registrar(id, m.linea, `${m.verbo}(${arg})`, m.res, m.res === "ok" ? "ok" : "warn");
  }

  function despertarProgramas() {
    if (!ejec) return false;
    const listos = [...ejec.progs.values()].filter(p => p.estado === "espera" && p.despertar <= mundo.t + 1e-9);
    if (!listos.length) return false;
    const snap = instantanea();
    for (const p of listos) { p.estado = "corre"; p.desde = performance.now(); p.mensajes = 0; p.worker.postMessage({ type: "despierta", id: p.espera, snap }); }
    return true;
  }

  let acum = 0;
  function avanzar() {
    while (acum >= DT && mundo.activo && !mundo.fin && !algunoCorre()) {
      if (despertarProgramas()) break;
      paso(DT); acum -= DT;
    }
  }

  function errorPrograma(p, mensaje, linea) {
    if (!ejec) return;
    lineaErr = { id: p.id, linea }; marcasSucias = true;
    consola("error", p.id, linea, escapeMsg(mensaje));
    terminar("error", "error", mensaje, linea, p.id);
  }
  const escapeMsg = (s) => esc(s);

  function cerrarProgramas() {
    if (ejec) for (const p of ejec.progs.values()) p.worker.terminate();
    ejec = null;
    pausa = false;
    if (mundo) mundo.activo = false;
  }

  function terminar(resultado, motivo, texto, linea, idProg) {
    if (!mundo || mundo.fin) return;
    const m = mundo;
    const codigos = ejec ? ejec.codigos : { ...programas };
    const inicio = ejec ? ejec.inicio : new Date().toISOString();
    const acabados = ejec ? [...ejec.progs.values()].filter(p => p.estado === "fin") : [];
    m.fin = resultado;
    cerrarProgramas();
    if (resultado !== "error") { lineaCorre = {}; marcasSucias = true; }
    const lineas = Object.values(codigos).reduce((a, c) => a + c.split("\n").filter(l => l.trim() && !/^\s*(\/\/|\/\*|\*)/.test(l)).length, 0);
    const cpd = m.derribos ? coste() / m.derribos : null;
    const lanz = Object.fromEntries(m.lanzadores.map(l => [l.id, { ...l.st, fallaMax: r3(l.st.fallaMax), tRafaga: r2(l.st.tRafaga) }]));
    telemetria.push({
      sandbox: "03_lanzamisiles", reto: retoIdx + 1, titulo: def.titulo, intento, semilla, vista, inicio,
      resultado, motivo, mensaje: texto, linea: linea ?? null, programa: idProg ?? null,
      tiempoJuego: r2(m.t), brechas: m.brechas, derribos: m.derribos, enemigos: m.total, misiles: m.consumidos, impactos: m.impactos,
      precision: m.consumidos ? r3(m.impactos / m.consumidos) : null, atascos: m.atascos, reparaciones: m.reparaciones,
      coste: coste(), costePorDerribo: cpd == null ? null : r2(cpd), lanzadores: lanz, detalleAtascos: m.detalleAtascos, uso: m.uso, consolas: m.consolas,
      inserciones: { ...insercion }, lineas, codigos, escenario: retoIdx === IDX_PROPIO ? def : undefined,
    });
    insercion = { dobleClic: 0, arrastre: 0, atajo: 0 };
    guardado.escribir("telemetria", telemetria);
    const stats = `${m.derribos}/${m.total} derribados · ${m.consumidos} misiles · precisión ${m.consumidos ? Math.round(m.impactos / m.consumidos * 100) : 0} % · ${m.atascos} ${m.atascos === 1 ? "atasco" : "atascos"} · ${coma(m.t)} s`;
    if (resultado === "victoria") {
      if (!hechos.includes(claveReto())) { hechos.push(claveReto()); guardado.escribir("hechos", hechos); }
      const ant = records[claveReto()];
      let record;
      if (cpd == null) record = "";
      else if (ant == null || cpd < ant - 1e-9) {
        records[claveReto()] = r2(cpd); guardado.escribir("records", records);
        record = `<p class="record">Coste por derribo <b>₵ ${coma(cpd)}</b> · <span class="mejora">${ant == null ? "primer récord" : `nuevo récord (antes ₵ ${coma(ant)})`}</span></p>`;
      } else record = `<p class="record">Coste por derribo <b>₵ ${coma(cpd)}</b> · <span class="peor">récord ₵ ${coma(ant)} (+${coma(cpd - ant)})</span></p>`;
      const sig = retoIdx + 1 < IDX_PROPIO;
      mostrarBanner("victoria", "Base intacta", record + `<p>₵ ${coste()} en total: ${m.consumidos} misiles × ₵ ${COSTE.misil} + ${m.reparaciones} reparaciones × ₵ ${COSTE.reparacion}. Menos misiles y menos atascos bajan el número.</p>`, stats,
        sig ? [["Siguiente reto", "primario", () => elegirReto(retoIdx + 1)], ["Otra vez", "", ocultarBanner]] : [["Otra vez", "primario", ocultarBanner]]);
      pintarRetos();
    } else if (resultado === "fallo") {
      const comentados = def.lanzadores.filter(l => soloComentarios(codigos[l.id] || "")).map(l => l.id);
      let extra = comentados.length ? ` El programa de ${comentados.join(" y ")} está todo comentado: no hace nada.` : "";
      for (const p of acabados) if (!comentados.includes(p.id)) extra += ` El programa de ${p.id} terminó a los ${p.finT.toFixed(1)} s: desde entonces nadie volvió a apuntar.`;
      mostrarBanner("fallo", "Aún no", esc(texto + extra), `Pista: ${def.pista || "revisa el registro y la consola."}`, [["Editar programa", "primario", ocultarBanner]]);
    } else if (resultado === "error") {
      mostrarBanner("fallo", linea ? `Error en la línea ${linea} de ${idProg}` : `Error en el programa de ${idProg}`, esc(texto), null,
        [["Ir a la línea", "primario", () => { ocultarBanner(); abrirPrograma(idProg); irALinea(linea); }]]);
    }
    pintarControles(); pintarProgs(); pintarResumen(); pintarEdicion(); metasClave = "";
  }

  function detener() { if (ejec) { consola("sistema", null, null, "Programa detenido."); terminar("detenido", "detenido", null); } }

  function vigia(now) {
    if (!ejec) return;
    for (const p of ejec.progs.values()) {
      if (p.estado === "corre" && now - p.desde > VIGIA_MS)
        return errorPrograma(p, `El programa de ${p.id} giró ${VIGIA_MS / 1000} s sin llegar a un await esperar(...), así que el tiempo de juego no puede avanzar. Cada vuelta del bucle necesita una espera.`, lineaCorre[p.id] ?? null);
    }
  }

  // ---------- Consola, globos y avisos a pantalla ----------
  const $consola = $("consola");
  function limpiarConsola() { $consola.innerHTML = `<div class="vacia">Aquí aparecen los console.log / warn / error y lo que reportan las máquinas.</div>`; }
  function consola(cls, id, linea, html) {
    const v = $consola.querySelector(".vacia"); if (v) v.remove();
    const d = document.createElement("div");
    d.className = `c ${cls}`;
    const ref = id ? `<button type="button" class="ref" data-ref="${esc(id)}">${esc(id)}</button>` : "";
    d.innerHTML = `<span class="l">${ref}${linea ? ` L${linea}` : ""}</span><span class="t">${html}</span>`;
    $consola.appendChild(d);
    while ($consola.children.length > 150) $consola.firstChild.remove();
    $consola.scrollTop = $consola.scrollHeight;
  }
  function globo(id, nivel, texto) { globos.set(id, { nivel, texto: String(texto).slice(0, 140), hasta: performance.now() + (nivel === "sistema" ? 2200 : 3000) }); }
  function mostrarConsola(id, linea, nivel, texto) {
    mundo.consolas[nivel] = (mundo.consolas[nivel] || 0) + 1;
    consola(nivel, id, linea, `${nivel === "log" ? "" : `<b>${nivel}</b> `}${esc(texto)}`);
    registrar(id, linea, `console.${nivel}`, texto, nivel === "error" ? "bad" : nivel === "warn" ? "warn" : "sensor");
    if (ruteo[nivel] === "globo") globo(id, nivel, texto);
    else if (ruteo[nivel] === "pantalla") aviso(nivel, id, linea, texto);
  }
  function avisoSistema(texto) { consola("bad", null, null, esc(texto)); aviso("error", null, null, texto); }

  const $avisos = $("avisos");
  function aviso(nivel, id, linea, texto) {
    const ult = $avisos.lastElementChild;
    const clave = `${nivel}|${id}|${texto}`;
    if (ult && ult.dataset.clave === clave) {
      ult.dataset.n = +ult.dataset.n + 1; ult.querySelector(".veces").textContent = `×${ult.dataset.n}`; ult.dataset.hasta = performance.now() + 4500; return;
    }
    const d = document.createElement("div");
    d.className = `toast ${nivel}`; d.dataset.clave = clave; d.dataset.n = 1; d.dataset.hasta = performance.now() + 4500;
    d.innerHTML = `<span class="nivel">${esc(nivel)}</span>${id ? `<button type="button" class="ref" data-ref="${esc(id)}">${esc(id)}</button>` : ""}${linea ? `<span class="veces">L${linea}</span>` : ""}<span class="txt">${esc(texto)}</span><span class="veces"></span>`;
    $avisos.appendChild(d);
    while ($avisos.children.length > 3) $avisos.firstChild.remove();
  }
  function cerrarAvisos() { $avisos.innerHTML = ""; globos.clear(); }
  function caducarAvisos(now) { for (const d of [...$avisos.children]) if (now > +d.dataset.hasta) d.remove(); }
  // Un enlace a una máquina la selecciona y centra la cámara en ella.
  document.addEventListener("click", (ev) => {
    const r = ev.target.closest(".ref[data-ref]"); if (!r) return;
    seleccionar(r.dataset.ref); centrarEn(r.dataset.ref);
  });

  // ---------- Vista 3D ----------
  const leerVar = (k) => getComputedStyle(document.documentElement).getPropertyValue(`--${k}`).trim();
  const V3 = (() => {
    if (typeof THREE === "undefined") return null;
    let renderer;
    try { renderer = new THREE.WebGLRenderer({ canvas: $("c3d"), antialias: true }); } catch { return null; }
    renderer.setPixelRatio(Math.min(2, window.devicePixelRatio || 1));
    const escena = new THREE.Scene();
    const camara = new THREE.PerspectiveCamera(38, 1.6, 0.1, 500);
    const cam = { yaw: 0, pitch: 1.02, dist: 33, x: COLS / 2, z: ROWS / 2 + .5 };
    const cam0 = { ...cam };
    const hemi = new THREE.HemisphereLight(0xffffff, 0x8a9488, 0.85);
    const sol = new THREE.DirectionalLight(0xffffff, 0.55); sol.position.set(-12, 30, 18);
    escena.add(hemi, sol);
    const lam = (k, extra) => new THREE.MeshLambertMaterial({ color: 0xffffff, ...extra, userData: { k } });
    const bas = (k, extra) => new THREE.MeshBasicMaterial({ color: 0xffffff, ...extra, userData: { k } });
    const M = {
      suelo: lam("suelo"), base: bas("accent", { transparent: true, opacity: .1, depthWrite: false }),
      edificio: lam("building"), techo: lam("building-top"), borde: lam("edge"), acento: lam("accent"), mal: lam("bad"),
      enemigo: lam("enemigo"), frio: lam("enemigo-frio", { transparent: true, opacity: .72 }), golpe: lam("bad"),
      misil: bas("misil"), explosion: bas("explosion", { transparent: true, opacity: .4, depthWrite: false }),
      humo: bas("edge", { transparent: true, opacity: .5, depthWrite: false }),
      sombra: bas("ink", { transparent: true, opacity: .16, depthWrite: false }), mira: bas("accent"),
      rVisual: bas("s-visual", { transparent: true, opacity: .75, side: THREE.DoubleSide }), rTermico: bas("s-termico", { transparent: true, opacity: .75, side: THREE.DoubleSide }),
      rVibra: bas("s-vibra", { transparent: true, opacity: .75, side: THREE.DoubleSide }), sel: bas("accent", { side: THREE.DoubleSide }),
      reparador: lam("warn"), vibra: lam("s-vibra"),
    };
    const L = {
      grid: new THREE.LineBasicMaterial({ color: 0xffffff, userData: { k: "grid" } }),
      grid2: new THREE.LineBasicMaterial({ color: 0xffffff, userData: { k: "grid-2" } }),
      brecha: new THREE.LineDashedMaterial({ color: 0xffffff, dashSize: .4, gapSize: .25, userData: { k: "bad" } }),
      altura: new THREE.LineDashedMaterial({ color: 0xffffff, dashSize: .12, gapSize: .1, transparent: true, opacity: .55, userData: { k: "ink" } }),
      estela: new THREE.LineBasicMaterial({ color: 0xffffff, transparent: true, opacity: .7, userData: { k: "misil" } }),
      miraAlt: new THREE.LineDashedMaterial({ color: 0xffffff, dashSize: .15, gapSize: .1, userData: { k: "accent" } }),
    };
    function aplicarColores() {
      for (const m of [...Object.values(M), ...Object.values(L)]) m.color.set(leerVar(m.userData.k) || "#888");
      escena.background = new THREE.Color(leerVar("bg") || "#e9ece6");
      if (escena.fog) escena.fog.color.copy(escena.background);
    }
    const G = {
      caja: (w, h, d) => new THREE.BoxGeometry(w, h, d),
      esfera: new THREE.SphereGeometry(1, 16, 12), disco: new THREE.CircleGeometry(1, 24),
      rotor: new THREE.CylinderGeometry(.15, .15, .025, 12), toro: new THREE.TorusGeometry(.48, .045, 6, 28),
    };
    const fijo = new THREE.Group(), movil = new THREE.Group();
    escena.add(fijo, movil);
    const objetos = new Map();  // id → { grupo, ... }
    const misiles = new Map(), efectos = new Map();
    let anillos = null;
    const mesh = (g, m) => new THREE.Mesh(g, m);
    function lineas(puntos, mat) {
      const g = new THREE.BufferGeometry().setFromPoints(puntos.map(p => new THREE.Vector3(...p)));
      const l = new THREE.LineSegments(g, mat); return l;
    }
    function limpiar(grupo) { while (grupo.children.length) { const c = grupo.children.pop(); c.traverse(o => { if (o.geometry && !Object.values(G).includes(o.geometry)) o.geometry.dispose(); }); } }

    function construir() {
      limpiar(fijo); limpiar(movil); objetos.clear(); misiles.clear(); efectos.clear(); anillos = null;
      const suelo = mesh(new THREE.PlaneGeometry(COLS, ROWS), M.suelo); suelo.rotation.x = -Math.PI / 2; suelo.position.set(COLS / 2, 0, ROWS / 2); fijo.add(suelo);
      const p1 = [], p2 = [];
      for (let i = 0; i <= COLS; i++) (i % 4 ? p1 : p2).push([i, .01, 0], [i, .01, ROWS]);
      for (let j = 0; j <= ROWS; j++) (j % 3 ? p1 : p2).push([0, .01, j], [COLS, .01, j]);
      fijo.add(lineas(p1, L.grid), lineas(p2, L.grid2));
      const zona = mesh(new THREE.PlaneGeometry(LINEA_BASE, ROWS), M.base); zona.rotation.x = -Math.PI / 2; zona.position.set(LINEA_BASE / 2, .015, ROWS / 2); fijo.add(zona);
      const br = lineas([[LINEA_BASE, .03, 0], [LINEA_BASE, .03, ROWS]], L.brecha); br.computeLineDistances(); fijo.add(br);
      escena.fog = mundo.def.niebla ? new THREE.Fog(0xffffff, 10, 34) : null;
      for (const l of mundo.lanzadores) {
        const g = new THREE.Group(); g.position.set(l.cx, 0, l.cy); g.userData.id = l.id;
        const base = mesh(G.caja(1.1, .45, 1.1), M.edificio); base.position.y = .225;
        const tapa = mesh(G.caja(.92, .06, .92), M.techo); tapa.position.y = .48;
        const torre = new THREE.Group(); torre.position.y = .55;
        const pod = mesh(G.caja(.8, .38, .6), M.borde); pod.position.set(.1, .24, 0); pod.rotation.z = .5;
        const frente = mesh(G.caja(.05, .3, .5), M.acento); frente.position.set(.5, .45, 0); frente.rotation.z = .5;
        torre.add(pod, frente);
        g.add(base, tapa, torre); fijo.add(g);
        objetos.set(l.id, { grupo: g, torre, pod, alto: 1.4 });
      }
      for (const s of mundo.sensores) {
        const g = new THREE.Group(); g.position.set(s.cx, 0, s.cy); g.userData.id = s.id;
        const poste = mesh(new THREE.CylinderGeometry(.06, .08, 1.3, 8), M.borde); poste.position.y = .65;
        const cabeza = mesh(new THREE.CylinderGeometry(.28, .28, .1, 16), M.vibra); cabeza.position.y = 1.3;
        const pie = mesh(new THREE.CylinderGeometry(.35, .4, .08, 16), M.edificio); pie.position.y = .04;
        g.add(poste, cabeza, pie); fijo.add(g);
        objetos.set(s.id, { grupo: g, alto: 1.6 });
      }
      { const d = mundo.deposito, g = new THREE.Group(); g.position.set(d.cx, 0, d.cy); g.userData.id = d.id;
        const c = mesh(G.caja(1.4, .7, 1.7), M.edificio); c.position.y = .35;
        const t = mesh(G.caja(1.2, .05, 1.5), M.techo); t.position.y = .72;
        const m1 = mesh(G.caja(.9, .14, .14), M.misil); m1.position.set(0, .82, -.3);
        const m2 = m1.clone(); m2.position.z = .3;
        g.add(c, t, m1, m2); fijo.add(g); objetos.set(d.id, { grupo: g, alto: 1.1 }); }
      for (const r of mundo.reparadores) {
        const g = new THREE.Group(); g.userData.id = r.id;
        const c = mesh(G.caja(.46, .32, .46), M.reparador); c.position.y = .2;
        const a = mesh(G.caja(.04, .35, .04), M.borde); a.position.set(.12, .5, .12);
        g.add(c, a); movil.add(g); objetos.set(r.id, { grupo: g, alto: .9 });
      }
      for (const l of mundo.lanzadores) {
        const mira = mesh(G.toro, M.mira); mira.rotation.x = Math.PI / 2; mira.visible = false;
        const alt = new THREE.Line(new THREE.BufferGeometry().setFromPoints([new THREE.Vector3(), new THREE.Vector3(0, 1, 0)]), L.miraAlt); alt.visible = false;
        movil.add(mira, alt); objetos.get(l.id).mira = mira; objetos.get(l.id).miraAlt = alt;
      }
      aplicarColores();
      anillosDe(seleccion);
    }

    function enemigoMesh(e) {
      const g = new THREE.Group(); g.userData.id = e.id;
      const tp = TIPOS[e.tipo], mat = tp.frio ? M.frio : M.enemigo;
      if (tp.suelo) {
        const cuerpo = mesh(G.caja(.82, .4, .6), mat); cuerpo.position.y = .3;
        const o1 = mesh(G.caja(.9, .2, .14), M.borde); o1.position.set(0, .1, .3);
        const o2 = o1.clone(); o2.position.z = -.3;
        g.add(cuerpo, o1, o2);
        return { grupo: g, cuerpo, mat };
      }
      const cuerpo = mesh(G.esfera, mat); cuerpo.scale.setScalar(.22);
      const brazo1 = mesh(G.caja(.85, .04, .06), M.borde), brazo2 = brazo1.clone(); brazo2.rotation.y = Math.PI / 2;
      const rotores = [[.4, 0], [-.4, 0], [0, .4], [0, -.4]].map(([x, z]) => { const r = mesh(G.rotor, M.borde); r.position.set(x, .06, z); return r; });
      const cuerpoG = new THREE.Group(); cuerpoG.add(cuerpo, brazo1, brazo2, ...rotores);
      const sombra = mesh(G.disco, M.sombra); sombra.rotation.x = -Math.PI / 2; sombra.scale.setScalar(.36); sombra.position.y = .02;
      const alt = new THREE.Line(new THREE.BufferGeometry().setFromPoints([new THREE.Vector3(0, 0, 0), new THREE.Vector3(0, 1, 0)]), L.altura);
      alt.computeLineDistances();
      g.add(cuerpoG, sombra, alt);
      return { grupo: g, cuerpo, cuerpoG, sombra, alt, rotores, mat };
    }

    function anillosDe(id) {
      if (anillos) { movil.remove(anillos); anillos.traverse(o => o.geometry && o.geometry.dispose()); anillos = null; }
      if (!mundo || !id) return;
      const e = mundo.porId[id];
      const grupo = new THREE.Group();
      const anillo = (r, mat, x, z) => { const a = mesh(new THREE.RingGeometry(r - .05, r + .05, 96), mat); a.rotation.x = -Math.PI / 2; a.position.set(x, .04, z); grupo.add(a); };
      if (e && e.clase === "lanzador") { anillo(alcance("visual"), M.rVisual, e.cx, e.cy); anillo(alcance("thermal"), M.rTermico, e.cx, e.cy); anillo(.9, M.sel, e.cx, e.cy); }
      else if (e && e.clase === "vibracion") { anillo(e.alcance, M.rVibra, e.cx, e.cy); anillo(.6, M.sel, e.cx, e.cy); }
      else if (e) anillo(.95, M.sel, e.cx, e.cy);
      else { const en = mundo.enemigos.find(x => x.id === id); if (!en) return; anillo(.6, M.sel, 0, 0); grupo.userData.sigue = id; }
      anillos = grupo; movil.add(grupo);
      for (const otro of seleccionadas) {
        if (otro === id) continue;
        const u = mundo.porId[otro] || mundo.enemigos.find(e => e.id === otro);
        if (!u) continue;
        const a = mesh(new THREE.RingGeometry(.55, .65, 32), M.sel);
        a.rotation.x = -Math.PI / 2;
        a.userData.unidad = otro;
        grupo.add(a);
      }
    }

    function posMisil(mi, t) {
      const u = Math.min(1, Math.max(0, (t - mi.t0) / mi.dur));
      return [mi.x0 + (mi.x1 - mi.x0) * u, mi.z0 + (mi.z1 - mi.z0) * u + mi.arco * 4 * u * (1 - u), mi.y0 + (mi.y1 - mi.y0) * u];
    }

    function actualizar(off, ahora) {
      const t = mundo.t + off;
      for (const l of mundo.lanzadores) {
        const o = objetos.get(l.id);
        o.torre.rotation.y = -l.yaw;
        o.pod.material = l.atascado ? M.mal : M.borde;
        if (l.lugar && !l.atascado && l.modo !== "idle") {
          o.mira.visible = true; o.mira.position.set(l.lugar.x, (l.lugar.z || 0) + .03, l.lugar.y);
          const z = l.lugar.z || 0;
          o.miraAlt.visible = z > 0.05;
          if (z > .05) { o.miraAlt.position.set(l.lugar.x, 0, l.lugar.y); o.miraAlt.scale.set(1, z, 1); o.miraAlt.computeLineDistances(); }
        } else { o.mira.visible = false; o.miraAlt.visible = false; }
      }
      for (const r of mundo.reparadores) { const o = objetos.get(r.id); o.grupo.position.set(r.cx, 0, r.cy); o.grupo.rotation.y = r.estado === "reparar" ? ahora / 160 : 0; }
      const vivos = new Set();
      for (const e of mundo.enemigos) {
        vivos.add(e.id);
        let o = objetos.get(e.id);
        if (!o) { o = enemigoMesh(e); objetos.set(e.id, o); movil.add(o.grupo); }
        const x = e.x + e.vx * off, y = e.y + e.vy * off;
        o.grupo.position.set(x, 0, y);
        o.cuerpo.material = mundo.t - e.golpeT < .25 ? M.golpe : o.mat;
        if (o.cuerpoG) {
          o.cuerpoG.position.y = e.z;
          o.alt.scale.set(1, e.z, 1);
          for (const r of o.rotores) r.rotation.y = ahora / 40;
        }
      }
      for (const [id, o] of objetos) if (o.mat && !vivos.has(id)) { movil.remove(o.grupo); objetos.delete(id); }
      const enVuelo = new Set();
      for (const mi of mundo.misiles) {
        enVuelo.add(mi.id);
        let o = misiles.get(mi.id);
        if (!o) {
          const bola = mesh(G.esfera, M.misil); bola.scale.setScalar(.12);
          const g = new THREE.BufferGeometry(); g.setAttribute("position", new THREE.BufferAttribute(new Float32Array(30), 3));
          const estela = new THREE.Line(g, L.estela); estela.frustumCulled = false;
          o = { bola, estela }; misiles.set(mi.id, o); movil.add(bola, estela);
        }
        const p = posMisil(mi, t); o.bola.position.set(...p);
        const arr = o.estela.geometry.attributes.position.array;
        for (let k = 0; k < 10; k++) { const q = posMisil(mi, t - k * .03); arr[k * 3] = q[0]; arr[k * 3 + 1] = q[1]; arr[k * 3 + 2] = q[2]; }
        o.estela.geometry.attributes.position.needsUpdate = true;
      }
      for (const [id, o] of misiles) if (!enVuelo.has(id)) { movil.remove(o.bola, o.estela); o.estela.geometry.dispose(); misiles.delete(id); }
      const vistos = new Set();
      for (const x of mundo.explosiones) {
        const k = `${x.t0}|${x.x}|${x.y}`; vistos.add(k);
        let o = efectos.get(k);
        if (!o) { o = mesh(G.esfera, (x.atasco ? M.humo : M.explosion).clone()); efectos.set(k, o); movil.add(o); }
        const u = Math.min(1, (t - x.t0) / (x.atasco ? .8 : .35));
        o.position.set(x.x, x.atasco ? 1 + u * .8 : x.z, x.y);
        o.scale.setScalar((x.atasco ? .5 : MISIL.radio) * (.25 + .75 * Math.min(1, u * 1.4)));
        o.material.opacity = (x.atasco ? .55 : .42) * (1 - Math.max(0, (t - x.t0 - .25) / .5));
      }
      for (const [k, o] of efectos) if (!vistos.has(k)) { movil.remove(o); o.material.dispose(); efectos.delete(k); }
      if (anillos && anillos.userData.sigue) {
        const en = mundo.enemigos.find(x => x.id === anillos.userData.sigue);
        if (en) anillos.position.set(en.x + en.vx * off, en.z, en.y); else anillos.visible = false;
      }
      if (anillos) for (const a of anillos.children) {
        if (!a.userData.unidad) continue;
        const u = mundo.porId[a.userData.unidad] || mundo.enemigos.find(e => e.id === a.userData.unidad);
        a.visible = !!u;
        if (u) a.position.set((u.cx ?? u.x) - anillos.position.x, .04 - anillos.position.y, (u.cy ?? u.y) - anillos.position.z);
      }
    }

    function colocarCamara() {
      const cp = Math.cos(cam.pitch);
      camara.position.set(cam.x + cam.dist * cp * Math.sin(cam.yaw), cam.dist * Math.sin(cam.pitch), cam.z + cam.dist * cp * Math.cos(cam.yaw));
      camara.lookAt(cam.x, 0, cam.z);
    }
    // En pantallas estrechas la cámara se aleja para que quepan las 32 columnas.
    let camaraMovida = false;
    function tamano(w, h) {
      renderer.setSize(w, h, false); camara.aspect = w / h; camara.updateProjectionMatrix();
      cam0.dist = camara.aspect < 1.5 ? 33 * 1.5 / camara.aspect : 33;
      if (!camaraMovida) cam.dist = cam0.dist;
    }
    function render() {
      colocarCamara();
      if (escena.fog) { escena.fog.near = cam.dist * .55; escena.fog.far = cam.dist * 1.75; }
      renderer.render(escena, camara);
    }
    const v = new THREE.Vector3();
    function proyectar(x, alto, y, w, h) {
      v.set(x, alto, y).project(camara);
      return { x: (v.x + 1) / 2 * w, y: (1 - v.y) / 2 * h, visible: v.z < 1 && v.z > -1 };
    }
    const ray = new THREE.Raycaster(), ndc = new THREE.Vector2();
    function elegir(px, py, w, h) {
      ndc.set(px / w * 2 - 1, -(py / h) * 2 + 1);
      ray.setFromCamera(ndc, camara);
      const hits = ray.intersectObjects([...fijo.children, ...movil.children], true);
      for (const hit of hits) { let o = hit.object; while (o && !o.userData.id) o = o.parent; if (o) return o.userData.id; }
      return null;
    }
    function suelo(px, py, w, h) {
      ndc.set(px / w * 2 - 1, -(py / h) * 2 + 1);
      ray.setFromCamera(ndc, camara);
      const punto = ray.ray.intersectPlane(new THREE.Plane(new THREE.Vector3(0, 1, 0), 0), new THREE.Vector3());
      return punto ? { x: punto.x, y: punto.z, z: 0 } : null;
    }
    function centrar(x, y) { cam.x = x; cam.z = y + 1; cam.dist = Math.min(cam.dist, 22); camaraMovida = true; }
    function recentrar() { Object.assign(cam, cam0); camaraMovida = false; }

    // Cámara: rueda presionada = orbitar · botón derecho o dos dedos = desplazar.
    // El botón izquierdo y la selección táctil se manejan juntos en el campo.
    const canvas = $("c3d"), punteros = new Map();
    let gesto = null;
    canvas.addEventListener("contextmenu", (ev) => ev.preventDefault());
    canvas.addEventListener("pointerdown", (ev) => {
      if (ev.pointerType !== "touch" && ev.button !== 1 && ev.button !== 2) return;
      canvas.setPointerCapture(ev.pointerId);
      punteros.set(ev.pointerId, { x: ev.clientX, y: ev.clientY });
      gesto = { movido: 0, desplazar: ev.button === 2, tactil: ev.pointerType === "touch", dist0: null };
      camaraMovida = true;
    });
    canvas.addEventListener("pointermove", (ev) => {
      const p = punteros.get(ev.pointerId); if (!p || !gesto) return;
      const dx = ev.clientX - p.x, dy = ev.clientY - p.y;
      p.x = ev.clientX; p.y = ev.clientY;
      gesto.movido += Math.abs(dx) + Math.abs(dy);
      if (punteros.size >= 2) {
        const [a, b] = [...punteros.values()], d = Math.hypot(a.x - b.x, a.y - b.y);
        if (gesto.dist0) cam.dist = Math.min(70, Math.max(8, cam.dist * gesto.dist0 / d));
        gesto.dist0 = d;
        desplazar(dx / 2, dy / 2);
      } else if (gesto.tactil && arrastreCampo && arrastreCampo.modo === "seleccion") return;
      else if (gesto.desplazar || gesto.tactil) desplazar(dx, dy);
      else { cam.yaw -= dx * .006; cam.pitch = Math.min(1.5, Math.max(.28, cam.pitch + dy * .005)); }
    });
    const soltar = (ev) => {
      punteros.delete(ev.pointerId);
      if (gesto && punteros.size === 0) {
        gesto = null;
      } else if (gesto) gesto.dist0 = null;
    };
    canvas.addEventListener("pointerup", soltar);
    canvas.addEventListener("pointercancel", (ev) => { punteros.delete(ev.pointerId); gesto = null; });
    canvas.addEventListener("wheel", (ev) => { ev.preventDefault(); camaraMovida = true; cam.dist = Math.min(70, Math.max(8, cam.dist * Math.exp(ev.deltaY * .0012))); }, { passive: false });
    function desplazar(dx, dy) {
      const k = cam.dist * .0022;
      const sx = Math.cos(cam.yaw), sz = -Math.sin(cam.yaw);
      cam.x = Math.min(COLS, Math.max(0, cam.x - (dx * sx + dy * Math.sin(cam.yaw)) * k));
      cam.z = Math.min(ROWS + 4, Math.max(-2, cam.z - (dx * sz + dy * Math.cos(cam.yaw)) * k));
    }
    return { construir, actualizar, render, tamano, proyectar, elegir, suelo, centrar, recentrar, anillosDe, aplicarColores };
  })();

  // ---------- Vista de plano (2D) ----------
  const $c2d = $("c2d"), ctx2 = $c2d.getContext("2d");
  let col = {};
  function leerColores() {
    for (const k of ["bg", "surface", "ink", "muted", "line", "grid", "grid-2", "suelo", "building", "building-top", "edge", "accent", "accent-soft", "bad", "warn", "base", "enemigo", "enemigo-frio", "misil", "explosion", "s-visual", "s-termico", "s-vibra"]) col[k] = leerVar(k);
    if (V3) V3.aplicarColores();
  }
  let geo2 = { T: 10, ox: 0, oy: 0 };
  function dibujar2D(off) {
    const dpr = window.devicePixelRatio || 1, W = $c2d.clientWidth, H = $c2d.clientHeight;
    if (!W || !H) return;
    if ($c2d.width !== Math.round(W * dpr) || $c2d.height !== Math.round(H * dpr)) { $c2d.width = Math.round(W * dpr); $c2d.height = Math.round(H * dpr); }
    const T = Math.min(W / COLS, (H - 40) / ROWS), ox = (W - T * COLS) / 2, oy = Math.max(36, (H - T * ROWS) / 2);
    geo2 = { T, ox, oy };
    const c = ctx2, P = (x) => ox + x * T, Q = (y) => oy + y * T;
    c.setTransform(dpr, 0, 0, dpr, 0, 0);
    c.fillStyle = col.bg; c.fillRect(0, 0, W, H);
    c.fillStyle = col.suelo; c.fillRect(ox, oy, COLS * T, ROWS * T);
    c.fillStyle = col.base; c.fillRect(ox, oy, LINEA_BASE * T, ROWS * T);
    c.lineWidth = 1;
    for (const [paso2, color] of [[1, col.grid], [4, col["grid-2"]]]) {
      c.strokeStyle = color; c.beginPath();
      for (let i = 0; i <= COLS; i += paso2) { c.moveTo(Math.round(P(i)) + .5, oy); c.lineTo(Math.round(P(i)) + .5, oy + ROWS * T); }
      for (let j = 0; j <= ROWS; j += paso2 === 4 ? 3 : 1) { c.moveTo(ox, Math.round(Q(j)) + .5); c.lineTo(ox + COLS * T, Math.round(Q(j)) + .5); }
      c.stroke();
    }
    c.fillStyle = col.muted; c.font = `500 ${Math.max(8, T * .38)}px "JetBrains Mono", monospace`; c.textAlign = "center"; c.textBaseline = "bottom";
    for (let i = 0; i <= COLS; i += 4) c.fillText(i, P(i), oy - 2);
    c.strokeStyle = col.bad; c.setLineDash([5, 4]); c.lineWidth = 2; c.beginPath(); c.moveTo(P(LINEA_BASE), oy); c.lineTo(P(LINEA_BASE), oy + ROWS * T); c.stroke(); c.setLineDash([]);
    if (mundo.def.niebla) { c.fillStyle = col.surface; c.globalAlpha = .28; c.fillRect(ox, oy, COLS * T, ROWS * T); c.globalAlpha = 1; }
    // Alcances de la máquina elegida
    const sel = seleccion && mundo.porId[seleccion];
    const aro = (x, y, r, color, dash) => { c.strokeStyle = color; c.lineWidth = 1.5; c.setLineDash(dash || []); c.beginPath(); c.arc(P(x), Q(y), r * T, 0, Math.PI * 2); c.stroke(); c.setLineDash([]); };
    if (sel && sel.clase === "lanzador") { aro(sel.cx, sel.cy, alcance("visual"), col["s-visual"]); aro(sel.cx, sel.cy, alcance("thermal"), col["s-termico"], [6, 4]); }
    if (sel && sel.clase === "vibracion") aro(sel.cx, sel.cy, sel.alcance, col["s-vibra"], [3, 3]);
    // Edificios
    const caja = (x, y, w, h, relleno, borde) => { c.fillStyle = relleno; c.strokeStyle = borde; c.lineWidth = 1.5; c.beginPath(); c.roundRect(P(x - w / 2), Q(y - h / 2), w * T, h * T, T * .18); c.fill(); c.stroke(); };
    const d = mundo.deposito; caja(d.cx, d.cy, 1.4, 1.7, col.building, col.edge);
    c.fillStyle = col.misil; c.fillRect(P(d.cx - .45), Q(d.cy - .35), .9 * T, .14 * T); c.fillRect(P(d.cx - .45), Q(d.cy + .2), .9 * T, .14 * T);
    for (const s of mundo.sensores) {
      c.fillStyle = col["s-vibra"]; c.beginPath(); c.arc(P(s.cx), Q(s.cy), T * .32, 0, Math.PI * 2); c.fill();
      c.strokeStyle = col["s-vibra"]; c.lineWidth = 1; for (const k of [.55, .8]) { c.beginPath(); c.arc(P(s.cx), Q(s.cy), T * k, 0, Math.PI * 2); c.stroke(); }
    }
    for (const l of mundo.lanzadores) {
      caja(l.cx, l.cy, 1.1, 1.1, col.building, l.atascado ? col.bad : seleccionadas.has(l.id) ? col.accent : col.edge);
      c.strokeStyle = l.atascado ? col.bad : col.ink; c.lineWidth = Math.max(2, T * .18); c.lineCap = "round";
      c.beginPath(); c.moveTo(P(l.cx), Q(l.cy)); c.lineTo(P(l.cx + Math.cos(l.yaw) * .7), Q(l.cy + Math.sin(l.yaw) * .7)); c.stroke(); c.lineCap = "butt";
      if (l.lugar && !l.atascado && l.modo !== "idle") {
        const x = P(l.lugar.x), y = Q(l.lugar.y), r = T * .45;
        c.strokeStyle = col.accent; c.lineWidth = 1.5; c.beginPath(); c.arc(x, y, r, 0, Math.PI * 2); c.moveTo(x - r * 1.4, y); c.lineTo(x + r * 1.4, y); c.moveTo(x, y - r * 1.4); c.lineTo(x, y + r * 1.4); c.stroke();
        if ((l.lugar.z || 0) > .05) { c.fillStyle = col.accent; c.font = `700 ${Math.max(9, T * .42)}px "JetBrains Mono", monospace`; c.textAlign = "left"; c.textBaseline = "bottom"; c.fillText(`↑${r2(l.lugar.z)}`, x + r, y - r * .6); }
      }
    }
    for (const r of mundo.reparadores) { c.fillStyle = col.warn; c.fillRect(P(r.cx) - T * .23, Q(r.cy) - T * .23, T * .46, T * .46); }
    // Enemigos: la sombra desplazada indica la altura.
    for (const e of mundo.enemigos) {
      const x = P(e.x + e.vx * off), y = Q(e.y + e.vy * off), tp = TIPOS[e.tipo], golpe = mundo.t - e.golpeT < .25;
      const color = golpe ? col.bad : tp.frio ? col["enemigo-frio"] : col.enemigo;
      if (tp.suelo) {
        c.fillStyle = color; c.beginPath(); c.roundRect(x - T * .4, y - T * .3, T * .8, T * .6, T * .1); c.fill();
        for (let k = 0; k < e.hpMax; k++) { c.fillStyle = k < e.hp ? col.surface : col.edge; c.fillRect(x - T * .3 + k * T * .22, y - T * .06, T * .14, T * .12); }
      } else {
        const sx = x + e.z * T * .28, sy = y + e.z * T * .28;
        c.fillStyle = col.ink; c.globalAlpha = .16; c.beginPath(); c.ellipse(sx, sy, T * .32, T * .2, 0, 0, Math.PI * 2); c.fill(); c.globalAlpha = 1;
        c.strokeStyle = color; c.lineWidth = 1; c.setLineDash([2, 2]); c.beginPath(); c.moveTo(x, y); c.lineTo(sx, sy); c.stroke(); c.setLineDash([]);
        c.beginPath(); c.moveTo(x, y - T * .36); c.lineTo(x + T * .36, y); c.lineTo(x, y + T * .36); c.lineTo(x - T * .36, y); c.closePath();
        if (tp.frio) { c.strokeStyle = color; c.lineWidth = 2; c.stroke(); } else { c.fillStyle = color; c.fill(); }
      }
      if (seleccionadas.has(e.id)) { c.strokeStyle = col.accent; c.lineWidth = 2; c.beginPath(); c.arc(x, y, T * .62, 0, Math.PI * 2); c.stroke(); }
    }
    const t = mundo.t + off;
    for (const mi of mundo.misiles) {
      const u = Math.min(1, Math.max(0, (t - mi.t0) / mi.dur));
      const x = P(mi.x0 + (mi.x1 - mi.x0) * u), y = Q(mi.y0 + (mi.y1 - mi.y0) * u);
      c.strokeStyle = col.misil; c.lineWidth = 1.5; c.beginPath(); c.moveTo(P(mi.x0 + (mi.x1 - mi.x0) * Math.max(0, u - .18)), Q(mi.y0 + (mi.y1 - mi.y0) * Math.max(0, u - .18))); c.lineTo(x, y); c.stroke();
      c.fillStyle = col.misil; c.beginPath(); c.arc(x, y, T * .14, 0, Math.PI * 2); c.fill();
    }
    // Explosiones: llena = en el suelo, con borde discontinuo y altura = en el aire.
    for (const x of mundo.explosiones) {
      const u = Math.min(1, (t - x.t0) / .35), a = 1 - Math.max(0, (t - x.t0 - .25) / .5);
      if (x.atasco) { c.fillStyle = col.edge; c.globalAlpha = .5 * a; c.beginPath(); c.arc(P(x.x), Q(x.y), T * .7 * u, 0, Math.PI * 2); c.fill(); c.globalAlpha = 1; continue; }
      const r = MISIL.radio * T * (.25 + .75 * Math.min(1, u * 1.4));
      c.globalAlpha = .38 * a; c.fillStyle = col.explosion; c.beginPath(); c.arc(P(x.x), Q(x.y), r, 0, Math.PI * 2); c.fill(); c.globalAlpha = Math.max(0, a);
      if (x.z > .05) {
        c.strokeStyle = col.explosion; c.setLineDash([4, 3]); c.lineWidth = 1.5; c.stroke(); c.setLineDash([]);
        c.fillStyle = col.ink; c.font = `600 ${Math.max(8, T * .36)}px "JetBrains Mono", monospace`; c.textAlign = "center"; c.textBaseline = "middle"; c.fillText(`↑${r2(x.z)}`, P(x.x), Q(x.y));
      }
      c.globalAlpha = 1;
    }
  }
  function proyectar2D(x, y) { return { x: geo2.ox + x * geo2.T, y: geo2.oy + y * geo2.T, visible: true }; }
  function elegir2D(px, py) {
    const x = (px - geo2.ox) / geo2.T, y = (py - geo2.oy) / geo2.T;
    let mejor = null, dm = .9;
    for (const e of [...mundo.maquinas, ...mundo.enemigos]) { const ex = e.cx ?? e.x, ey = e.cy ?? e.y, d = Math.hypot(ex - x, ey - y); if (d < dm) { dm = d; mejor = e.id; } }
    return mejor;
  }
  // Ratón y tacto comparten la selección. La cámara conserva sus botones y los gestos de dos dedos.
  const LARGO_MS = 480, $campo = $("campo"), $carga = $("carga");
  const $cajaSeleccion = $("seleccion-caja"), punterosCampo = new Set();
  let largo = null, arrastreCampo = null, ultimoToque = null, tFicha = 0;
  let campoCoordenadas = null;
  const unidades = () => [...mundo.maquinas, ...mundo.enemigos];
  const unidadPorId = (id) => mundo.porId[id] || mundo.enemigos.find(e => e.id === id);
  function puntoPantalla(e) {
    const r = $campo.getBoundingClientRect();
    const p = vista === "3d" && V3
      ? V3.proyectar(e.cx ?? e.x, e.z || 0, e.cy ?? e.y, r.width, r.height)
      : proyectar2D(e.cx ?? e.x, e.cy ?? e.y);
    return { x: p.x + r.left, y: p.y + r.top, visible: p.visible && p.x >= 0 && p.x <= r.width && p.y >= 0 && p.y <= r.height };
  }
  function unidadEn(cx, cy) {
    const r = $campo.getBoundingClientRect(), x = cx - r.left, y = cy - r.top;
    return vista === "3d" && V3 ? V3.elegir(x, y, r.width, r.height) : elegir2D(x, y);
  }
  function coordenadasEn(cx, cy) {
    const r = $campo.getBoundingClientRect(), x = cx - r.left, y = cy - r.top;
    const p = vista === "3d" && V3 ? V3.suelo(x, y, r.width, r.height) : { x: (x - geo2.ox) / geo2.T, y: (y - geo2.oy) / geo2.T, z: 0 };
    return p && p.x >= 0 && p.x <= COLS && p.y >= 0 && p.y <= ROWS ? { x: r2(p.x), y: r2(p.y), z: 0 } : null;
  }
  document.addEventListener("focusin", (ev) => {
    if (ev.target.matches("[data-coordenadas]")) campoCoordenadas = ev.target;
    else campoCoordenadas = null;
  });
  function escribirCoordenadas(x, y) {
    if (!campoCoordenadas || !campoCoordenadas.isConnected || campoCoordenadas.disabled || campoCoordenadas.readOnly) return false;
    const p = coordenadasEn(x, y);
    if (p) {
      campoCoordenadas.value = fmtLugar(p);
      campoCoordenadas.dispatchEvent(new Event("input", { bubbles: true }));
      campoCoordenadas.dispatchEvent(new Event("change", { bubbles: true }));
    }
    return true;
  }
  function igualesVisibles(id) {
    const e = unidadPorId(id);
    if (!e) return;
    const tipo = (u) => u.clase || `enemigo:${u.tipo}`;
    seleccionar(unidades().filter(u => tipo(u) === tipo(e) && puntoPantalla(u).visible).map(u => u.id));
  }
  function dobleEnCampo(x, y) {
    clearTimeout(tFicha); ultimoToque = null;
    if (escribirCoordenadas(x, y)) return;
    const id = unidadEn(x, y);
    if (id) igualesVisibles(id);
  }
  $campo.addEventListener("dblclick", (ev) => {
    if (ev.button !== 0 || ev.target.tagName !== "CANVAS") return;
    ev.preventDefault();
    // El doble toque ya se procesa en pointerup, sin depender del clic sintético.
    if (ev.sourceCapabilities && ev.sourceCapabilities.firesTouchEvents) return;
    dobleEnCampo(ev.clientX, ev.clientY);
  });
  function cancelarLargo() { if (largo) { cancelAnimationFrame(largo.raf); clearTimeout(largo.fin); } largo = null; $carga.hidden = true; }
  function cancelarArrastre() {
    cancelarLargo(); arrastreCampo = null; $cajaSeleccion.hidden = true;
  }
  $campo.addEventListener("pointerdown", (ev) => {
    if (ev.target.tagName !== "CANVAS") return;
    cerrarHoja();
    clearTimeout(tFicha);
    punterosCampo.add(ev.pointerId);
    if (punterosCampo.size > 1) { cancelarArrastre(); ultimoToque = null; return; }
    if (ev.button !== 0) return;
    ev.target.setPointerCapture(ev.pointerId);
    // Evita que el mapa quite el foco al destino de coordenadas.
    if (campoCoordenadas) ev.preventDefault();
    const id = unidadEn(ev.clientX, ev.clientY);
    arrastreCampo = { puntero: ev.pointerId, tactil: ev.pointerType === "touch", x: ev.clientX, y: ev.clientY, px: ev.clientX, py: ev.clientY, t0: performance.now(), id, modo: null, movido: false, base: ev.shiftKey ? [...seleccionadas] : [] };
    if (!id || campoCoordenadas) return;
    const r = $campo.getBoundingClientRect();
    largo = { puntero: ev.pointerId, id, x: ev.clientX, y: ev.clientY, t0: performance.now(), raf: 0 };
    $carga.style.left = `${ev.clientX - r.left}px`; $carga.style.top = `${ev.clientY - r.top}px`; $carga.style.setProperty("--p", 0);
    // El temporizador decide; el anillo solo acompaña (sin fotogramas, la ficha se abre igual).
    largo.fin = setTimeout(() => {
      if (!arrastreCampo || !largo) return;
      const elegido = largo.id;
      arrastreCampo.ficha = true;
      const ids = arrastreCampo.modo === "seleccion" ? [...seleccionadas] : [elegido];
      cancelarLargo(); seleccionar(ids, { inspeccionar: false });
      // El dedo sigue capturado por el mapa para poder continuar seleccionando.
      ponerInspector("abierto");
      if (navigator.vibrate) navigator.vibrate(12);
    }, LARGO_MS);
    const tick = (now) => {
      if (!largo) return;
      const u = (now - largo.t0 - 110) / (LARGO_MS - 110);
      if (u > 0) { $carga.hidden = false; $carga.style.setProperty("--p", Math.min(1, u).toFixed(3)); }
      largo.raf = requestAnimationFrame(tick);
    };
    largo.raf = requestAnimationFrame(tick);
  }, true);
  function sumarRecorrido(a, x, y) {
    const ids = new Set(a.modo === "seleccion" ? seleccionadas : a.base);
    if (a.id) ids.add(a.id);
    const dx = x - a.px, dy = y - a.py, d2 = dx * dx + dy * dy;
    for (const u of unidades()) {
      const p = puntoPantalla(u); if (!p.visible) continue;
      const t = d2 ? Math.max(0, Math.min(1, ((p.x - a.px) * dx + (p.y - a.py) * dy) / d2)) : 0;
      if (Math.hypot(p.x - a.px - t * dx, p.y - a.py - t * dy) <= 18) ids.add(u.id);
    }
    a.modo = "seleccion";
    seleccionar([...ids], { inspeccionar: false });
  }
  $campo.addEventListener("pointermove", (ev) => {
    const a = arrastreCampo;
    if (!a || a.puntero !== ev.pointerId) return;
    const distancia = Math.hypot(ev.clientX - a.x, ev.clientY - a.y);
    if (distancia > 8) a.movido = true;
    if (a.tactil) {
      if (a.modo === "camara") return;
      if (a.movido && a.modo !== "seleccion" && performance.now() - a.t0 < LARGO_MS / 3) { a.modo = "camara"; cancelarLargo(); return; }
      if (a.movido && (a.modo === "seleccion" || performance.now() - a.t0 >= LARGO_MS / 3)) sumarRecorrido(a, ev.clientX, ev.clientY);
    } else if (a.movido) {
      cancelarLargo(); a.modo = "caja";
      const r = $campo.getBoundingClientRect();
      $cajaSeleccion.hidden = false;
      Object.assign($cajaSeleccion.style, { left: `${Math.min(a.x, ev.clientX) - r.left}px`, top: `${Math.min(a.y, ev.clientY) - r.top}px`, width: `${Math.abs(ev.clientX - a.x)}px`, height: `${Math.abs(ev.clientY - a.y)}px` });
    }
    a.px = ev.clientX; a.py = ev.clientY;
  }, true);
  $campo.addEventListener("pointerup", (ev) => {
    punterosCampo.delete(ev.pointerId);
    const a = arrastreCampo;
    if (!a || a.puntero !== ev.pointerId) return;
    if (a.modo === "caja") {
      seleccionar([...a.base, ...unidades().filter(u => {
        const p = puntoPantalla(u);
        return p.visible && p.x >= Math.min(a.x, ev.clientX) && p.x <= Math.max(a.x, ev.clientX) && p.y >= Math.min(a.y, ev.clientY) && p.y <= Math.max(a.y, ev.clientY);
      }).map(u => u.id)]);
    } else if (a.modo === "seleccion") seleccionar([...seleccionadas]);
    else if (!a.movido && !a.ficha) {
      if (a.tactil) {
        const ahora = performance.now();
        if (ultimoToque && ahora - ultimoToque.t < 320 && Math.hypot(ev.clientX - ultimoToque.x, ev.clientY - ultimoToque.y) < 24) dobleEnCampo(ev.clientX, ev.clientY);
        else {
          ultimoToque = { t: ahora, x: ev.clientX, y: ev.clientY };
          if (!campoCoordenadas) {
            seleccionar(a.id, { inspeccionar: false });
            tFicha = setTimeout(() => { if (seleccion) ponerInspector(inspectorCompleto() ? "abierto" : "tira"); }, 320);
          }
        }
      } else if (!campoCoordenadas) seleccionar(a.base.length ? [...a.base, a.id].filter(Boolean) : a.id);
    }
    cancelarArrastre();
  }, true);
  for (const tipo of ["pointercancel", "lostpointercapture"]) $campo.addEventListener(tipo, (ev) => {
    punterosCampo.delete(ev.pointerId);
    if (arrastreCampo && arrastreCampo.puntero === ev.pointerId) cancelarArrastre();
  }, true);
  addEventListener("blur", () => { clearTimeout(tFicha); punterosCampo.clear(); cancelarArrastre(); });

  // ---------- Etiquetas y globos sobre el campo ----------
  const $capa = $("capa"), etiquetas = new Map();
  function pintarCapa(off, ahora) {
    const W = $capa.clientWidth, H = $capa.clientHeight;
    const vivos = new Set();
    for (const e of mundo.maquinas) {
      const alto = e.clase === "lanzador" ? 1.45 : e.clase === "vibracion" ? 1.7 : e.clase === "deposito" ? 1.1 : .9;
      const p = vista === "3d" && V3 ? V3.proyectar(e.cx, alto, e.cy, W, H) : proyectar2D(e.cx, e.cy - .65);
      vivos.add(e.id);
      let o = etiquetas.get(e.id);
      if (!o) {
        const etq = document.createElement("div"); etq.className = "etq";
        const g = document.createElement("div"); g.className = "globo"; g.hidden = true;
        $capa.append(etq, g); o = { etq, g, texto: "", txtEtq: "" }; etiquetas.set(e.id, o);
      }
      const atasco = e.clase === "lanzador" && e.atascado;
      const txt = e.clase === "lanzador" ? `${e.id} · ${e.misiles}▮${atasco ? " ⚠" : ""}` : e.id;
      if (txt !== o.txtEtq) { o.etq.textContent = txt; o.txtEtq = txt; }
      o.etq.className = `etq${seleccionadas.has(e.id) ? " sel" : ""}${atasco ? " atasco" : ""}`;
      o.etq.style.transform = `translate(${p.x}px, ${p.y}px) translate(-50%, -100%)`;
      o.etq.hidden = !p.visible || (e.clase === "reparador" && vista === "2d");
      const gl = globos.get(e.id);
      if (gl && ahora < gl.hasta && p.visible) {
        if (o.texto !== gl.nivel + gl.texto) { o.g.textContent = gl.texto; o.g.className = `globo ${gl.nivel}`; o.texto = gl.nivel + gl.texto; }
        o.g.hidden = false; o.g.style.transform = `translate(${p.x}px, ${p.y}px) translate(-50%, calc(-100% - 22px))`;
      } else o.g.hidden = true;
    }
    for (const [id, o] of etiquetas) if (!vivos.has(id)) { o.etq.remove(); o.g.remove(); etiquetas.delete(id); }
  }
  function centrarEn(id) {
    const e = mundo.porId[id] || mundo.enemigos.find(x => x.id === id);
    if (e && V3 && vista === "3d") V3.centrar(e.cx ?? e.x, e.cy ?? e.y);
  }

  // ---------- Retos y mundo en pantalla ----------
  function pintarRetos() {
    const chips = RETOS.map((r, i) => [i, r.titulo]).concat([[IDX_PROPIO, `✎ ${propio.titulo}`]]);
    $("retos").innerHTML = chips.map(([i, t]) => {
      const clave = i === IDX_PROPIO ? "propio" : String(i), hecho = hechos.includes(clave);
      return `<button type="button" class="reto-btn${hecho ? " hecho" : ""}" aria-pressed="${i === retoIdx}" data-i="${i}"><span class="n">${hecho ? "✓" : i === IDX_PROPIO ? "+" : i + 1}</span>${esc(t)}</button>`;
    }).join("");
  }
  $("retos").addEventListener("click", (ev) => { const b = ev.target.closest(".reto-btn"); if (b) elegirReto(+b.dataset.i); });
  function abrirHoja(si) {
    $("hoja-reto").hidden = !si;
    $("b-reto").setAttribute("aria-expanded", si);
  }
  const cerrarHoja = () => { if (!$("hoja-reto").hidden) abrirHoja(false); };
  $("b-reto").addEventListener("click", () => abrirHoja($("hoja-reto").hidden));
  $("hoja-reto").addEventListener("click", (ev) => { if (ev.target.closest("[data-cerrar-hoja]")) abrirHoja(false); });

  function textoInicial(d, id) {
    const lineas = d.inicial[id] || [];
    if (!lineas.length) return `/* Programa de ${id}.\n * Doble clic en el inspector inserta nombres, funciones y valores. */\n\n`;
    return `/* Programa de ${id} · el código de partida está comentado.\n * Quita las // (Ctrl+/ o el botón «//») o escribe el tuyo. */\n` + lineas.map(l => "// " + l).join("\n") + "\n";
  }
  function cargarProgramas() {
    const g = guardado.leer(`prog-${claveReto()}`, null) || {};
    return Object.fromEntries(def.lanzadores.map(l => [l.id, typeof g[l.id] === "string" ? g[l.id] : textoInicial(def, l.id)]));
  }
  let tGuardar = 0;
  function guardarProgramas() {
    clearTimeout(tGuardar);
    const clave = `prog-${claveReto()}`, copia = { ...programas };
    tGuardar = setTimeout(() => guardado.escribir(clave, copia), 300);
  }

  function nuevoMundo() {
    mundo = crearMundo(def, semilla);
    if (V3) V3.construir();
    for (const o of etiquetas.values()) { o.etq.remove(); o.g.remove(); }
    etiquetas.clear(); globos.clear();
    seleccionadas = new Set([...seleccionadas].filter(id => unidadPorId(id)));
    if (!seleccionadas.size) seleccionadas.add(def.lanzadores[0].id);
    seleccion = [...seleccionadas][0];
    if (V3) V3.anillosDe(seleccion);
    historia.clear();
    pintarMaquinas(); pintarInspector();
    metasClave = "";
  }

  function elegirReto(i) {
    clearTimeout(tFicha); cancelarArrastre(); ultimoToque = null;
    cerrarProgramas();
    retoIdx = i; guardado.escribir("reto", i);
    def = defActual();
    intento = telemetria.filter(t => t.reto === i + 1).length;
    if (!semillaFija) semilla = intento + 1;
    programas = cargarProgramas();
    progSel = def.lanzadores[0].id;
    seleccion = def.lanzadores[0].id;
    seleccionadas = new Set([seleccion]);
    edicion = { ids: [], mixto: false };
    lineaCorre = {}; lineaErr = null;
    nuevoMundo();
    $("titulo").textContent = def.titulo;
    $("reto-n").textContent = i === IDX_PROPIO ? "✎" : i + 1;
    $("objetivo-corto").textContent = def.objetivo;
    pintarPaleta();
    $("objetivo-txt").textContent = def.objetivo;
    $("leccion").textContent = def.leccion;
    ocultarBanner(); limpiarConsola(); cerrarAvisos();
    pintarRetos(); pintarProgs(); abrirPrograma(progSel); pintarResumen(); pintarEventosYa(); pintarControles(); pintarEscenario();
  }

  let metasClave = "";
  function pintarHud() {
    const m = mundo, me = def.metas;
    $("reloj").textContent = `t ${m.t.toFixed(1)} s${m.def.niebla ? " · niebla" : ""}`;
    const clave = [m.brechas, m.derribos, m.atascos, m.consumidos, m.reparaciones, m.fin, me.tiempoMax != null && m.t > me.tiempoMax].join("|");
    if (clave === metasClave) return;
    metasClave = clave;
    const cpd = m.derribos ? (coste() / m.derribos).toFixed(1) : "—", rec = records[claveReto()];
    let html = `<span class="meta${m.brechas > me.brechasMax ? " rota" : ""}">brechas <b>${m.brechas}</b> · máx ${me.brechasMax}</span>`;
    html += `<span class="meta${m.total && m.derribos === m.total ? " cumplida" : ""}">derribados <b>${m.derribos}/${m.total}</b>${me.derribosMin != null ? ` · mín ${me.derribosMin}` : ""}</span>`;
    html += `<span class="meta${me.atascosMax != null && m.atascos > me.atascosMax ? " rota" : ""}">atascos <b>${m.atascos}</b>${me.atascosMax != null ? ` · máx ${me.atascosMax}` : ""}</span>`;
    if (me.tiempoMax != null) html += `<span class="meta${m.t > me.tiempoMax ? " rota" : ""}">≤ ${me.tiempoMax} s</span>`;
    html += `<span class="meta optimo" title="El número a optimizar: misiles y reparaciones divididos entre derribos">₵ por derribo <b>${cpd}</b>${rec != null ? ` · récord ${rec.toFixed(1)}` : ""}</span>`;
    $("metas").innerHTML = html;
  }

  function pintarControles() {
    const corriendo = !!ejec;
    const $e = $("b-ejecutar");
    $e.textContent = corriendo ? "■ Detener" : "▶ Ejecutar";
    $e.classList.toggle("primario", !corriendo); $e.classList.toggle("peligro", corriendo);
    const $p = $("b-pausa");
    $p.disabled = !corriendo; $p.textContent = pausa ? "Seguir" : "Pausa";
    $("b-vel").textContent = `${velocidad}×`;
    $("intento-txt").textContent = `Intento ${intento + (corriendo ? 0 : 1)} · ${retoIdx === IDX_PROPIO ? "tu escenario" : `reto ${retoIdx + 1}`}`;
    $("semilla-txt").textContent = corriendo || semillaFija ? semilla : intento + 1;
    $("semilla-fija").checked = semillaFija;
    $codigo.readOnly = corriendo;
  }
  $("b-ejecutar").addEventListener("click", () => ejec ? detener() : ejecutar());
  $("b-pausa").addEventListener("click", () => { pausa = !pausa; pintarControles(); });
  $("b-vel").addEventListener("click", () => { velocidad = velocidad === 1 ? 2 : velocidad === 2 ? 4 : velocidad === 4 ? 8 : 1; pintarControles(); });
  $("b-reiniciar").addEventListener("click", () => {
    if (ejec) terminar("detenido", "reinicio", null);
    nuevoMundo(); lineaCorre = {}; lineaErr = null; marcasSucias = true; ocultarBanner(); cerrarAvisos(); pintarControles();
  });
  $("semilla-fija").addEventListener("change", (ev) => {
    semillaFija = ev.target.checked; guardado.escribir("semillaFija", semillaFija);
    if (semillaFija && !ejec && mundo.fin == null) semilla = intento + 1;
    pintarControles();
  });

  // Vista 3D o plano
  function aplicarVista(v) {
    vista = V3 ? v : "2d";
    guardado.escribir("vista", v);
    $("c3d").hidden = vista !== "3d"; $("c2d").hidden = vista !== "2d";
    $("sin3d").hidden = !!V3;
    $("b-centrar").hidden = vista !== "3d";
    document.querySelectorAll("[data-vista]").forEach(b => b.setAttribute("aria-pressed", b.dataset.vista === vista));
    tamanoCampo();
  }
  document.querySelectorAll("[data-vista]").forEach(b => b.addEventListener("click", () => aplicarVista(b.dataset.vista)));
  $("b-centrar").addEventListener("click", () => V3 && V3.recentrar());
  function tamanoCampo() { const r = $("campo").getBoundingClientRect(); if (V3 && r.width) V3.tamano(r.width, r.height); }
  new ResizeObserver(tamanoCampo).observe($("campo"));

  // ---------- Máquinas e inspector ----------
  function pintarMaquinas() {
    $("maquinas").innerHTML = mundo.maquinas.map(e => `<button type="button" class="maq-chip" data-id="${e.id}" aria-pressed="${seleccionadas.has(e.id)}">${e.id}</button>`).join("")
      + `<span class="fila-bajo" style="align-self:center">En el campo: toca para elegir, mantén presionado para abrir la ficha.</span>`;
  }
  $("maquinas").addEventListener("click", (ev) => { const b = ev.target.closest(".maq-chip"); if (b) seleccionar(b.dataset.id); });
  // El inspector tiene tres estados: cerrado (nada elegido), tira (nombre y signos vitales) y abierto (ficha completa).
  let insEstado = "cerrado";
  const inspectorCompleto = () => $("app").dataset.forma === "movil" && $("app").dataset.inspectorMovil !== "tira";
  function seleccionar(id, opciones = {}) {
    const ids = (Array.isArray(id) ? id : id ? [id] : []).filter(id => unidadPorId(id));
    seleccionadas = new Set(ids);
    seleccion = ids[0] || null;
    if (V3) V3.anillosDe(seleccion);
    document.querySelectorAll(".maq-chip").forEach(b => b.setAttribute("aria-pressed", seleccionadas.has(b.dataset.id)));
    if (!seleccion || opciones.inspeccionar === false) insEstado = "cerrado";
    else if (inspectorCompleto()) insEstado = "abierto";
    else if (insEstado === "cerrado") insEstado = "tira";
    const programables = ids.filter(id => Object.hasOwn(programas, id));
    configurarEdicion(programables.length ? programables : [progSel]);
    pintarInspector();
  }
  $("app").addEventListener("cmg:forma", () => {
    if (seleccion && inspectorCompleto() && insEstado !== "cerrado") ponerInspector("abierto");
  });
  function ponerInspector(estado) { insEstado = seleccion ? estado : "cerrado"; pintarInspector(); }
  const abrirInspector = () => ponerInspector("abierto");

  // Un token es algo que se puede insertar en el código: data-ins es el texto y data-fin el comentario de retorno.
  function tk(tipo, texto, ins, o = {}) {
    if (o.ajeno) return `<button type="button" class="tk tk-${tipo} ajeno" title="${esc(o.ajeno)}" data-ajeno="${esc(o.ajeno)}">${esc(texto)}</button>`;
    return `<button type="button" class="tk tk-${tipo}" draggable="true" data-ins="${esc(ins)}" data-clave="${esc(o.clave || ins)}"${o.fin ? ` data-fin="${esc(o.fin)}"` : ""}${o.vivo ? ` data-vivo="${esc(o.vivo)}"` : ""}>${esc(texto)}</button>`;
  }
  const fila = (...partes) => `<div class="fila-tk">${partes.join(" ")}</div>`;
  const nota = (t) => `<span class="nota">${t}</span>`;
  const grupo = (titulo, ...filas) => `<div class="grupo-tk">${titulo ? `<div class="g">${titulo}</div>` : ""}${filas.join("")}</div>`;
  const tkValor = (v, vivo) => typeof v === "number" ? tk("num", v, String(v), { vivo, clave: vivo }) : typeof v === "boolean" ? tk("kw", v, String(v), { vivo, clave: vivo }) : tk("str", JSON.stringify(v), JSON.stringify(v), { vivo, clave: vivo });

  function estadoDe(e) {
    if (e.clase === "lanzador") {
      if (e.atascado) return ["mal", "atascado"];
      if (e.sinMisiles && e.modo !== "idle") return ["alerta", "sin misiles"];
      if (e.modo === "burst") return ["alerta", "ráfaga"];
      if (e.modo === "regular") return ["activo", "disparando"];
      return ["", "inactivo"];
    }
    if (e.clase === "reparador") return e.estado === "reparar" ? ["activo", "reparando"] : e.estado === "ir" ? ["activo", `va a ${e.objetivo}`] : e.estado === "volver" ? ["", "vuelve"] : ["", "en base"];
    if (e.clase === "vibracion") return [enRango(e).length ? "activo" : "", `${enRango(e).length} en rango`];
    if (e.clase === "deposito") return ["", "suministrando"];
    return ["mal", `vida ${e.hp}/${e.hpMax}`];
  }
  const metricasDe = (e) => {
    if (e.clase === "lanzador") {
      const s = e.st;
      return [["lanzados", s.lanzados], ["impactos", s.impactos], ["precisión", s.lanzados ? `${Math.round(s.impactos / s.lanzados * 100)} %` : "—"], ["derribos", s.derribos], ["atascos", s.atascos], ["en ráfaga", `${s.tRafaga.toFixed(1)} s`], ["fallo máx", `${Math.round(s.fallaMax * 100)} %`], ["₵ gastado", s.consumidos * COSTE.misil]];
    }
    if (e.clase === "vibracion") return [["lecturas", e.st.lecturas]];
    if (e.clase === "reparador") return [["reparaciones", e.st.reparaciones], ["₵ gastado", e.st.reparaciones * COSTE.reparacion]];
    if (e.clase === "deposito") return [["misiles entregados", mundo.consumidos]];
    return null;
  };

  function pintarInspector() {
    const $i = $("inspector");
    const e = seleccion && (mundo.porId[seleccion] || mundo.enemigos.find(x => x.id === seleccion));
    if (!e) insEstado = "cerrado";
    $i.dataset.estado = insEstado;
    if (!e) { $("ins-tira").innerHTML = ""; $("ins-cuerpo").innerHTML = ""; return; }
    const propioProg = e.id === progSel, pre = propioProg ? "" : `${varDe(e.id)}.`;
    let clase, c1 = "", c2 = "", botones = "";
    if (e.clase === "lanzador") {
      clase = "Lanzamisiles";
      const ajeno = propioProg ? null : `Solo desde el programa de ${e.id}`;
      c1 = grupo("Nombre", fila(tk("var", varDe(e.id), varDe(e.id)), nota(`en pantalla ${e.id}${propioProg ? " · en su programa no hace falta escribirlo" : ""}`)))
        + grupo("Contenido", fila(tk("prop", `${pre}missiles`, `${pre}missiles`), `<span class="sep">=</span>`, tkValor(e.misiles, `${e.id}:missiles`), nota(`/ ${def.cargador} misiles`)))
        + grupo("Funciones",
          fila(tk("fn", `${pre}autoTarget(tipo, sensor)`, `${pre}autoTarget(/* tipo de enemigo */, /* sensor */)`, { fin: "// → posición {x, y, z} o null" }), nota("→ posición")),
          fila(tk("fn", `${pre}regularShoot(lugar)`, `${pre}regularShoot(/* lugar */);`, { ajeno }), nota("1 disparo/s")),
          fila(tk("fn", `${pre}burstFire(lugar)`, `${pre}burstFire(/* lugar */);`, { ajeno }), nota("2,2 disparos/s · sube el fallo")),
          fila(tk("fn", `${pre}stopFire()`, `${pre}stopFire();`, { ajeno }), nota("deja de disparar")));
      c2 = grupo("Flujo", fila(nota("entrada:"), "misiles", nota("· salida:"), "lanzamientos"), fila(nota("suministro:"), `${def.suministro} misil/s`))
        + grupo("Propiedades",
          fila(tk("prop", `${pre}fireRate`, `${pre}fireRate`), `<span class="sep">=</span>`, tkValor(cadencia(e.modo), `${e.id}:fireRate`), nota("disparos/s")),
          fila(tk("prop", `${pre}failureRate`, `${pre}failureRate`), `<span class="sep">=</span>`, tkValor(r3(e.falla), `${e.id}:failureRate`), `<span class="barra"><i data-barra="${e.id}" style="width:${Math.round(e.falla * 100)}%"></i></span>`),
          fila(tk("prop", `${pre}mode`, `${pre}mode`), `<span class="sep">=</span>`, tkValor(e.modo, `${e.id}:mode`)),
          fila(tk("prop", `${pre}jammed`, `${pre}jammed`), `<span class="sep">=</span>`, tkValor(e.atascado, `${e.id}:jammed`)),
          fila(tk("prop", `${pre}target`, `${pre}target`), `<span class="sep">=</span>`, `<span class="nota" data-vivo="${e.id}:target">${esc(fmtLugar(e.lugar))}</span>`))
        + grupo("Sensores montados", fila(tk("prop", `${pre}sensors`, `${pre}sensors`), `<span class="sep">=</span>`, tk("str", '"visual"', '"visual"'), tk("str", '"thermal"', '"thermal"')),
          fila(nota(`alcance: cámara ${alcance("visual")} · térmico ${alcance("thermal")}${def.niebla ? " (niebla)" : ""}`)),
          fila(nota("tipos:"), ...Object.keys(TIPOS).map(t => tk("str", `"${t}"`, `"${t}"`))));
      botones = (propioProg ? "" : `<button type="button" class="btn chico" data-accion="programa">Editar el programa de ${esc(e.id)}</button>`);
    } else if (e.clase === "vibracion") {
      clase = "Sensor de vibración (red)";
      c1 = grupo("Nombre", fila(tk("var", varDe(e.id), varDe(e.id)), nota(`en pantalla ${e.id}`)))
        + grupo("Funciones", fila(tk("fn", `${varDe(e.id)}.detect(tipo)`, `${varDe(e.id)}.detect(/* tipo de enemigo */)`, { fin: "// → posición actual o null" }), nota("→ posición, sin predicción")))
        + grupo("Propiedades", fila(tk("prop", `${varDe(e.id)}.count`, `${varDe(e.id)}.count`), `<span class="sep">=</span>`, tkValor(enRango(e).length, `${e.id}:count`), nota("enemigos de suelo en rango")));
      c2 = grupo("", fila(nota("tipo:"), "vibración del suelo"), fila(nota("alcance:"), `${e.alcance} casillas`), fila(nota("ve:"), tk("str", '"crawler"', '"crawler"'), nota("· no ve drones")),
        fila(nota("Da dónde está el enemigo ahora, no dónde estará: el misil llega tarde a lo que se mueve rápido.")));
    } else if (e.clase === "deposito") {
      clase = "Depósito de misiles";
      c1 = grupo("", fila(nota("No tiene nombre en el código en este banco.")));
      c2 = grupo("", fila(nota("salida:"), `${def.suministro} misil/s a cada lanzador`), fila(nota("cargador de cada lanzador:"), `${def.cargador}`));
    } else if (e.clase === "reparador") {
      clase = "Robot reparador";
      c1 = grupo("", fila(nota("Trabaja solo: atiende los atascos en orden de llegada.")));
      c2 = grupo("", fila(nota("velocidad:"), `${REP.vel} casillas/s`), fila(nota("reparación:"), `${REP.tBase} s + ${REP.tPorFallo} s × failureRate del fallo`), fila(nota("cola:"), `<span class="nota" data-vivo="cola">${mundo.colaReparar.join(", ") || "vacía"}</span>`));
    } else {
      const tp = TIPOS[e.tipo];
      clase = `Enemigo · ${tp.nombre}`;
      const ven = [...(tp.frio ? [] : ["thermal"]), "visual"].sort();
      const vib = mundo.sensores[0];
      c1 = grupo("Tipo", fila(tk("str", `"${e.tipo}"`, `"${e.tipo}"`), nota(`autoTarget("${e.tipo}", …) lo apunta`)))
        + grupo("Lo ven", fila(...ven.map(s => tk("str", `"${s}"`, `"${s}"`))), tp.suelo && vib ? fila(tk("fn", `${varDe(vib.id)}.detect("${e.tipo}")`, `${varDe(vib.id)}.detect("${e.tipo}")`)) : "");
      c2 = grupo("", fila(nota("vida:"), `<span data-vivo="${e.id}:hp">${e.hp}/${e.hpMax}</span>`), fila(nota("velocidad:"), `${-e.vx} casillas/s`), fila(nota("altura:"), `${e.z} m${tp.suelo ? " (suelo)" : ""}`),
        fila(nota("posición:"), `<span class="nota" data-vivo="${e.id}:pos">x ${e.x.toFixed(1)} · y ${e.y.toFixed(1)}</span>`), tp.frio ? fila(nota("Motor frío: el térmico no lo ve.")) : "");
    }
    const [cls, txt] = estadoDe(e);
    const m = metricasDe(e);
    const abierto = insEstado === "abierto";
    $("ins-tira").innerHTML = `
      <div class="ins-cab"><div class="nombre"><h2>${esc(e.id)}${seleccionadas.size > 1 ? ` · ${seleccionadas.size} seleccionadas` : ""}</h2><span class="estado ${cls}" data-estado>${esc(txt)}</span><span class="clase">${esc(clase)}</span></div>
        <div class="ins-acc">${V3 && vista === "3d" ? `<button type="button" data-accion="centrar" aria-label="Centrar la cámara en ${esc(e.id)}" data-tip="Centrar la cámara">⌖</button>` : ""}<button type="button" data-accion="${abierto ? "plegar" : "abrir"}" aria-label="${abierto ? "Plegar la ficha" : "Abrir la ficha completa"}" data-tip="${abierto ? "Plegar la ficha" : "Ficha completa"}">${abierto ? "▴" : "▾"}</button><button type="button" data-accion="cerrar" aria-label="Cerrar el inspector" data-tip="Cerrar">×</button></div></div>
      <div class="vitales" id="ins-vitales">${htmlVitales(e)}</div>
      <div class="ins-pista">Mantén presionada una unidad, o toca aquí, para ver su ficha completa.</div>`;
    $("ins-cuerpo").innerHTML = `
      <div class="regla"></div>
      <div class="ins-cols"><div class="ins-col"><h3><span class="placa">Para tu código</span></h3>${c1}</div><div class="ins-col"><h3><span class="placa">Datos</span></h3>${c2}</div></div>
      ${botones ? `<div class="fila-botones">${botones}</div>` : ""}
      ${m ? `<div class="regla"></div><div class="grupo-tk"><h3 class="metricas-tit"><span class="placa">Métricas de este intento</span></h3><div class="metricas" data-metricas>${htmlMetricas(m)}</div></div>` : ""}
      <div class="regla"></div>
      <div class="leyenda-tk"><span class="tk-var">máquina</span><span class="tk-fn">función</span><span class="tk-prop">propiedad</span><span class="tk-num">número</span><span class="tk-str">texto</span>
        <span style="font-family:var(--f-body);font-weight:400">· doble toque: lo inserta en el programa de <b>${esc(progSel)}</b> · también se puede arrastrar</span></div>
      <div class="pista-tk" id="pista-tk"></div>`;
  }

  // Signos vitales: gráficos propios que se leen de un vistazo (cargador, failureRate y su historia, vida).
  const historia = new Map();   // id de lanzador → [[t, failureRate], …] de los últimos 30 s de juego
  const VENTANA = 30;
  function muestrear() {
    for (const l of mundo.lanzadores) {
      const h = historia.get(l.id) || (historia.set(l.id, []), historia.get(l.id));
      if (!h.length || h[h.length - 1][0] !== mundo.t) h.push([mundo.t, l.falla]);
      while (h.length && h[0][0] < mundo.t - VENTANA) h.shift();
    }
  }
  const celdas = (n, total, extra = "") => `<div class="celdas ${extra}">${Array.from({ length: total }, (_, i) => `<i class="${i < n ? "on" : ""}"></i>`).join("")}</div>`;
  const vital = (k, v, cuerpo = "") => `<div class="vital"><div class="k"><span>${k}</span>${v != null ? `<b>${v}</b>` : ""}</div>${cuerpo}</div>`;
  function traza(id) {
    const h = historia.get(id) || [];
    const max = Math.max(0.2, ...h.map(p => p[1])) * 1.1, t1 = mundo.t, t0 = t1 - VENTANA;
    const pts = h.map(([t, f]) => `${((t - t0) / VENTANA * 100).toFixed(2)},${(30 - f / max * 28).toFixed(2)}`);
    const linea = pts.length > 1 ? `<path class="area" d="M${pts[0].split(",")[0]},30L${pts.join("L")}L${pts[pts.length - 1].split(",")[0]},30Z"/><polyline class="linea" points="${pts.join(" ")}"/>` : "";
    return `<svg class="traza" viewBox="0 0 100 30" preserveAspectRatio="none" aria-hidden="true"><line class="base" x1="0" y1="30" x2="100" y2="30"/>${linea}</svg>
      <div class="traza-pie"><span>−${VENTANA} s</span><span>escala 0–${r3(max)}</span><span>ahora</span></div>`;
  }
  function htmlVitales(e) {
    if (e.clase === "lanzador") {
      return vital("Misiles", `${e.misiles}/${def.cargador}`, celdas(e.misiles, def.cargador))
        + vital("failureRate", r3(e.falla), `<div class="medidor"><i style="width:${Math.min(100, Math.round(e.falla * 100))}%"></i></div>`)
        + `<div class="vital" style="grid-column:1/-1"><div class="k"><span>failureRate · últimos ${VENTANA} s</span><b>${esc(e.modo)}</b></div>${traza(e.id)}</div>`;
    }
    if (e.clase === "vibracion") return vital("En rango", enRango(e).length) + vital("Alcance", `${e.alcance} casillas`);
    if (e.clase === "reparador") return vital("Cola", esc(mundo.colaReparar.join(", ") || "vacía")) + vital("Reparaciones", e.st.reparaciones);
    if (e.clase === "deposito") return vital("Entregados", mundo.consumidos) + vital("Suministro", `${def.suministro} misil/s`);
    return vital("Vida", `${e.hp}/${e.hpMax}`, celdas(e.hp, e.hpMax, "vida")) + vital("Altura", `${e.z} m`) + vital("Posición", `x ${e.x.toFixed(1)} · y ${e.y.toFixed(1)}`);
  }
  const htmlMetricas = (m) => m.map(([k, v]) => `<span class="m">${esc(k)} <b>${esc(v)}</b></span>`).join("");
  $("inspector").addEventListener("click", (ev) => {
    const b = ev.target.closest("[data-accion]");
    if (!b) { if (insEstado === "tira" && ev.target.closest(".ins-tira")) abrirInspector(); return; }
    const a = b.dataset.accion;
    if (a === "programa") { abrirPestana("programa"); abrirPrograma(seleccion); }
    else if (a === "centrar") centrarEn(seleccion);
    else if (a === "abrir") abrirInspector();
    else if (a === "plegar") ponerInspector("tira");
    else if (a === "cerrar") seleccionar(null);
  });
  document.addEventListener("keydown", (ev) => {
    if (ev.key !== "Escape") return;
    if (!$("hoja-reto").hidden) abrirHoja(false);
    else if (insEstado === "abierto") ponerInspector("tira");
  });
  function valorVivo(clave) {
    const [id, p] = clave.split(":");
    if (clave === "cola") return mundo.colaReparar.join(", ") || "vacía";
    const e = mundo.porId[id] || mundo.enemigos.find(x => x.id === id);
    if (!e) return null;
    switch (p) {
      case "missiles": return e.misiles;
      case "failureRate": return r3(e.falla);
      case "fireRate": return cadencia(e.modo);
      case "mode": return e.modo;
      case "jammed": return e.atascado;
      case "target": return fmtLugar(e.lugar);
      case "count": return enRango(e).length;
      case "hp": return `${e.hp}/${e.hpMax}`;
      case "pos": return `x ${e.x.toFixed(1)} · y ${e.y.toFixed(1)}`;
    }
    return null;
  }
  function actualizarVivos() {
    const $i = $("inspector");
    muestrear();
    const e = seleccion && (mundo.porId[seleccion] || mundo.enemigos.find(x => x.id === seleccion));
    if ([...seleccionadas].some(id => !unidadPorId(id))) { seleccionar([...seleccionadas].filter(id => unidadPorId(id))); return; }
    if (!e) return;
    for (const el of $i.querySelectorAll("[data-vivo]")) {
      const v = valorVivo(el.dataset.vivo); if (v == null) continue;
      const txt = el.classList.contains("tk-str") ? JSON.stringify(v) : String(v);
      if (el.textContent !== txt) { el.textContent = txt; if (el.dataset.ins != null) el.dataset.ins = txt; }
    }
    const barra = $i.querySelector("[data-barra]"); if (barra) barra.style.width = `${Math.round(e.falla * 100)}%`;
    const est = $i.querySelector("[data-estado]"); if (est) { const [cls, txt] = estadoDe(e); est.className = `estado ${cls}`; est.textContent = txt; }
    const vit = $("ins-vitales"); if (vit) { const h = htmlVitales(e); if (vit.innerHTML !== h) vit.innerHTML = h; }
    const met = $i.querySelector("[data-metricas]"); if (met) { const h = htmlMetricas(metricasDe(e)); if (met.innerHTML !== h) met.innerHTML = h; }
  }

  // Doble clic (o doble toque) inserta; un clic solo arma el token y explica qué insertará.
  let armado = { clave: null, t: 0 };
  document.addEventListener("click", (ev) => {
    const t = ev.target.closest(".tk"); if (!t) return;
    const $p = $("pista-tk");
    if (t.dataset.ajeno) { if ($p) $p.textContent = `${t.dataset.ajeno}. Desde aquí puedes leer sus propiedades.`; return; }
    const ahora = performance.now();
    document.querySelectorAll(".tk.armado").forEach(x => x.classList.remove("armado"));
    if (armado.clave === t.dataset.clave && ahora - armado.t < 550) {
      armado = { clave: null, t: 0 };
      insertarRef(t.dataset.ins, t.dataset.fin);
      insercion.dobleClic++;
      t.classList.add("hecho"); setTimeout(() => t.classList.remove("hecho"), 400);
      if ($p) $p.innerHTML = `Insertado <code>${esc(t.dataset.ins)}</code> en ${esc(progSel)}.`;
    } else {
      armado = { clave: t.dataset.clave, t: ahora };
      t.classList.add("armado");
      if ($p) $p.innerHTML = `Doble clic inserta <code>${esc(t.dataset.ins)}</code> donde está el cursor del programa.`;
    }
  });
  const $editor = $("editor");
  document.addEventListener("dragstart", (ev) => {
    const t = ev.target.closest && ev.target.closest(".tk[data-ins]"); if (!t) return;
    ev.dataTransfer.setData("text/plain", t.dataset.ins); ev.dataTransfer.effectAllowed = "copy";
    $editor.classList.add("soltar");
  });
  document.addEventListener("dragend", () => $editor.classList.remove("soltar"));

  // ---------- Pestañas ----------
  const TABS = ["programa", "registro", "ayuda", "escenario"];
  function abrirPestana(t) {
    for (const x of TABS) { const on = x === t; $(`t-${x}`).setAttribute("aria-selected", on); $(`v-${x}`).hidden = !on; }
    if (t === "programa") medirEditor();
  }
  document.querySelector(".tabs").addEventListener("click", (ev) => { const b = ev.target.closest(".tab"); if (b) abrirPestana(b.id.slice(2)); });

  // Banner
  function mostrarBanner(tipo, titulo, html, stats, acciones) {
    const $b = $("banner");
    $b.className = `banner ${tipo}`;
    $b.innerHTML = `<h2>${esc(titulo)}</h2>${html ? (html.startsWith("<p") ? html : `<p>${html}</p>`) : ""}${stats ? `<p class="stats">${esc(stats)}</p>` : ""}<div class="acciones"></div>`;
    const $a = $b.querySelector(".acciones");
    for (const [txt, cls, fn] of acciones) {
      const b = document.createElement("button"); b.type = "button"; b.className = `btn chico ${cls}`; b.textContent = txt; b.addEventListener("click", fn); $a.appendChild(b);
    }
    $b.hidden = false;
  }
  function ocultarBanner() { $("banner").hidden = true; }

  // ---------- Programas ----------
  function pintarProgs() {
    const varios = def.lanzadores.length > 1;
    $("progs").innerHTML = def.lanzadores.map(l => {
      const p = ejec && ejec.progs.get(l.id);
      const est = lineaErr && lineaErr.id === l.id ? "error" : p ? (p.estado === "corre" ? "corre" : p.estado === "espera" ? "espera" : "") : "";
      return `<button type="button" class="prog-tab" data-id="${l.id}" aria-pressed="${edicion.ids.includes(l.id)}"><span class="punto ${est}"></span>Programa de ${l.id}</button>`;
    }).join("");
    $("b-copiar-prog").hidden = !varios || edicion.ids.length > 1;
    $("b-restaurar").hidden = edicion.ids.length > 1;
  }
  $("progs").addEventListener("click", (ev) => { const b = ev.target.closest(".prog-tab"); if (b) abrirPrograma(b.dataset.id); });
  function abrirPrograma(id) {
    if (!Object.hasOwn(programas, id)) return;
    seleccionar(id);
    configurarEdicion([id], true);
  }
  function configurarEdicion(ids, forzar = false) {
    ids = [...new Set(ids)].filter(id => Object.hasOwn(programas, id));
    if (!ids.length) return;
    if (!forzar && ids.join("|") === edicion.ids.join("|")) return;
    const fuentes = ids.map(id => programas[id]);
    edicion = { ids, mixto: fuentes.some(src => src !== fuentes[0]) };
    progSel = ids[0];
    $codigo.value = edicion.mixto ? "" : fuentes[0];
    $codigo.placeholder = edicion.mixto ? "Escribe el código que quieres añadir o sustituir en las unidades seleccionadas." : "";
    $codigo.setAttribute("aria-label", ids.length > 1 ? `Programa de ${ids.length} lanzadores en JavaScript` : `Programa de ${progSel} en JavaScript`);
    $("acciones-multi").hidden = !edicion.mixto;
    $("multi-estado").textContent = `${ids.length} programas distintos: Add anexa; Replace sustituye.`;
    pintarProgs(); medirEditor(); pintarEdicion(); marcasSucias = true;
  }
  const CLAVE_CONFIRMAR_REPLACE = "cmg-juego-confirmar-replace";
  let confirmarReplace = (() => { try { return localStorage.getItem(CLAVE_CONFIRMAR_REPLACE) !== "false"; } catch { return true; } })();
  function preferirConfirmacionReplace(valor) {
    confirmarReplace = !!valor;
    try { localStorage.setItem(CLAVE_CONFIRMAR_REPLACE, JSON.stringify(confirmarReplace)); } catch { /* preferencia de sesión */ }
  }
  function confirmarReemplazo(ids) {
    if (!confirmarReplace) return Promise.resolve(true);
    const dialogo = $("confirmar-replace"), omitir = $("replace-no-preguntar");
    omitir.checked = false;
    dialogo.returnValue = "cancelar";
    $("replace-texto").textContent = `Se sustituirá por completo el programa de ${ids.join(", ")}. Se perderá el código anterior de estas unidades.`;
    return new Promise(resolve => {
      dialogo.addEventListener("close", () => {
        const aceptado = dialogo.returnValue === "reemplazar";
        if (aceptado && omitir.checked) preferirConfirmacionReplace(false);
        resolve(aceptado);
      }, { once: true });
      dialogo.showModal();
    });
  }
  let aplicandoMulti = false;
  async function aplicarMulti(reemplazar) {
    if (ejec || !edicion.mixto || aplicandoMulti) return;
    const ids = [...edicion.ids], nuevo = $codigo.value, destino = programas;
    aplicandoMulti = true;
    try {
      if (reemplazar && !await confirmarReemplazo(ids)) return;
      if (ejec || programas !== destino) return;
      for (const id of ids) {
        const anterior = programas[id];
        programas[id] = reemplazar ? nuevo : anterior + (anterior && nuevo && !anterior.endsWith("\n") ? "\n" : "") + nuevo;
      }
      guardarProgramas(); configurarEdicion(ids, true); pintarInspector();
    } finally { aplicandoMulti = false; }
  }
  $("b-add").addEventListener("click", () => aplicarMulti(false));
  $("b-replace").addEventListener("click", () => aplicarMulti(true));
  $("b-coordenadas").addEventListener("click", () => { const texto = $("coordenadas").value.trim(); if (texto) insertar(texto); });
  let confirmarCopia = false;
  $("b-copiar-prog").addEventListener("click", (ev) => {
    if (ejec) return;
    if (!confirmarCopia) { confirmarCopia = true; ev.target.textContent = `¿Copiar el de ${progSel} encima de los demás? Toca otra vez`; setTimeout(() => { confirmarCopia = false; ev.target.textContent = "Copiar a los demás lanzadores"; }, 3000); return; }
    confirmarCopia = false; ev.target.textContent = "Copiar a los demás lanzadores";
    for (const l of def.lanzadores) if (l.id !== progSel) programas[l.id] = programas[progSel].split(progSel).join(l.id);
    guardarProgramas();
  });
  let confirmarRestaurar = false;
  $("b-restaurar").addEventListener("click", (ev) => {
    if (ejec) return;
    if (!confirmarRestaurar) { confirmarRestaurar = true; ev.target.textContent = "¿Seguro? Se pierde tu programa. Toca otra vez"; setTimeout(() => { confirmarRestaurar = false; ev.target.textContent = "Restaurar programa inicial"; }, 3000); return; }
    confirmarRestaurar = false; ev.target.textContent = "Restaurar programa inicial";
    programas[progSel] = textoInicial(def, progSel); guardarProgramas(); abrirPrograma(progSel);
  });
  function pintarEdicion() {
    $codigo.readOnly = !!ejec;
    for (const id of ["b-add", "b-replace", "b-coordenadas", "coordenadas"]) $(id).disabled = !!ejec;
    marcasSucias = true;
  }

  // ---------- Editor de texto ----------
  const $codigo = $("codigo"), $gutter = $("gutter"), $banda = $("banda"), $espejo = $("espejo"), $resaltado = $("resaltado");
  let alturas = [];
  function medirEditor() {
    const lineas = $codigo.value.split("\n");
    $espejo.style.width = `${$codigo.clientWidth}px`;
    $espejo.innerHTML = lineas.map(l => `<div>${esc(l) || " "}</div>`).join("");
    alturas = [...$espejo.children].map(d => d.getBoundingClientRect().height);
    $gutter.innerHTML = alturas.map((h, i) => `<div style="height:${h}px">${i + 1}</div>`).join("");
    pintarResaltado();
    pintarBanda();
  }
  function pintarResaltado() {
    if (!colores) return;
    const toks = lexico($codigo.value);
    let html = "";
    toks.forEach((t, i) => { const cls = clasificar(toks, i); html += cls ? `<span class="${cls}">${esc(t[1])}</span>` : esc(t[1]); });
    $resaltado.innerHTML = html + "\n";
    $resaltado.style.width = `${$codigo.clientWidth}px`;
    sincronizarScroll();
  }
  function sincronizarScroll() {
    $resaltado.style.transform = `translate(${-$codigo.scrollLeft}px, ${-$codigo.scrollTop}px)`;
    $gutter.style.transform = `translateY(${-$codigo.scrollTop}px)`;
  }
  const pad = () => parseFloat(getComputedStyle($codigo).paddingTop) || 10;
  function pintarBanda() {
    const corre = !edicion.mixto && lineaCorre[progSel], err = !edicion.mixto && lineaErr && lineaErr.id === progSel ? lineaErr.linea : null;
    const l = err || corre;
    $banda.className = `banda ${l ? (err ? "err" : "corre") : ""}`;
    if (l && alturas.length >= l) {
      const top = alturas.slice(0, l - 1).reduce((a, b) => a + b, 0);
      $banda.style.top = `${pad() + top - $codigo.scrollTop}px`;
      $banda.style.height = `${alturas[l - 1]}px`;
    }
    [...$gutter.children].forEach((d, i) => d.className = i + 1 === err ? "err" : i + 1 === corre ? "corre" : "");
    sincronizarScroll();
  }
  function pintarMarcasYa() { marcasSucias = false; pintarBanda(); pintarProgs(); }
  function irALinea(l) {
    abrirPestana("programa");
    $codigo.focus();
    if (!l) return;
    const lineas = $codigo.value.split("\n");
    let pos = 0; for (let i = 0; i < l - 1 && i < lineas.length; i++) pos += lineas[i].length + 1;
    $codigo.setSelectionRange(pos, pos + (lineas[l - 1] || "").length);
  }
  $codigo.addEventListener("input", () => {
    if (!edicion.mixto) for (const id of edicion.ids) programas[id] = $codigo.value;
    if (lineaErr && lineaErr.id === progSel) { lineaErr = null; marcasSucias = true; }
    medirEditor();
    if (!edicion.mixto) guardarProgramas();
  });
  $codigo.addEventListener("scroll", pintarBanda);
  // Localiza el carácter bajo el puntero con las mismas métricas y ajuste de línea del textarea.
  // Así las comillas y los delimitadores contiguos no dependen de dónde deje el caret el navegador.
  function caracterCodigo(ev) {
    const r = $codigo.getBoundingClientRect(), cs = getComputedStyle($codigo), espejo = document.createElement("div");
    for (const k of ["font", "lineHeight", "padding", "boxSizing", "whiteSpace", "overflowWrap", "wordBreak", "tabSize", "letterSpacing", "fontVariantLigatures"]) espejo.style[k] = cs[k];
    Object.assign(espejo.style, { position: "fixed", left: `${r.left}px`, top: `${r.top}px`, width: `${$codigo.clientWidth}px`, height: `${$codigo.clientHeight}px`, overflow: "hidden", opacity: "0", pointerEvents: "none" });
    const texto = document.createTextNode($codigo.value);
    espejo.append(texto); document.body.append(espejo);
    espejo.scrollTop = $codigo.scrollTop; espejo.scrollLeft = $codigo.scrollLeft;
    const rango = document.createRange();
    let pos = $codigo.selectionStart;
    for (let i = 0; i < texto.length; i++) {
      rango.setStart(texto, i); rango.setEnd(texto, i + 1);
      if ([...rango.getClientRects()].some(c => ev.clientX >= c.left && ev.clientX < c.right && ev.clientY >= c.top && ev.clientY < c.bottom)) { pos = i; break; }
    }
    espejo.remove();
    return pos;
  }
  function rangoCodigo(pos, triple) {
    const src = $codigo.value, pila = [], pares = [];
    let offset = 0;
    for (const [tipo, txt] of lexico(src)) {
      const desde = offset; offset += txt.length;
      if (!triple && tipo === "str" && pos >= desde && pos < offset) return [desde, offset];
      if (tipo !== "p") continue;
      if ("([{".includes(txt)) pila.push({ c: txt, pos: desde });
      else if (")]}".includes(txt)) {
        const abre = pila.pop();
        if (abre && "([{".indexOf(abre.c) === ")]}".indexOf(txt)) pares.push([abre.pos, desde]);
        else pila.length = 0;
      }
    }
    if (triple) {
      // El delimitador pulsado tiene prioridad sobre cualquier par anidado que contenga.
      const par = pares.find(([a, b]) => a === pos || b === pos);
      if (par) return [par[0] + 1, par[1]];
    }
    return null;
  }
  $codigo.addEventListener("mousedown", (ev) => {
    if (ev.button !== 0 || ev.detail < 2) return;
    const rango = rangoCodigo(caracterCodigo(ev), ev.detail >= 3);
    if (!rango) return;
    ev.preventDefault(); $codigo.setSelectionRange(...rango);
  });
  $codigo.addEventListener("dblclick", (ev) => {
    const rango = rangoCodigo(caracterCodigo(ev), false);
    if (rango) { ev.preventDefault(); $codigo.setSelectionRange(...rango); }
  });
  $codigo.addEventListener("drop", () => { insercion.arrastre++; $editor.classList.remove("soltar"); setTimeout(seleccionarHueco, 0); });
  new ResizeObserver(() => medirEditor()).observe($codigo);
  $codigo.addEventListener("keydown", (ev) => {
    if (ev.key === "Tab") { ev.preventDefault(); insertar("  "); }
    else if (ev.key === "/" && (ev.metaKey || ev.ctrlKey)) { ev.preventDefault(); alternarComentario(); }
    else if (ev.key === "Enter" && (ev.metaKey || ev.ctrlKey)) { ev.preventDefault(); ejec ? detener() : ejecutar(); }
    else if (ev.key === "Enter") {
      ev.preventDefault();
      const antes = $codigo.value.slice(0, $codigo.selectionStart);
      const linea = antes.slice(antes.lastIndexOf("\n") + 1);
      insertar("\n" + linea.match(/^\s*/)[0] + (/\{\s*$/.test(linea) ? "  " : ""));
    }
  });
  // Inserta con execCommand para que Ctrl+Z lo deshaga; si el navegador no lo permite, cambia el valor a mano.
  const tactil = matchMedia("(pointer: coarse)");
  const sinTeclado = () => tactil.matches && document.activeElement !== $codigo;
  function insertar(texto, selDesde, selHasta) {
    if ($codigo.readOnly) return false;
    const quieto = sinTeclado();
    if (!quieto) $codigo.focus();
    const a = $codigo.selectionStart;
    let ok = false;
    if (!quieto) { try { ok = document.execCommand("insertText", false, texto); } catch { ok = false; } }
    if (!ok) {
      const v = $codigo.value, b = $codigo.selectionEnd;
      $codigo.value = v.slice(0, a) + texto + v.slice(b);
      $codigo.dispatchEvent(new Event("input"));
    }
    if (selDesde != null) $codigo.setSelectionRange(a + selDesde, a + (selHasta ?? selDesde));
    else $codigo.setSelectionRange(a + texto.length, a + texto.length);
    return true;
  }
  const RE_HUECO = /\/\*\s*(?:tipo de enemigo|tipo|sensor|lugar|condición)\s*\*\//;
  function seleccionarHueco() {
    const v = $codigo.value, p = $codigo.selectionEnd;
    const finLinea = v.indexOf("\n", p) < 0 ? v.length : v.indexOf("\n", p);
    const re = new RegExp(RE_HUECO.source, "g"); re.lastIndex = p;
    const m = re.exec(v);
    if (m && m.index < finLinea) $codigo.setSelectionRange(m.index, m.index + m[0].length);
  }
  function insertarRef(ins, fin) {
    abrirPestana("programa");
    if (ejec) { avisoEditor("Detén el programa para editarlo."); return; }
    const v = $codigo.value, a = $codigo.selectionStart, b = $codigo.selectionEnd;
    const finLinea = v.indexOf("\n", b) < 0 ? v.length : v.indexOf("\n", b);
    let texto = ins;
    if (/^".*"$/.test(texto) && v[a - 1] === '"' && v[b] === '"') texto = texto.slice(1, -1);
    if (fin && !v.slice(b, finLinea).trim()) texto += " " + fin;
    const h = texto.search(RE_HUECO);
    if (h >= 0) { const m = texto.slice(h).match(RE_HUECO)[0]; insertar(texto, h, h + m.length); }
    else { insertar(texto); seleccionarHueco(); }
  }
  function insertarBloque(bloque) {
    const a = $codigo.selectionStart, v = $codigo.value;
    const ini = v.lastIndexOf("\n", a - 1) + 1;
    const fin = v.indexOf("\n", a) === -1 ? v.length : v.indexOf("\n", a);
    const linea = v.slice(ini, fin);
    const sangria = linea.match(/^\s*/)[0] + (/\{\s*$/.test(linea) ? "  " : "");
    const texto = bloque.split("\n").map((l, i) => (i ? sangria : "") + l).join("\n");
    const h = texto.search(RE_HUECO), hueco = texto.indexOf("\n" + sangria + "  \n");
    const pos = h >= 0 ? h : hueco === -1 ? texto.length : hueco + 1 + sangria.length + 2;
    const largo = h >= 0 ? texto.slice(h).match(RE_HUECO)[0].length : 0;
    if (!linea.trim()) { $codigo.setSelectionRange(ini, fin); insertar(sangria + texto, sangria.length + pos, sangria.length + pos + largo); }
    else { $codigo.setSelectionRange(fin, fin); insertar("\n" + sangria + texto, 1 + sangria.length + pos, 1 + sangria.length + pos + largo); }
  }
  // Comenta o descomenta con // las líneas elegidas; el bloque /* … */ de la cabecera no se toca.
  function alternarComentario() {
    if ($codigo.readOnly) return;
    const v = $codigo.value, a = $codigo.selectionStart;
    let b = $codigo.selectionEnd;
    if (b > a && v[b - 1] === "\n") b--;
    const ini = v.lastIndexOf("\n", a - 1) + 1;
    let fin = v.indexOf("\n", b); if (fin < 0) fin = v.length;
    const lineas = v.slice(ini, fin).split("\n");
    const bloque = (l) => /^\s*(\/\*|\*)/.test(l);
    const utiles = lineas.filter(l => l.trim() && !bloque(l));
    if (!utiles.length) return;
    let nuevas;
    if (utiles.every(l => /^\s*\/\//.test(l))) nuevas = lineas.map(l => bloque(l) ? l : l.replace(/^(\s*)\/\/ ?/, "$1"));
    else {
      const min = Math.min(...utiles.map(l => l.match(/^\s*/)[0].length));
      nuevas = lineas.map(l => !l.trim() || bloque(l) ? l : l.slice(0, min) + "// " + l.slice(min));
    }
    const texto = nuevas.join("\n");
    if (!sinTeclado()) $codigo.focus();
    $codigo.setSelectionRange(ini, fin);
    insertar(texto, 0, texto.length);
  }
  function avisoEditor(html) {
    const $a = $("aviso");
    if (!html) { $a.hidden = true; return; }
    $a.innerHTML = html; $a.hidden = false;
    setTimeout(() => { $a.hidden = true; }, 2500);
  }

  // Atajos de escritura
  // "|" separa grupos: control de flujo · órdenes del lanzador · avisos.
  const ATAJOS = [
    { ico: "comentar", t: "Comentar", cod: "// …  (Ctrl+/)", comentar: true },
    "|",
    { ico: "whileTrue", t: "While true", b: "while (true) {\n  \n  await esperar(0.5);\n}" },
    { ico: "mientras", t: "While", b: "while (/* condición */) {\n  \n  await esperar(0.5);\n}" },
    { ico: "siNo", t: "If / else", b: "if (/* condición */) {\n  \n} else {\n  \n}" },
    { ico: "plan", t: "Si no hay (??)", enLinea: " ?? " },
    { ico: "esperar", t: "Esperar", b: "await esperar(0.5);" },
    { ico: "variable", t: "Variable", enLinea: "const pos = " },
    "|",
    { ico: "apuntar", t: "Apuntar", b: "const pos = autoTarget(/* tipo de enemigo */, /* sensor */);" },
    { ico: "disparo", t: "Disparo", b: "regularShoot(/* lugar */);" },
    { ico: "rafaga", t: "Ráfaga", b: "burstFire(/* lugar */);" },
    { ico: "detener", t: "Detener", b: "stopFire();" },
    { ico: "sensor", t: "Sensor de vibración", b: () => `const pos = ${varDe(mundo.sensores[0].id)}.detect(/* tipo de enemigo */);`, si: () => mundo && mundo.sensores.length },
    "|",
    { ico: "aviso", t: "Aviso", b: "console.warn(/* condición */);" },
  ];
  const textoAtajo = (a) => typeof a.b === "function" ? a.b() : a.b;
  function pintarPaleta() {
    const I = window.ICONOS || {};
    $("paleta").innerHTML = ATAJOS.map((a, i) => {
      if (a === "|") return `<span class="sep-pal" aria-hidden="true"></span>`;
      if (a.si && !a.si()) return "";
      const ico = I[a.ico] || { svg: "", c1: "#7FA3FF" };
      const cod = a.cod || (a.enLinea ? a.enLinea.trim() : textoAtajo(a).split("\n")[0] + (textoAtajo(a).includes("\n") ? " …" : ""));
      return `<button type="button" class="atajo" data-i="${i}" aria-label="${esc(a.t)}" data-tip="${esc(a.t)}" data-tip-cod="${esc(cod)}" style="--c1:${ico.c1};${ico.c2 ? `--c2:${ico.c2};` : ""}${ico.c3 ? `--c3:${ico.c3};` : ""}">${ico.svg}</button>`;
    }).join("");
  }
  $("paleta").addEventListener("pointerdown", (ev) => { if (ev.target.closest(".atajo")) ev.preventDefault(); });
  $("paleta").addEventListener("click", (ev) => {
    const b = ev.target.closest(".atajo"); if (!b) return;
    if (ejec) return avisoEditor("Detén el programa para editarlo.");
    const a = ATAJOS[+b.dataset.i];
    insercion.atajo++;
    if (a.comentar) alternarComentario();
    else if (a.enLinea) insertar(a.enLinea);
    else insertarBloque(textoAtajo(a));
  });
  $("b-colores").setAttribute("aria-pressed", colores);
  $editor.classList.toggle("colores", colores);
  $("b-colores").addEventListener("click", () => {
    colores = !colores; guardado.escribir("colores", colores);
    $("b-colores").setAttribute("aria-pressed", colores);
    $editor.classList.toggle("colores", colores); pintarResaltado();
  });
  const TAMANOS = [12, 13, 14, 16, 18];
  function aplicarLetra() { document.querySelector(".app").style.setProperty("--code-size", `${tamLetra}px`); guardado.escribir("letra", tamLetra); medirEditor(); }
  $("b-menos").addEventListener("click", () => { const i = TAMANOS.indexOf(tamLetra); tamLetra = TAMANOS[Math.max(0, (i < 0 ? 2 : i) - 1)]; aplicarLetra(); });
  $("b-mas").addEventListener("click", () => { const i = TAMANOS.indexOf(tamLetra); tamLetra = TAMANOS[Math.min(TAMANOS.length - 1, (i < 0 ? 2 : i) + 1)]; aplicarLetra(); });

  // Cómo se muestra cada console
  const DESTINOS = [["globo", "Globo"], ["pantalla", "Pantalla"], ["consola", "Solo consola"]];
  function pintarRuteo() {
    $("ruteo").innerHTML = NIVELES.map(n => `<code class="tk-fn">console.${n}</code><span class="seg" role="group" aria-label="console.${n}">${DESTINOS.map(([v, t]) => `<button type="button" data-nivel="${n}" data-dest="${v}" aria-pressed="${ruteo[n] === v}">${t}</button>`).join("")}</span>`).join("");
  }
  $("ruteo").addEventListener("click", (ev) => {
    const b = ev.target.closest("[data-dest]"); if (!b) return;
    ruteo[b.dataset.nivel] = b.dataset.dest; guardado.escribir("ruteo", ruteo); pintarRuteo();
  });

  // ---------- Registro y telemetría ----------
  function pintarEventosYa() {
    eventosSucios = false;
    $("eventos").innerHTML = mundo.eventos.slice(-250).map(e =>
      `<tr><td>${e.t.toFixed(2)}</td><td>${esc(e.maquina)}</td><td>${e.linea}</td><td>${esc(e.que)}</td><td class="${e.clase}">${esc(e.resultado)}</td></tr>`).join("")
      || `<tr><td colspan="5" style="color:var(--muted)">Todavía no hay eventos en este intento.</td></tr>`;
  }
  function pintarResumen() {
    const delReto = telemetria.filter(t => t.reto === retoIdx + 1);
    const victorias = delReto.filter(t => t.resultado === "victoria");
    const primera = delReto.findIndex(t => t.resultado === "victoria");
    const rec = records[claveReto()];
    const vistas = ["3d", "2d"].map(v => delReto.filter(t => t.vista === v).length).join(" / ");
    const dobles = delReto.reduce((a, t) => a + ((t.inserciones && t.inserciones.dobleClic) || 0), 0);
    const datos = [["Intentos", delReto.length], ["Cumplidos", victorias.length], ["Récord ₵/derribo", rec != null ? rec.toFixed(1) : "—"], ["Intentos hasta cumplir", primera >= 0 ? primera + 1 : "—"], ["3D / plano", vistas], ["Inserciones con doble clic", dobles]];
    $("resumen").innerHTML = datos.map(([k, v]) => `<div class="dato"><span>${k}</span><b>${v}</b></div>`).join("");
    $("json").value = JSON.stringify(telemetria, null, 2);
  }
  $("b-copiar").addEventListener("click", () => {
    const txt = JSON.stringify(telemetria, null, 2);
    const ok = () => { $("copiado").hidden = false; setTimeout(() => $("copiado").hidden = true, 1600); };
    const planB = () => { const d = $("json").closest("details"); d.open = true; $("json").focus(); $("json").select(); };
    try { navigator.clipboard.writeText(txt).then(ok, planB); } catch { planB(); }
  });
  let confirmarBorrado = false;
  $("b-borrar").addEventListener("click", (ev) => {
    if (!confirmarBorrado) { confirmarBorrado = true; ev.target.textContent = "¿Seguro? Toca otra vez"; setTimeout(() => { confirmarBorrado = false; ev.target.textContent = "Borrar telemetría"; }, 3000); return; }
    confirmarBorrado = false; ev.target.textContent = "Borrar telemetría";
    telemetria = []; guardado.escribir("telemetria", telemetria); intento = 0; pintarResumen(); pintarControles();
  });

  // ---------- Órdenes (ayuda) ----------
  function pintarAyuda() {
    const f = (firma, texto, cls = "") => `<div class="firma ${cls}"><code>${firma}</code><p>${texto}</p></div>`;
    const k = (tipo, t, ins) => tk(tipo, t, ins ?? t);
    $("v-ayuda").innerHTML = `
      <h3>Cómo leer el inspector</h3>
      <ul>
        <li><b>Para tu código</b> (izquierda): el nombre de la máquina, lo que contiene y sus funciones. Es lo que más vas a escribir.</li>
        <li><b>Datos</b> (derecha): entradas, salidas, ritmo y propiedades que puedes leer para decidir, como <span class="tk-prop">failureRate</span>.</li>
        <li><b>Métricas</b> (abajo): cómo le fue a la máquina en este intento. No se usan en el código.</li>
        <li>Doble clic sobre cualquier palabra de color la inserta en el programa abierto. Las funciones llegan con huecos <span class="r">/* tipo de enemigo */</span> ya seleccionados: el siguiente doble clic en un valor los rellena.</li>
      </ul>
      <div class="leyenda-tk"><span class="tk-var">máquina</span><span class="tk-fn">función</span><span class="tk-prop">propiedad</span><span class="tk-num">número</span><span class="tk-str">texto</span></div>
      <h3>Funciones del lanzador</h3>
      <p class="leccion" style="margin:0">En el programa de un lanzador, lo suyo se escribe sin prefijo. Lo de otra máquina lleva su nombre: <span class="r">LAU_02.failureRate</span>. En pantalla los nombres llevan guion (LAU-01); en el código, guion bajo.</p>
      ${f(`${k("fn", "autoTarget")}(tipo, sensor) → posición | null`, `Mira con ese sensor, elige el enemigo de ese tipo más cercano a la base y calcula dónde estará cuando llegue tu próximo misil. Devuelve <span class="r">{x, y, z, id, tipo}</span> o <span class="r">null</span>. No gasta tiempo. Ignora a los que ya tienen misiles suficientes en el aire.`)}
      ${f(`${k("fn", "regularShoot")}(lugar) → "ok" | "sin_objetivo" | "sin_misiles" | "atascado"`, `Dispara 1 misil por segundo a ese lugar hasta que le des otra orden. Con <span class="r">null</span> deja de disparar y devuelve "sin_objetivo".`)}
      ${f(`${k("fn", "burstFire")}(lugar)`, `Igual, pero 2,2 misiles por segundo. Al entrar en ráfaga la probabilidad de fallo sube al 15 % y sigue subiendo 5 puntos por segundo. Fuera de ráfaga baja 6 puntos por segundo hasta el 2 %.`)}
      ${f(`${k("fn", "stopFire")}()`, `Deja de disparar.`)}
      <h3>Propiedades (solo lectura)</h3>
      ${f(`${k("prop", "failureRate")} · ${k("prop", "missiles")} · ${k("prop", "mode")} · ${k("prop", "jammed")} · ${k("prop", "fireRate")} · ${k("prop", "target")} · ${k("prop", "sensors")}`, `Probabilidad de que el próximo disparo falle (0 a 1) · misiles en el cargador · "idle", "regular" o "burst" · si está atascado · disparos por segundo · a dónde apunta · sensores montados.`, "prop")}
      <h3>Red de sensores</h3>
      ${f(`VIB_01.${k("fn", "detect")}(tipo) → posición | null · VIB_01.${k("prop", "count")}`, `El sensor de vibración oye a los enemigos de suelo en su radio, aunque haya niebla. Da dónde están ahora, sin predicción. No oye drones.`, "red")}
      <h3>Del programa</h3>
      ${f(`await ${k("fn", "esperar")}(segundos)`, `Deja pasar tiempo de juego. Mientras tu programa no espera, el reloj está quieto: cada vuelta de un bucle necesita una espera.`)}
      ${f(`console.log · info · warn · error`, `Mensajes de la máquina. En «Cómo se muestra cada console» eliges si salen como globo sobre la máquina, como aviso a pantalla con enlace a ella o solo en la consola.`)}
      <h3>Enemigos</h3>
      <div class="tabla-wrap"><table><thead><tr><th>Tipo</th><th>Vida</th><th>Velocidad</th><th>Altura</th><th>Lo ven</th></tr></thead><tbody>
        ${Object.entries(TIPOS).map(([t, d]) => `<tr><td>${k("str", `"${t}"`)} ${esc(d.nombre)}</td><td>${d.hp}</td><td>${d.vel} c/s</td><td>${d.z} m</td><td>cámara${d.frio ? "" : ", térmico"}${d.suelo ? ", vibración" : ""}</td></tr>`).join("")}
      </tbody></table></div>
      <h3>Reglas</h3>
      <ul>
        <li>El misil vuela a ${MISIL.vel} casillas/s y estalla en el lugar pedido, a su altura: daña lo que esté a ${MISIL.radio} m o menos. Una explosión en el suelo no alcanza a un dron a 2,5 m.</li>
        <li>Cada lanzador recibe ${LAU.suministro} misil/s del depósito hasta llenar su cargador.</li>
        <li>Un fallo atasca el lanzador y pierde el misil. El robot reparador va hasta él y tarda ${REP.tBase} s más ${REP.tPorFallo} s por cada punto de failureRate que tenía al fallar: con 0,04 son ${(REP.tBase + REP.tPorFallo * .04).toFixed(1)} s; con 0,35, ${(REP.tBase + REP.tPorFallo * .35).toFixed(1)} s.</li>
        <li>failureRate es la probabilidad media de fallo por disparo. En promedio falla 1 de cada 1/failureRate disparos, sin rachas extremas.</li>
        <li>Alcance: cámara ${SENSOR.visual.alcance} (niebla ${SENSOR.visual.niebla}), térmico ${SENSOR.thermal.alcance} (niebla ${SENSOR.thermal.niebla}).</li>
        <li>Coste: ₵ ${COSTE.misil} por misil y ₵ ${COSTE.reparacion} por reparación. El número a bajar es el coste por derribo.</li>
        <li>La semilla decide los fallos. Con la misma semilla, el mismo programa da el mismo resultado.</li>
      </ul>
      <h3>Ejemplo</h3>
<pre>while (true) {
  const pos = autoTarget("drone", "visual") ?? autoTarget("crawler", "visual");
  if (failureRate >= 0.25) {
    console.warn(failureRate);
  }
  if (failureRate >= 0.35) {
    regularShoot(pos);
  } else {
    burstFire(pos);
  }
  await esperar(0.4);
}</pre>`;
  }

  // ---------- Escenario propio ----------
  const filaOla = (o, i, dis) => `<div class="ola" data-i="${i}">
      <label class="campo-f">Tipo<select data-k="tipo" ${dis}>${Object.keys(TIPOS).map(t => `<option value="${t}"${o.tipo === t ? " selected" : ""}>${t}</option>`).join("")}</select></label>
      <label class="campo-f">Cuántos<input data-k="n" type="number" min="0" max="40" value="${o.n}" ${dis}></label>
      <label class="campo-f">Desde (s)<input data-k="t" type="number" min="0" step="0.5" value="${o.t}" ${dis}></label>
      <label class="campo-f">Cada (s)<input data-k="cada" type="number" min="0.1" step="0.05" value="${o.cada}" ${dis}></label>
      <label class="campo-f">Carriles (filas 0–17)<input data-k="carriles" value="${o.carriles.join(", ")}" ${dis}></label>
      <label class="campo-f">Vida<input data-k="hp" type="number" min="1" max="9" placeholder="${TIPOS[o.tipo].hp}" value="${o.hp ?? ""}" ${dis}></label>
      <button type="button" class="btn chico quitar" data-quitar="${i}" ${dis}>Quitar</button>
    </div>`;
  // `d` es el escenario que se muestra: el del reto o un borrador que todavía no se guardó.
  function pintarEscenario(d = def) {
    const propioSel = retoIdx === IDX_PROPIO, dis = propioSel ? "" : "disabled";
    const me = d.metas, num = (v) => v == null ? "" : v;
    $("esc-aviso").hidden = propioSel;
    $("esc-aviso").innerHTML = propioSel ? "" : `Este reto es fijo. Puedes copiarlo a «Tu escenario» y cambiar lo que quieras, también el enunciado. <button type="button" class="btn chico" id="esc-copiar-reto">Usar como base de Tu escenario</button>`;
    $("esc-form").innerHTML = `
      <fieldset ${dis}><legend>Enunciado</legend>
        <label class="campo-f">Título<input id="esc-titulo" maxlength="60" value="${esc(d.titulo)}"></label>
        <label class="campo-f">Lo que pides (aparece arriba como objetivo)<textarea id="esc-objetivo">${esc(d.objetivo)}</textarea></label>
        <label class="campo-f">Pista cuando falle<input id="esc-pista" value="${esc(d.pista)}"></label>
      </fieldset>
      <fieldset ${dis}><legend>Metas: lo que tiene que salir</legend>
        <div class="dos">
          <label class="campo-f">Brechas máximas<input id="esc-brechas" type="number" min="0" value="${num(me.brechasMax)}"></label>
          <label class="campo-f">Atascos máximos (vacío = sin límite)<input id="esc-atascos" type="number" min="0" value="${num(me.atascosMax)}"></label>
          <label class="campo-f">Derribos mínimos (vacío = todos los que haga)<input id="esc-derribos" type="number" min="0" value="${num(me.derribosMin)}"></label>
          <label class="campo-f">Tiempo máximo en s (vacío = sin límite)<input id="esc-tiempo" type="number" min="1" value="${num(me.tiempoMax)}"></label>
        </div>
      </fieldset>
      <fieldset ${dis}><legend>Defensa</legend>
        <div class="dos">
          <label class="campo-f">Lanzadores<select id="esc-lanzadores"><option value="1"${d.lanzadores.length === 1 ? " selected" : ""}>1 · LAU-01</option><option value="2"${d.lanzadores.length === 2 ? " selected" : ""}>2 · LAU-01 y LAU-02</option></select></label>
          <label class="campo-f">Robots reparadores<input id="esc-rep" type="number" min="0" max="3" value="${d.reparadores}"></label>
          <label class="campo-f">Cargador (misiles)<input id="esc-cargador" type="number" min="1" max="40" value="${d.cargador}"></label>
          <label class="campo-f">Suministro (misiles/s)<input id="esc-suministro" type="number" min="0" max="5" step="0.1" value="${d.suministro}"></label>
        </div>
        <div style="display:flex;gap:16px;flex-wrap:wrap">
          <label class="check"><input type="checkbox" id="esc-vib"${d.sensores.length ? " checked" : ""}> Sensor de vibración VIB-01</label>
          <label class="check"><input type="checkbox" id="esc-niebla"${d.niebla ? " checked" : ""}> Niebla</label>
        </div>
      </fieldset>
      <fieldset ${dis}><legend>Oleadas (entran por la derecha)</legend>
        <div class="oleadas" id="esc-oleadas">${d.oleadas.map((o, i) => filaOla(o, i, dis)).join("")}</div>
        <div><button type="button" class="btn chico" id="esc-mas" ${dis}>+ Oleada</button></div>
      </fieldset>
      ${propioSel ? `<div style="display:flex;gap:8px;flex-wrap:wrap">
        <button type="button" class="btn primario" id="esc-guardar">Guardar y jugar</button>
        <button type="button" class="btn" id="esc-json-copiar">Copiar JSON</button>
      </div>
      <details class="caja"><summary>Pegar un escenario en JSON</summary><div class="dentro">
        <textarea class="json" id="esc-json" aria-label="Escenario en JSON" placeholder='{"titulo": "…", "oleadas": […]}'></textarea>
        <div><button type="button" class="btn chico" id="esc-json-aplicar">Aplicar</button> <span class="fila-bajo" id="esc-json-msg"></span></div>
      </div></details>` : ""}`;
  }
  function leerEscenario() {
    const v = (id) => $(id).value.trim();
    const n = (id) => v(id) === "" ? null : Number(v(id));
    const oleadas = [...document.querySelectorAll("#esc-oleadas .ola")].map(f => {
      const g = (k) => f.querySelector(`[data-k="${k}"]`).value;
      return { tipo: g("tipo"), n: Number(g("n")), t: Number(g("t")), cada: Number(g("cada")), carriles: g("carriles").split(/[,\s]+/).filter(Boolean).map(Number), ...(g("hp") ? { hp: Number(g("hp")) } : {}) };
    });
    return normalizar({
      titulo: v("esc-titulo") || "Tu escenario", objetivo: v("esc-objetivo"), pista: v("esc-pista"), leccion: "Escenario propio · se edita en la pestaña Escenario.",
      metas: { brechasMax: n("esc-brechas") ?? 0, atascosMax: n("esc-atascos"), derribosMin: n("esc-derribos"), tiempoMax: n("esc-tiempo") },
      lanzadores: POS_LANZADORES[v("esc-lanzadores")] || POS_LANZADORES[1],
      reparadores: n("esc-rep"), cargador: n("esc-cargador"), suministro: n("esc-suministro"), niebla: $("esc-niebla").checked,
      sensores: $("esc-vib").checked ? [{ id: "VIB-01", x: 17, y: 9, alcance: 8 }] : [],
      oleadas, inicial: propio.inicial,
    });
  }
  function guardarPropio(nuevo, jugar) {
    propio = nuevo; guardado.escribir("propio", propio);
    if (jugar || retoIdx === IDX_PROPIO) { elegirReto(IDX_PROPIO); abrirPestana("escenario"); }
    pintarRetos();
  }
  $("v-escenario").addEventListener("click", (ev) => {
    const id = ev.target.id;
    if (ev.target.dataset.quitar != null) { const d = leerEscenario(); d.oleadas.splice(+ev.target.dataset.quitar, 1); pintarEscenario(d); return; }
    if (id === "esc-mas") { const d = leerEscenario(); d.oleadas.push({ tipo: "drone", n: 4, t: 0, cada: 1, carriles: [9] }); pintarEscenario(d); return; }
    if (id === "esc-guardar") { guardarPropio(leerEscenario(), true); abrirPestana("programa"); return; }
    if (id === "esc-copiar-reto") {
      guardado.escribir("prog-propio", programas);
      guardarPropio(normalizar({ ...def, titulo: `${def.titulo} (mío)`, leccion: "Escenario propio · se edita en la pestaña Escenario." }), true);
      return;
    }
    if (id === "esc-json-copiar") {
      const txt = JSON.stringify(leerEscenario(), null, 2);
      try { navigator.clipboard.writeText(txt).then(() => { ev.target.textContent = "Copiado"; setTimeout(() => ev.target.textContent = "Copiar JSON", 1500); }, () => { $("esc-json").value = txt; $("esc-json").closest("details").open = true; $("esc-json").select(); }); }
      catch { $("esc-json").value = txt; }
      return;
    }
    if (id === "esc-json-aplicar") {
      try { guardarPropio(normalizar(JSON.parse($("esc-json").value)), true); }
      catch (e) { $("esc-json-msg").textContent = `No es un JSON válido: ${e.message}`; }
    }
  });

  // ---------- Bucle de juego ----------
  let ultimo = performance.now(), ultVivos = 0;
  function bucle(now) {
    const real = Math.min(0.25, (now - ultimo) / 1000);
    ultimo = now;
    if (mundo.activo && !mundo.fin && !pausa) { if (!algunoCorre()) acum += real * velocidad * turbo; avanzar(); }
    else if (!mundo.activo) acum = 0;
    vigia(now);
    const off = mundo.activo && !pausa && !algunoCorre() ? Math.min(acum, DT) : 0;
    if (vista === "3d" && V3) { V3.actualizar(off, now); V3.render(); } else dibujar2D(off);
    pintarCapa(off, now);
    caducarAvisos(now);
    pintarHud();
    if (now - ultVivos > 200) { ultVivos = now; actualizarVivos(); }
    if (marcasSucias) pintarMarcasYa();
    if (eventosSucios) pintarEventosYa();
    requestAnimationFrame(bucle);
  }

  // ---------- Arranque ----------
  leerColores();
  matchMedia("(prefers-color-scheme: dark)").addEventListener("change", () => { leerColores(); });
  new MutationObserver(() => leerColores()).observe(document.documentElement, { attributes: true, attributeFilter: ["data-theme"] });
  window.__banco = {
    get mundo() { return mundo; }, get def() { return def; }, get programas() { return programas; }, RETOS, instrumentar, lexico, normalizar,
    turbo(n) { turbo = n; }, fijarSemilla(n) { semillaFija = true; semilla = n; }, usarEscenario(d) { guardarPropio(normalizar(d), true); }, elegirReto, ejecutar, abrirPrograma, seleccionar, get seleccionadas() { return [...seleccionadas]; }, get telemetria() { return telemetria; },
  }; // para depurar y probar desde la consola
  window.cmg = { insertar, alternarComentario, medirEditor, get codigo() { return $codigo; }, get ejecutando() { return !!ejec; }, get confirmarReplace() { return confirmarReplace; }, set confirmarReplace(v) { preferirConfirmacionReplace(v); } };
  pintarRuteo();
  pintarAyuda();
  def = defActual();
  aplicarVista(vista);
  aplicarLetra();
  elegirReto(retoIdx);
  document.fonts && document.fonts.ready.then(() => { medirEditor(); });
  requestAnimationFrame(bucle);
})();


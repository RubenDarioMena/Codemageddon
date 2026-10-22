-- Esquema de la base de datos de la partida.
-- Escrito en el subconjunto común de SQLite y PostgreSQL: el destino final es PostgreSQL.
-- {ID} lo sustituye el adaptador (scripts/db/base_datos.gd):
--   SQLite      -> INTEGER PRIMARY KEY
--   PostgreSQL  -> BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY
-- Tiempo: segundos simulados (t), día y hora del reloj del juego. Sin funciones de fecha
-- propias de un motor, para que las consultas del jugador funcionen igual en los dos.

-- Registro (solo se añade): lo que pasa en la fábrica, los robots, los camiones y la ciudad.
CREATE TABLE IF NOT EXISTS eventos (
  id {ID},
  t REAL NOT NULL,
  dia INTEGER NOT NULL,
  hora INTEGER NOT NULL,
  origen TEXT NOT NULL,
  tipo TEXT NOT NULL,
  material TEXT,
  cantidad INTEGER,
  detalle TEXT,
  monto REAL
);

-- Encuestas de la ciudad: una fila por vecino que se queja o protesta.
CREATE TABLE IF NOT EXISTS quejas (
  id {ID},
  t REAL NOT NULL,
  dia INTEGER NOT NULL,
  hora INTEGER NOT NULL,
  distrito TEXT NOT NULL,
  motivo TEXT NOT NULL,
  intensidad REAL NOT NULL
);

-- Proyecciones (foto del estado actual, se reescriben cada segundo). Editarlas no cambia el mundo.
CREATE TABLE IF NOT EXISTS maquinas (
  id TEXT PRIMARY KEY,
  tipo TEXT NOT NULL,
  x INTEGER NOT NULL,
  z INTEGER NOT NULL,
  ruido REAL NOT NULL,
  estado TEXT NOT NULL,
  turno TEXT NOT NULL,
  entrada INTEGER NOT NULL,
  salida INTEGER NOT NULL,
  producidos INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS robots (
  id INTEGER PRIMARY KEY,
  nivel TEXT NOT NULL,
  modelo TEXT NOT NULL,
  estado TEXT NOT NULL,
  carga TEXT,
  cantidad INTEGER NOT NULL,
  x REAL NOT NULL,
  z REAL NOT NULL,
  distancia REAL NOT NULL
);

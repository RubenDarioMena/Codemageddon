class_name Cfg
extends RefCounted
## Constantes de diseño. Todo lo balanceable vive aquí para poder ajustarlo sin tocar la lógica.

const HZ := 20
const MAPA := Vector2i(192, 128)          # metros (1 casilla = 1 m)
const PARCELA := Rect2i(16, 40, 56, 48)   # terreno de la empresa: solo aquí se construye
const CIUDAD := Rect2i(140, 14, 48, 100)
const SEG_POR_HORA := 12.5                # un día simulado = 5 minutos a velocidad 1
const HORA_INICIO := 7.0
const PRESUPUESTO := 1200

## Caminos de los camiones (polilíneas en metros, x/z).
const RUTA_PROVEEDOR := [Vector2(-4, 24), Vector2(12, 24), Vector2(12, 61.5), Vector2(15.4, 61.5)]
const RUTA_VENTA := [Vector2(70.6, 61.5), Vector2(100, 61.5), Vector2(112, 61.5), Vector2(143, 61.5)]
const VEL_CAMION := 7.0
const PLAZO_PEDIDO := 6.0                 # segundos simulados hasta que sale el camión

const MATERIALES := {
	"cobre": {"nombre": "Cobre", "color": Color("ee9550")},
	"silicio": {"nombre": "Silicio", "color": Color("9fb4d8")},
	"lingote": {"nombre": "Lingote", "color": Color("d7793d")},
	"circuito": {"nombre": "Circuito", "color": Color("3fd17a")},
}

## Catálogo del proveedor: material, unidades por pedido y precio del pedido.
const PEDIDOS := {
	"cobre": {"unidades": 10, "precio": 40},
	"silicio": {"unidades": 10, "precio": 80},
}

const MAQUINAS := {
	"recepcion": {
		"nombre": "Recepción", "prefijo": "REC", "tam": Vector2i(4, 3), "costo": 0, "construible": false,
		"modelo": "recepcion", "cap_salida": 60, "ruido": 0.3,
	},
	"fundidora": {
		"nombre": "Fundidora", "prefijo": "FUN", "tam": Vector2i(3, 3), "costo": 300, "tecla": KEY_W,
		"modelo": "fundidora", "recetas": {"lingote": {"entra": {"cobre": 1}, "sale": {"lingote": 1}, "t": 2.5}},
		"cap_entrada": 8, "cap_salida": 8, "ruido": 3.0, "humo": 1.0,
	},
	"ensambladora": {
		"nombre": "Ensambladora", "prefijo": "ENS", "tam": Vector2i(3, 3), "costo": 450, "tecla": KEY_E,
		"modelo": "ensambladora",
		"recetas": {"circuito": {"entra": {"lingote": 2, "silicio": 1}, "sale": {"circuito": 1}, "t": 4.0}},
		"cap_entrada": 8, "cap_salida": 8, "ruido": 2.0, "humo": 0.2,
	},
	"fabrica_robots": {
		"nombre": "Fábrica de robots", "prefijo": "FAB", "tam": Vector2i(4, 4), "costo": 700, "tecla": KEY_A,
		"modelo": "fabrica_robots",
		"recetas": {
			"mula": {"entra": {"circuito": 2, "lingote": 2}, "robot": 0, "t": 10.0},
			"operario": {"entra": {"circuito": 4, "lingote": 2}, "robot": 1, "t": 14.0},
			"explorador": {"entra": {"circuito": 6, "lingote": 4}, "robot": 2, "t": 20.0},
		},
		"cap_entrada": 12, "ruido": 2.5, "humo": 0.3,
	},
	"despacho": {
		"nombre": "Despacho", "prefijo": "DES", "tam": Vector2i(3, 3), "costo": 250, "tecla": KEY_S,
		"modelo": "despacho", "acepta": ["circuito", "lingote"], "cap_entrada": 40, "ruido": 0.5,
	},
	"servidor": {
		"nombre": "Servidor", "prefijo": "SRV", "tam": Vector2i(2, 2), "costo": 250, "tecla": KEY_D,
		"modelo": "servidor", "filas": 10000, "ruido": 0.2,
	},
}
const ORDEN_CONSTRUCCION := ["cinta", "fundidora", "ensambladora", "fabrica_robots", "despacho", "servidor"]
const TECLA_CINTA := KEY_Q
const CINTA_COSTO := 4
const CINTA_VEL := 1.6          # casillas por segundo
const CINTA_HUECO := 0.34       # separación mínima entre objetos
const T_CONSTRUIR := 6.0
const T_CONSTRUIR_CINTA := 0.25
const FILAS_BASE := 4000        # capacidad de registro sin servidores
const PRECIO_BASE_CIRCUITO := 24.0
const PRECIO_LINGOTE := 7.0

const ROBOTS := {
	0: {"nombre": "Mula", "nivel": "T0", "vel": 2.4, "cap": 2, "minar": false, "bucle": false, "auto": false,
		"desc": "Sin chip ni sensores. Ejecuta tu lista de órdenes una sola vez."},
	1: {"nombre": "Operario", "nivel": "T1", "vel": 2.6, "cap": 2, "minar": false, "bucle": true, "auto": false,
		"desc": "Con chip: puede repetir su lista de órdenes en bucle."},
	2: {"nombre": "Explorador", "nivel": "T2", "vel": 2.8, "cap": 3, "minar": true, "bucle": true, "auto": true,
		"desc": "Sensores y pala: busca menas por su cuenta y comprueba si hay espacio antes de entregar."},
}
const T_RECOGER := 0.6
const T_ENTREGAR := 0.5
const T_MINAR := 1.3

## Distritos: exposición relativa a humo y ruido de la fábrica y del tráfico de camiones.
const DISTRITOS := {
	"Norte": {"poblacion": 1800, "humo": 1.0, "ruido": 0.45, "trafico": 0.2, "centro": Vector2(164, 30)},
	"Centro": {"poblacion": 2600, "humo": 0.55, "ruido": 0.6, "trafico": 1.0, "centro": Vector2(164, 64)},
	"Sur": {"poblacion": 1500, "humo": 0.3, "ruido": 0.3, "trafico": 0.25, "centro": Vector2(164, 98)},
}


static func hora_de(t: float) -> float:
	return fmod(HORA_INICIO + t / SEG_POR_HORA, 24.0)


static func dia_de(t: float) -> int:
	return int(floor((HORA_INICIO + t / SEG_POR_HORA) / 24.0)) + 1


static func es_noche(t: float) -> bool:
	var h := hora_de(t)
	return h >= 22.0 or h < 6.0


static func tam_rotado(tam: Vector2i, rot: int) -> Vector2i:
	return tam if rot % 2 == 0 else Vector2i(tam.y, tam.x)


static func dir_vec(d: int) -> Vector2i:
	return [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)][posmod(d, 4)]

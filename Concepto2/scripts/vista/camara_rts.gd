class_name CamaraRTS
extends Node3D
## Cámara ortográfica de RTS. Flechas/WASD y bordes de pantalla desplazan, la rueda hace zoom por
## niveles enteros de píxeles por metro (el pixel art no se deforma), y la rueda PULSADA orbita:
## giro libre mientras arrastras, ajuste a 8 direcciones (45°) al soltar, para que la luz dibujada
## de los sprites no quede en ángulos arbitrarios. Q/E giran 45°.

const NIVELES_PPM := [6, 8, 12, 16, 24, 32, 48]
const BORDE := 6.0

var camara: Camera3D
var objetivo := Vector3(40, 0, 64)
var yaw := 0.0
var yaw_obj := 0.0
var pitch := deg_to_rad(52.0)
var nivel := 4
var orbitando := false
var teclas_activas := true       # el control lo apaga mientras se escribe o en el menú de construcción
var rotacion_con_qe := true
var _size := 0.0
## El desplazamiento por bordes solo actúa con el ratón dentro de la ventana. En la web, con el
## ratón fuera del canvas Godot conserva su última posición (al principio, 0,0: una esquina).
var _raton_dentro := false


func _ready() -> void:
	camara = Camera3D.new()
	camara.projection = Camera3D.PROJECTION_ORTHOGONAL
	camara.near = 1.0
	camara.far = 600.0
	add_child(camara)
	camara.make_current()
	_size = _size_objetivo()
	_aplicar()
	get_window().mouse_exited.connect(func(): _raton_dentro = false)
	get_window().focus_exited.connect(func(): _raton_dentro = false)


func _size_objetivo() -> float:
	return get_viewport().get_visible_rect().size.y / float(NIVELES_PPM[nivel])


func ppm() -> int:
	return NIVELES_PPM[nivel]


func _process(delta: float) -> void:
	var mover := Vector2.ZERO
	if teclas_activas:
		if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
			mover.x -= 1
		if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
			mover.x += 1
		if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
			mover.y -= 1
		if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
			mover.y += 1
	var vp := get_viewport()
	var raton := vp.get_mouse_position()
	var tam := vp.get_visible_rect().size
	if _raton_dentro and Rect2(Vector2.ZERO, tam).has_point(raton) and not orbitando:
		if raton.x < BORDE:
			mover.x -= 1
		elif raton.x > tam.x - BORDE:
			mover.x += 1
		if raton.y < BORDE:
			mover.y -= 1
		elif raton.y > tam.y - BORDE:
			mover.y += 1
	if mover != Vector2.ZERO:
		var vel := _size * 0.9
		var adelante := Vector3(-sin(yaw), 0, -cos(yaw))
		var derecha := Vector3(cos(yaw), 0, -sin(yaw))
		objetivo += (derecha * mover.x - adelante * mover.y).normalized() * vel * delta
	objetivo.x = clamp(objetivo.x, 0.0, Cfg.MAPA.x)
	objetivo.z = clamp(objetivo.z, 0.0, Cfg.MAPA.y)
	if not orbitando:
		yaw = lerp_angle(yaw, yaw_obj, min(1.0, delta * 10.0))
	_size = lerp(_size, _size_objetivo(), min(1.0, delta * 14.0))
	_aplicar()


func _aplicar() -> void:
	var offset := Basis(Vector3.UP, yaw) * Vector3(0, sin(pitch), cos(pitch)) * 150.0
	camara.size = _size
	camara.look_at_from_position(objetivo + offset, objetivo, Vector3.UP)


func _input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		_raton_dentro = true


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		var b := e as InputEventMouseButton
		if b.button_index == MOUSE_BUTTON_MIDDLE:
			orbitando = b.pressed
			if not b.pressed:
				yaw_obj = round(yaw / (PI / 4.0)) * (PI / 4.0)
			get_viewport().set_input_as_handled()
		elif b.pressed and b.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom(1, b.position)
			get_viewport().set_input_as_handled()
		elif b.pressed and b.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(-1, b.position)
			get_viewport().set_input_as_handled()
	elif e is InputEventMouseMotion and orbitando:
		var m := e as InputEventMouseMotion
		yaw -= m.relative.x * 0.008
		yaw_obj = yaw
		pitch = clamp(pitch + m.relative.y * 0.004, deg_to_rad(32.0), deg_to_rad(78.0))
		get_viewport().set_input_as_handled()
	elif e is InputEventKey and e.pressed and not e.echo and teclas_activas and rotacion_con_qe:
		if e.keycode == KEY_Q:
			yaw_obj += PI / 4.0
			get_viewport().set_input_as_handled()
		elif e.keycode == KEY_E:
			yaw_obj -= PI / 4.0
			get_viewport().set_input_as_handled()


## Zoom hacia el punto bajo el cursor, como en los RTS.
func _zoom(paso: int, cursor: Vector2) -> void:
	var antes := rayo_suelo(cursor)
	nivel = clampi(nivel + paso, 0, NIVELES_PPM.size() - 1)
	var previo := _size
	_size = _size_objetivo()
	_aplicar()
	var despues := rayo_suelo(cursor)
	if antes != Vector3.INF and despues != Vector3.INF:
		objetivo += antes - despues
	_size = previo


func centrar(p: Vector3) -> void:
	objetivo = Vector3(p.x, 0, p.z)


## Punto del suelo (y = 0) bajo una posición de pantalla.
func rayo_suelo(pos: Vector2, altura: float = 0.0) -> Vector3:
	var o := camara.project_ray_origin(pos)
	var d := camara.project_ray_normal(pos)
	var hit = Plane(Vector3.UP, altura).intersects_ray(o, d)
	return hit if hit != null else Vector3.INF


func a_pantalla(p: Vector3) -> Vector2:
	return camara.unproject_position(p)

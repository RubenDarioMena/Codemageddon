class_name VistaRobots
extends Node3D
## Robots: volumen 3D (GLB de Blender) con cara-pantalla pixel art y su ID pintado encima.

const NIVEL_COLOR := {0: Color("f29421"), 1: Color("2f7fe0"), 2: Color("59f0ff")}

var sim: Simulacion
var escenas := {}
var nodos := {}            # id -> {raiz, cuerpo_anim, cara: ShaderMaterial, etiqueta, carga: Node3D, anillo}
var tex_caras: ImageTexture
var mat_anillo: StandardMaterial3D
var seleccion: Array = []  # ids seleccionados (lo pone el control)


func construir(p_sim: Simulacion) -> void:
	sim = p_sim
	escenas[0] = load("res://assets/modelos/robot_mula.glb")
	escenas[1] = escenas[0]
	escenas[2] = load("res://assets/modelos/robot_explorador.glb")
	tex_caras = ImageTexture.create_from_image(Pixel.hoja_caras())
	mat_anillo = StandardMaterial3D.new()
	mat_anillo.albedo_color = Color("3fe08a")
	mat_anillo.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_anillo.no_depth_test = true


func actualizar(alfa: float, velocidad: float) -> void:
	var vivos := {}
	for r in sim.robots:
		vivos[r.id] = true
		if not nodos.has(r.id):
			_crear(r)
		var n: Dictionary = nodos[r.id]
		var p := r.prev.lerp(r.pos, alfa)
		n.raiz.position = Vector3(p.x, 0.1 if sim.rejilla.en_parcela(r.celda()) else 0.0, p.y)
		var rumbo := lerp_angle(r.prev_rumbo, r.rumbo, alfa)
		n.raiz.rotation.y = rumbo + PI   # el modelo mira a -Z; rumbo 0 = +Z
		n.cara.set_shader_parameter("cara", _cara(r))
		n.carga.visible = r.cant > 0
		if r.cant > 0:
			for k in n.carga.get_child_count():
				var caja := n.carga.get_child(k) as MeshInstance3D
				caja.visible = k < r.cant
				(caja.material_override as StandardMaterial3D).albedo_color = Cfg.MATERIALES[r.carga].color
		n.anillo.visible = r.id in seleccion
		if n.anim:
			var mueve := r.estado in ["yendo", "minando"] and velocidad > 0.0
			if mueve and not n.anim.is_playing():
				n.anim.play(n.anim_nombre)
			elif not mueve and n.anim.is_playing():
				n.anim.pause()
	for id in nodos.keys():
		if not vivos.has(id):
			nodos[id].raiz.queue_free()
			nodos.erase(id)


func _cara(r: Robot) -> int:
	var nombre := "reposo"
	match r.estado:
		"minando":
			nombre = "minar"
		"esperando":
			nombre = "esperando"
		"sin_ruta", "sin_menas", "sin_fundidora":
			nombre = "error"
		"ocioso":
			nombre = "dormido"
		"yendo":
			nombre = "cargado" if r.cant > 0 else "mover"
	if nombre in ["reposo", "mover"] and fmod(Time.get_ticks_msec() / 1000.0 + r.id * 0.7, 3.2) < 0.15:
		nombre = "parpadeo"
	return Pixel.CARAS.find(nombre)


func _crear(r: Robot) -> void:
	var raiz := Node3D.new()
	add_child(raiz)
	var modelo: Node3D = escenas[r.nivel].instantiate()
	modelo.scale = Vector3.ONE * 1.3   # algo más grandes que a escala real, para leerse como unidades de RTS
	raiz.add_child(modelo)
	var n := {"raiz": raiz, "anim": null, "anim_nombre": "", "cara": null, "etiqueta": null, "carga": null, "anillo": null}
	var mat_cara := ShaderMaterial.new()
	mat_cara.shader = _shader_cara()
	mat_cara.set_shader_parameter("hoja", tex_caras)
	mat_cara.set_shader_parameter("n", Pixel.CARAS.size())
	n.cara = mat_cara
	for c in modelo.find_children("*", "", true, false):
		if c is AnimationPlayer:
			var lista: PackedStringArray = c.get_animation_list()
			if not lista.is_empty():
				n.anim = c
				n.anim_nombre = lista[0]
				c.get_animation(lista[0]).loop_mode = Animation.LOOP_LINEAR
		elif c is MeshInstance3D:
			if c.name == "pantalla":
				_poner_cara(c, mat_cara)
			elif c.name == "cabeza" and r.nivel == 1:
				var m := StandardMaterial3D.new()
				m.albedo_color = NIVEL_COLOR[1]
				c.material_override = m
			elif c.name == "luz_estado":
				var m := StandardMaterial3D.new()
				m.albedo_color = NIVEL_COLOR[r.nivel]
				m.emission_enabled = true
				m.emission = NIVEL_COLOR[r.nivel]
				m.emission_energy_multiplier = 2.0
				c.material_override = m
	# Carga visible sobre la plataforma.
	var carga := Node3D.new()
	carga.position = Vector3(0, 0.52 if r.nivel < 2 else 0.78, 0.12 if r.nivel < 2 else 0.2)
	for k in 3:
		var caja := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.18, 0.14, 0.18)
		caja.mesh = b
		caja.material_override = StandardMaterial3D.new()
		caja.position = Vector3((k - 1) * 0.19, 0.07, 0)
		carga.add_child(caja)
	raiz.add_child(carga)
	n.carga = carga
	# Identificador estable pintado encima: robots[n] en el código.
	var et := Label3D.new()
	et.text = r.nombre()
	et.font_size = 36
	et.pixel_size = 0.01
	et.outline_size = 8
	et.modulate = NIVEL_COLOR[r.nivel].lightened(0.3)
	et.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	et.no_depth_test = true
	et.position = Vector3(0, 1.25, 0)
	raiz.add_child(et)
	n.etiqueta = et
	var anillo := MeshInstance3D.new()
	var toro := TorusMesh.new()
	toro.inner_radius = 0.48
	toro.outer_radius = 0.56
	toro.rings = 24
	anillo.mesh = toro
	anillo.material_override = mat_anillo
	anillo.position.y = 0.03
	anillo.scale.y = 0.15
	raiz.add_child(anillo)
	n.anillo = anillo
	nodos[r.id] = n


func _poner_cara(pantalla: MeshInstance3D, mat: ShaderMaterial) -> void:
	# La caja «pantalla» tiene UV de cubo; encima va un quad con la hoja de caras.
	var aabb := pantalla.get_aabb()
	var q := QuadMesh.new()
	q.size = Vector2(aabb.size.x * 0.92, aabb.size.y * 0.9)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = mat
	mi.position = aabb.get_center() + Vector3(0, 0, -aabb.size.z * 0.5 - 0.003)
	mi.rotation.y = PI
	pantalla.add_child(mi)


static var _shader: Shader


static func _shader_cara() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = """
shader_type spatial;
render_mode unshaded;
uniform sampler2D hoja : filter_nearest, source_color;
uniform int cara = 0;
uniform int n = 8;
void fragment() {
	vec2 uv = vec2((float(cara) + UV.x) / float(n), UV.y);
	vec3 c = texture(hoja, uv).rgb;
	ALBEDO = c;
	EMISSION = c * 1.4;
}
"""
	return _shader

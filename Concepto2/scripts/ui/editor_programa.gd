class_name EditorPrograma
extends PanelContainer
## Editor del programa JavaScript de un robot (tecla J). El código corre en el servicio auxiliar;
## aquí se escribe, se lanza, se ve la línea que está esperando y la consola de `log()`.
## Al poner el cursor sobre "FUN-01" o robots[3], el objeto se resalta en el mundo (GDD §7).

const PLANTILLAS := [
	["Bucle básico (T1)", """// Lleva cobre de la recepción a la fundidora, para siempre.
while (true) {
  await yo.recoger("REC-01", "cobre");
  await yo.entregar("FUN-01");
}
"""],
	["Con condiciones: sin derrames", """// Antes de entregar, mira si cabe. Si no hay cobre, avisa y espera.
while (true) {
  const fun = maquinas["FUN-01"];
  if (fun.espacio("cobre") < yo.capacidad) {
    log("FUN-01 está llena, espero");
    await yo.esperar(2);
    continue;
  }
  const r = await yo.recoger("REC-01", "cobre");
  if (r === "viaje_vacio") {
    log("No queda cobre en REC-01: ¿hiciste un pedido?");
    await yo.esperar(5);
    continue;
  }
  await yo.entregar("FUN-01");
}
"""],
	["Monitoreo con SQL", """// Decide a quién alimentar consultando el registro en PostgreSQL:
// la fundidora que más veces se quedó sin insumo en la última hora simulada.
while (true) {
  const filas = await db.query(`
    SELECT origen, COUNT(*) AS veces
    FROM eventos
    WHERE tipo = 'estado' AND detalle = 'sin_insumo'
      AND origen LIKE 'FUN-%' AND t > $1
    GROUP BY origen
    ORDER BY veces DESC
    LIMIT 1`, [reloj.t - 12.5]);
  const destino = filas.length > 0 ? filas[0].origen : "FUN-01";
  log("Alimento a", destino);
  await yo.recoger("REC-01", "cobre");
  await yo.entregar(destino);
}
"""],
	["Funciones y parámetros", """// Una función reutilizable: el mismo viaje para distintos materiales y destinos.
async function llevar(material, desde, hasta) {
  const r = await yo.recoger(desde, material);
  if (r !== "ok") return r;
  return await yo.entregar(hasta);
}

while (true) {
  await llevar("cobre", "REC-01", "FUN-01");
  await llevar("silicio", "REC-01", "ENS-01");
}
"""],
	["Explorador (T2): minar", """// Rutina del explorador escrita a mano: sensores + pala.
while (true) {
  const mena = yo.buscarMena();
  if (!mena) { log("No quedan menas"); await yo.esperar(10); continue; }
  while (yo.cantidad < yo.capacidad) {
    const r = await yo.minar(mena);
    if (r === "agotada") break;
  }
  const f = yo.buscarMaquina("fundidora", { conEspacio: true });
  if (!f) { await yo.esperar(3); continue; }
  await yo.entregar(f);
}
"""],
]

const API := """[color=#59f0ff]Este robot[/color]  [code]yo[/code] (también [code]robots[N][/code])
[code]await yo.recoger("REC-01", "cobre")[/code]
[code]await yo.entregar("FUN-01")[/code]
[code]await yo.ir(x, z)[/code] · [code]await yo.esperar(seg)[/code] · [code]await yo.reparar(id)[/code]
Las órdenes devuelven [code]"ok"[/code], [code]"viaje_vacio"[/code], [code]"derrame"[/code], [code]"rechazo"[/code], [code]"sin_ruta"[/code]…
[code]yo.carga  yo.cantidad  yo.capacidad  yo.x  yo.z  yo.estado[/code]

[color=#59f0ff]Red de planta[/color]
[code]maquinas["FUN-01"].estado / .entrada.cobre / .salida.lingote[/code]
[code]maquinas["FUN-01"].espacio("cobre")[/code]
[code]reloj.hora  reloj.dia  reloj.t[/code]

[color=#59f0ff]Base de datos (PostgreSQL)[/color]
[code]const filas = await db.query("SELECT ...", [param])[/code]
[code]log("texto", valor)[/code] → consola y tabla eventos (tipo 'log')

[color=#59f0ff]Solo T2 (sensores y pala)[/color]
[code]yo.buscarMena()  yo.buscarMaquina("fundidora", {conEspacio: true})[/code]
[code]await yo.minar(mena)[/code]

[color=#7f95a3]Las órdenes duran tiempo simulado: con el juego en pausa, el await espera.
Un bucle sin await bloquea el robot: el servicio lo detiene a los 3 s.[/color]"""

signal ejecutar(robot: Robot)
signal detener(robot: Robot)
signal resaltar(id: String)

var robot: Robot = null
var titulo: Label
var estado_lbl: Label
var editor: CodeEdit
var consola: RichTextLabel
var b_ejecutar: Button
var b_detener: Button
var plantillas: OptionButton
var _linea_marcada := -1
var _linea_error := -1
var _consola_n := -1
var _t := 0.0


func iniciar() -> void:
	add_theme_stylebox_override("panel", Estilo.caja(Color(0.03, 0.05, 0.08, 0.97), Estilo.AMBAR, 6, 12))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	var cab := HBoxContainer.new()
	v.add_child(cab)
	titulo = Label.new()
	titulo.add_theme_color_override("font_color", Estilo.AMBAR)
	titulo.add_theme_font_size_override("font_size", 16)
	cab.add_child(titulo)
	estado_lbl = Label.new()
	estado_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	estado_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cab.add_child(estado_lbl)
	var cerrar := Estilo.boton("Cerrar", "J")
	cerrar.custom_minimum_size.x = 90
	cerrar.pressed.connect(func(): visible = false)
	cab.add_child(cerrar)

	editor = CodeEdit.new()
	editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	editor.custom_minimum_size = Vector2(0, 220)
	editor.gutters_draw_line_numbers = true
	editor.gutters_draw_executing_lines = true
	editor.indent_automatic = true
	editor.indent_size = 2
	editor.indent_use_spaces = true
	editor.auto_brace_completion_enabled = true
	editor.syntax_highlighter = _resaltador()
	editor.text_changed.connect(_al_editar)
	editor.caret_changed.connect(_al_mover_cursor)
	editor.gui_input.connect(_teclas_editor)
	v.add_child(editor)

	var acciones := HBoxContainer.new()
	v.add_child(acciones)
	b_ejecutar = Estilo.boton("Ejecutar", "Ctrl+Enter")
	b_ejecutar.custom_minimum_size.x = 150
	b_ejecutar.pressed.connect(func(): if robot: ejecutar.emit(robot))
	acciones.add_child(b_ejecutar)
	b_detener = Estilo.boton("Detener")
	b_detener.pressed.connect(func(): if robot: detener.emit(robot))
	acciones.add_child(b_detener)
	var b_clics := Estilo.boton("Desde mis clics", "", "Convierte la lista de órdenes que diste con el ratón en código editable.")
	b_clics.custom_minimum_size.x = 140
	b_clics.pressed.connect(_desde_clics)
	acciones.add_child(b_clics)
	plantillas = OptionButton.new()
	plantillas.focus_mode = Control.FOCUS_NONE
	plantillas.add_item("Plantillas…")
	for p in PLANTILLAS:
		plantillas.add_item(p[0])
	plantillas.item_selected.connect(func(i):
		if i > 0 and robot:
			editor.text = PLANTILLAS[i - 1][1]
			_al_editar()
		plantillas.select(0))
	acciones.add_child(plantillas)

	var pestañas := TabContainer.new()
	pestañas.custom_minimum_size = Vector2(0, 190)
	v.add_child(pestañas)
	consola = RichTextLabel.new()
	consola.name = "Consola"
	consola.bbcode_enabled = true
	consola.scroll_following = true
	pestañas.add_child(consola)
	var api := RichTextLabel.new()
	api.name = "API"
	api.bbcode_enabled = true
	api.text = API
	pestañas.add_child(api)
	visible = false


func mostrar(r: Robot) -> void:
	if r != robot:
		robot = r
		_linea_marcada = -1
		_linea_error = -1
		_consola_n = -1
		if r != null:
			editor.text = r.codigo if r.codigo != "" else _codigo_inicial(r)
			r.codigo = editor.text
	_refrescar()


func _codigo_inicial(r: Robot) -> String:
	if r.nivel == 0:
		return "// %s no tiene chip: no puede ejecutar programas.\n// Fabrica un Operario (T1) en la fábrica de robots.\n" % r.etiqueta()
	return PLANTILLAS[0][1] if r.nivel == 1 else PLANTILLAS[4][1]


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	if _t > 0.1:
		_t = 0.0
		_refrescar()


func _refrescar() -> void:
	if robot == null:
		titulo.text = "PROGRAMA"
		estado_lbl.text = "Selecciona un robot"
		b_ejecutar.disabled = true
		b_detener.disabled = true
		return
	titulo.text = "PROGRAMA · %s" % robot.etiqueta()
	b_ejecutar.disabled = robot.nivel == 0
	b_detener.disabled = not robot.ejecutando
	editor.editable = not robot.ejecutando
	if robot.nivel == 0:
		estado_lbl.text = "Sin chip (T0)"
		estado_lbl.add_theme_color_override("font_color", Estilo.TENUE)
	elif robot.ejecutando:
		estado_lbl.text = "▶ ejecutando · línea %d · %s" % [robot.linea, robot.estado]
		estado_lbl.add_theme_color_override("font_color", Estilo.VERDE)
	else:
		estado_lbl.text = "detenido"
		estado_lbl.add_theme_color_override("font_color", Estilo.TENUE)
	# Línea en espera (la del await en curso) y línea del último error.
	var nueva := robot.linea - 1 if robot.ejecutando else -1
	if nueva != _linea_marcada:
		if _linea_marcada >= 0 and _linea_marcada < editor.get_line_count():
			editor.set_line_as_executing(_linea_marcada, false)
			editor.set_line_background_color(_linea_marcada, Color(0, 0, 0, 0))
		if nueva >= 0 and nueva < editor.get_line_count():
			editor.set_line_as_executing(nueva, true)
			editor.set_line_background_color(nueva, Color(0.1, 0.45, 0.55, 0.35))
		_linea_marcada = nueva
	var err := robot.linea_error - 1
	if err != _linea_error:
		if _linea_error >= 0 and _linea_error < editor.get_line_count() and _linea_error != _linea_marcada:
			editor.set_line_background_color(_linea_error, Color(0, 0, 0, 0))
		if err >= 0 and err < editor.get_line_count():
			editor.set_line_background_color(err, Color(0.8, 0.15, 0.15, 0.35))
		_linea_error = err
	if robot.consola.size() != _consola_n:
		_consola_n = robot.consola.size()
		var t := ""
		for l in robot.consola.slice(-120):
			t += l + "\n"
		consola.text = t


func _al_editar() -> void:
	if robot != null and not robot.ejecutando:
		robot.codigo = editor.text
		robot.linea_error = 0


func _desde_clics() -> void:
	if robot == null or robot.ejecutando:
		return
	var p: Array = robot.programa()
	var lineas: PackedStringArray = []
	for l in p[0]:
		if not l.begins_with("// fin"):
			lineas.append(l)
	editor.text = "\n".join(lineas) + "\n"
	_al_editar()


func _teclas_editor(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_ENTER and (e.ctrl_pressed or e.meta_pressed):
		if robot:
			ejecutar.emit(robot)
		accept_event()


## Si el cursor está sobre un identificador del mundo, se resalta (máquina o robot).
func _al_mover_cursor() -> void:
	var linea := editor.get_line(editor.get_caret_line())
	var col := editor.get_caret_column()
	var rx := RegEx.create_from_string("\"([A-Z]{3}-\\d{2})\"|robots\\[(\\d+)\\]")
	for m in rx.search_all(linea):
		if col >= m.get_start() and col <= m.get_end():
			resaltar.emit(m.get_string(1) if m.get_string(1) != "" else "R" + m.get_string(2))
			return
	resaltar.emit("")


func _resaltador() -> CodeHighlighter:
	var h := CodeHighlighter.new()
	h.number_color = Color("ffb547")
	h.symbol_color = Color("9fb4d8")
	h.function_color = Color("b48ae0")
	h.member_variable_color = Color("c8e6ff")
	for k in ["await", "async", "function", "const", "let", "var", "while", "for", "if", "else", "return", "break",
			"continue", "true", "false", "null", "undefined", "new", "of", "in", "try", "catch", "throw", "typeof"]:
		h.add_keyword_color(k, Color("59f0ff"))
	for k in ["yo", "robots", "maquinas", "db", "log", "reloj", "menas"]:
		h.add_keyword_color(k, Color("ffb547"))
	h.add_color_region("\"", "\"", Color("3fe08a"))
	h.add_color_region("'", "'", Color("3fe08a"))
	h.add_color_region("`", "`", Color("3fe08a"))
	h.add_color_region("//", "", Color("6a8394"), true)
	return h

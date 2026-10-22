class_name ConsolaSQL
extends PanelContainer
## Consola SQL sobre la base de la partida. La idea central: el HUD muestra poco; lo que quieras
## vigilar lo consultas tú y lo fijas como panel. Así el jugador construye su propio monitoreo.

signal fijar(sql: String, titulo: String)

const EJEMPLOS := [
	["Últimos eventos", "SELECT t, origen, tipo, material, cantidad, detalle\nFROM eventos\nORDER BY id DESC\nLIMIT 20;"],
	["Producción por máquina", "SELECT origen, material, SUM(cantidad) AS total\nFROM eventos\nWHERE tipo = 'salida'\nGROUP BY origen, material\nORDER BY total DESC;"],
	["¿Quién está parado?", "SELECT origen, detalle AS estado, COUNT(*) AS veces\nFROM eventos\nWHERE tipo = 'estado' AND detalle IN ('sin_insumo', 'salida_llena')\nGROUP BY origen, detalle\nORDER BY veces DESC;"],
	["Estado actual (proyección)", "SELECT id, tipo, estado, entrada, salida, producidos, turno\nFROM maquinas\nORDER BY id;"],
	["Viajes por robot", "SELECT origen AS robot, tipo, material, COUNT(*) AS veces\nFROM eventos\nWHERE origen LIKE 'R%' AND tipo IN ('recoge', 'entrega', 'viaje_vacio', 'derrame')\nGROUP BY origen, tipo, material\nORDER BY robot;"],
	["Material derramado", "SELECT origen, material, SUM(cantidad) AS unidades, detalle AS casilla\nFROM eventos\nWHERE tipo = 'derrame'\nGROUP BY origen, material, detalle;"],
	["Caja por día", "SELECT dia, SUM(monto) AS neto,\n       SUM(CASE WHEN monto > 0 THEN monto ELSE 0 END) AS ingresos,\n       SUM(CASE WHEN monto < 0 THEN monto ELSE 0 END) AS gastos\nFROM eventos\nWHERE monto IS NOT NULL\nGROUP BY dia;"],
	["Quejas por distrito", "SELECT distrito, motivo, COUNT(*) AS quejas, SUM(intensidad) AS presion\nFROM quejas\nGROUP BY distrito, motivo\nORDER BY presion DESC;"],
	["Ruido nocturno (JOIN)", "SELECT e.origen, m.ruido, COUNT(*) AS producciones_nocturnas\nFROM eventos e\nJOIN maquinas m ON m.id = e.origen\nWHERE e.tipo = 'salida' AND (e.hora >= 22 OR e.hora < 6)\nGROUP BY e.origen, m.ruido\nORDER BY producciones_nocturnas DESC;"],
	["Crear un índice", "-- Con muchos eventos, filtrar por origen se vuelve lento.\n-- Un índice lo acelera (mira los ms antes y después).\nCREATE INDEX IF NOT EXISTS idx_eventos_origen ON eventos (origen);"],
	["Retención manual", "-- El registro tiene capacidad limitada (servidores).\n-- Borra lo que ya no necesitas: por ejemplo, los cambios de estado viejos.\nDELETE FROM eventos WHERE tipo = 'estado' AND dia < (SELECT MAX(dia) FROM eventos);"],
]

var db: BaseDatos
var editor: CodeEdit
var tabla: Tree
var estado: Label
var ejemplos: OptionButton


func iniciar(p_db: BaseDatos) -> void:
	db = p_db
	add_theme_stylebox_override("panel", Estilo.caja(Color(0.03, 0.05, 0.08, 0.97), Estilo.ACENTO, 6, 12))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	var cab := HBoxContainer.new()
	v.add_child(cab)
	var titulo := Label.new()
	titulo.text = "CONSOLA SQL · base de la partida"
	titulo.add_theme_color_override("font_color", Estilo.ACENTO)
	titulo.add_theme_font_size_override("font_size", 16)
	cab.add_child(titulo)
	var esp := Control.new()
	esp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cab.add_child(esp)
	ejemplos = OptionButton.new()
	ejemplos.focus_mode = Control.FOCUS_NONE
	ejemplos.add_item("Ejemplos…")
	for e in EJEMPLOS:
		ejemplos.add_item(e[0])
	ejemplos.item_selected.connect(func(i):
		if i > 0:
			editor.text = EJEMPLOS[i - 1][1]
			ejecutar()
		ejemplos.select(0))
	cab.add_child(ejemplos)
	var cerrar := Estilo.boton("Cerrar", "F2")
	cerrar.pressed.connect(func(): visible = false)
	cab.add_child(cerrar)

	var cuerpo := HSplitContainer.new()
	cuerpo.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(cuerpo)
	var izq := VBoxContainer.new()
	izq.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	izq.size_flags_stretch_ratio = 1.4
	cuerpo.add_child(izq)
	editor = CodeEdit.new()
	editor.custom_minimum_size = Vector2(0, 150)
	editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	editor.gutters_draw_line_numbers = true
	editor.syntax_highlighter = _resaltador()
	editor.text = EJEMPLOS[0][1]
	editor.gui_input.connect(_teclas_editor)
	izq.add_child(editor)
	var acciones := HBoxContainer.new()
	izq.add_child(acciones)
	var b_ej := Estilo.boton("Ejecutar", "Ctrl+Enter")
	b_ej.custom_minimum_size.x = 150
	b_ej.pressed.connect(ejecutar)
	acciones.add_child(b_ej)
	var b_fijar := Estilo.boton("Fijar como panel", "", "El resultado se queda en pantalla y se actualiza cada 2 s.")
	b_fijar.custom_minimum_size.x = 150
	b_fijar.pressed.connect(func(): fijar.emit(editor.text, _titulo(editor.text)))
	acciones.add_child(b_fijar)
	estado = Label.new()
	estado.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	estado.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	acciones.add_child(estado)

	var der := RichTextLabel.new()
	der.bbcode_enabled = true
	der.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	der.custom_minimum_size = Vector2(260, 0)
	der.text = _ayuda_esquema()
	cuerpo.add_child(der)

	tabla = Tree.new()
	tabla.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabla.custom_minimum_size = Vector2(0, 200)
	tabla.hide_root = true
	tabla.column_titles_visible = true
	v.add_child(tabla)
	var pie := Label.new()
	pie.text = db.descripcion()
	pie.add_theme_color_override("font_color", Estilo.TENUE)
	pie.add_theme_font_size_override("font_size", 12)
	pie.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(pie)


func abrir_con(sql: String) -> void:
	visible = true
	editor.text = sql
	ejecutar()
	editor.grab_focus()


func _teclas_editor(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_ENTER and (e.ctrl_pressed or e.meta_pressed):
		ejecutar()
		accept_event()


func ejecutar() -> void:
	var r := db.consultar(editor.text)
	llenar_tabla(tabla, r)
	if not r.ok:
		estado.text = "Error: " + r.error
		estado.add_theme_color_override("font_color", Estilo.ROJO)
	else:
		estado.text = "%d filas · %.2f ms · %s" % [r.filas.size(), r.ms, db.motor.get_slice(" (", 0)]
		estado.add_theme_color_override("font_color", Estilo.VERDE)


static func llenar_tabla(t: Tree, r: Dictionary, max_filas: int = 500) -> void:
	t.clear()
	var cols: Array = r.columnas
	t.columns = max(1, cols.size())
	var raiz := t.create_item()
	if cols.is_empty():
		t.set_column_title(0, "(sin filas)" if r.ok else "error")
		return
	for i in cols.size():
		t.set_column_title(i, str(cols[i]))
		t.set_column_expand(i, true)
	for f in r.filas.slice(0, max_filas):
		var it := t.create_item(raiz)
		for i in cols.size():
			var v = f[cols[i]]
			var s := "NULL"
			if v is float:
				s = str(int(v)) if v == floor(v) and abs(v) < 1e15 else str(snappedf(v, 0.01))
			elif v != null:
				s = str(v)
			it.set_text(i, s)
			if v == null:
				it.set_custom_color(i, Estilo.TENUE)


static func _titulo(sql: String) -> String:
	for l in sql.split("\n"):
		var s := l.strip_edges()
		if s.begins_with("--"):
			return s.trim_prefix("--").strip_edges()
	for e in EJEMPLOS:
		if e[1] == sql:
			return e[0]
	return sql.replace("\n", " ").left(40)


func _resaltador() -> CodeHighlighter:
	var h := CodeHighlighter.new()
	h.number_color = Color("ffb547")
	h.symbol_color = Color("9fb4d8")
	h.function_color = Color("b48ae0")
	h.member_variable_color = Estilo.TEXTO
	for k in ["SELECT", "FROM", "WHERE", "GROUP", "BY", "ORDER", "LIMIT", "AND", "OR", "NOT", "IN", "AS", "JOIN", "ON",
			"LEFT", "INNER", "COUNT", "SUM", "AVG", "MIN", "MAX", "CASE", "WHEN", "THEN", "ELSE", "END", "DESC", "ASC",
			"CREATE", "INDEX", "IF", "EXISTS", "DELETE", "INSERT", "INTO", "VALUES", "UPDATE", "SET", "IS", "NULL",
			"LIKE", "DISTINCT", "HAVING", "TABLE", "VIEW", "DROP", "BETWEEN"]:
		h.add_keyword_color(k, Color("59f0ff"))
		h.add_keyword_color(k.to_lower(), Color("59f0ff"))
	h.add_color_region("'", "'", Color("3fe08a"))
	h.add_color_region("--", "", Color("6a8394"), true)
	return h


func _ayuda_esquema() -> String:
	return """[color=#59f0ff]Tablas[/color]
[b]eventos[/b] (solo se añade)
  id, t, dia, hora, origen, tipo,
  material, cantidad, detalle, monto
  [color=#7f95a3]tipo: salida · entrada · estado · a_cinta
  recoge · entrega · viaje_vacio · derrame
  rechazo · compra · venta · multa …[/color]
[b]quejas[/b]
  id, t, dia, hora, distrito, motivo, intensidad
[b]maquinas[/b] (foto actual)
  id, tipo, x, z, ruido, estado, turno,
  entrada, salida, producidos
[b]robots[/b] (foto actual)
  id, nivel, modelo, estado, carga,
  cantidad, x, z, distancia

[color=#7f95a3]Editar las fotos no cambia el mundo.
Borrar eventos libera capacidad… y
también lo verá el auditor de la ciudad.[/color]"""

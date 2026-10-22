class_name Estilo
extends RefCounted
## Tema de la interfaz: paneles oscuros con acento cian (la «terminal» de la IA de la fábrica).

const FONDO := Color(0.04, 0.07, 0.1, 0.93)
const BORDE := Color("1b6f80")
const ACENTO := Color("59f0ff")
const AMBAR := Color("ffb547")
const ROJO := Color("ff6b6b")
const VERDE := Color("3fe08a")
const TEXTO := Color("d8e6ee")
const TENUE := Color("7f95a3")


static func caja(fondo: Color = FONDO, borde: Color = BORDE, radio: int = 4, margen: int = 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fondo
	s.border_color = borde
	s.set_border_width_all(1)
	s.set_corner_radius_all(radio)
	s.set_content_margin_all(margen)
	return s


static func tema() -> Theme:
	var t := Theme.new()
	t.default_font_size = 14
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Menlo", "SF Mono", "Consolas", "DejaVu Sans Mono", "monospace"])
	t.set_font("normal_font", "RichTextLabel", SystemFont.new())
	t.set_font("mono_font", "RichTextLabel", mono)
	t.set_font("font", "CodeEdit", mono)
	t.set_font("font", "TextEdit", mono)
	t.set_font("font", "Tree", mono)
	t.set_font_size("font_size", "Tree", 13)
	t.set_font_size("font_size", "CodeEdit", 14)
	t.set_stylebox("panel", "PanelContainer", caja())
	t.set_stylebox("panel", "Panel", caja())
	t.set_color("font_color", "Label", TEXTO)
	t.set_color("default_color", "RichTextLabel", TEXTO)
	for estado in ["normal", "hover", "pressed", "disabled", "focus"]:
		var c := Color("0e1c26")
		var b := BORDE
		match estado:
			"hover":
				c = Color("143040")
				b = ACENTO
			"pressed":
				c = Color("1b4a5c")
				b = ACENTO
			"disabled":
				c = Color("0a1218")
				b = Color("26343d")
			"focus":
				c = Color(0, 0, 0, 0)
				b = ACENTO
		t.set_stylebox(estado, "Button", caja(c, b, 3, 6))
	t.set_color("font_color", "Button", TEXTO)
	t.set_color("font_disabled_color", "Button", Color("4e6270"))
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_stylebox("panel", "Tree", caja(Color("071017"), BORDE, 2, 4))
	t.set_color("font_color", "Tree", TEXTO)
	t.set_stylebox("normal", "CodeEdit", caja(Color("071017"), BORDE, 2, 6))
	t.set_stylebox("focus", "CodeEdit", caja(Color("071017"), ACENTO, 2, 6))
	t.set_stylebox("normal", "OptionButton", caja(Color("0e1c26"), BORDE, 3, 6))
	t.set_stylebox("hover", "OptionButton", caja(Color("143040"), ACENTO, 3, 6))
	t.set_stylebox("pressed", "OptionButton", caja(Color("1b4a5c"), ACENTO, 3, 6))
	return t


static func boton(texto: String, tecla: String = "", tooltip: String = "") -> Button:
	var b := Button.new()
	b.text = ("[%s] " % tecla if tecla != "" else "") + texto
	b.tooltip_text = tooltip
	b.focus_mode = Control.FOCUS_NONE
	b.clip_text = true
	b.custom_minimum_size = Vector2(104, 30)
	return b


static func escapar(s: String) -> String:
	return s.replace("[", "[lb]")

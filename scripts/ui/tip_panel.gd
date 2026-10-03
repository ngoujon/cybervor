class_name TipPanel
extends PanelContainer
## Case avec une infobulle riche : titre coloré, ligne d'informations, texte sur plusieurs lignes.
## (Les infobulles par défaut de Godot tiennent sur une seule ligne, illisible pour les longues descriptions.)

const WIDTH := 400.0

var tip_title := ""
var tip_color := Color.WHITE
var tip_sub := ""       # ligne d'informations (type, touche, recharge…), BBCode autorisé
var tip_body := ""      # description, BBCode autorisé


func set_tip(title: String, color: Color, sub: String, body: String) -> void:
	tip_title = title
	tip_color = color
	tip_sub = sub
	tip_body = body
	tooltip_text = title   # non vide : déclenche l'infobulle (texte remplacé par _make_custom_tooltip)


func _make_custom_tooltip(_for_text: String) -> Object:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.custom_minimum_size = Vector2(WIDTH, 0)
	var t := Label.new()
	t.text = tip_title
	t.add_theme_font_override("font", Ui.font_bold)
	t.add_theme_font_size_override("font_size", 22)
	t.add_theme_color_override("font_color", tip_color)
	v.add_child(t)
	for part in [[tip_sub, 16, Ui.C_MUTED], [tip_body, 17, Ui.C_TEXT]]:
		if part[0] == "":
			continue
		var r := RichTextLabel.new()
		r.bbcode_enabled = true
		r.fit_content = true
		r.scroll_active = false
		r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		r.custom_minimum_size = Vector2(WIDTH, 0)
		r.add_theme_font_size_override("normal_font_size", part[1])
		r.add_theme_font_size_override("bold_font_size", part[1])
		r.add_theme_color_override("default_color", part[2])
		r.text = part[0]
		v.add_child(r)
	return v

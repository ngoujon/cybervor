extends Control
## Guide du jeu : règles, commandes, types de dégâts, armes, objets, statistiques, héros, ennemis, modes…
## Ouverture : Ui.open_guide() (menu d'accueil, menu Échap, F3). Recherche insensible aux accents et à la casse,
## avec surlignage des mots trouvés dans le texte.

const HL := "#ffe066"

var _sections: Array = []
var _search: LineEdit
var _list: VBoxContainer
var _title: Label
var _text: RichTextLabel
var _count: Label
var _current := 0
var _buttons: Array = []


func _ready() -> void:
	theme = Ui.theme
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var p := Ui.panel(22)
	Ui.place(p, Control.PRESET_CENTER, Vector2(-780, -480))
	p.custom_minimum_size = Vector2(1560, 960)
	add_child(p)
	var root := Ui.vbox(14)
	p.add_child(root)
	var top := Ui.hbox(16)
	root.add_child(top)
	top.add_child(Ui.label("Guide de Cybervor", 38, Ui.C_BORDER))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	top.add_child(Ui.button("Fermer", _close, 160, 22))

	var body := Ui.hbox(20)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	# colonne de gauche : recherche + sommaire
	var left := Ui.vbox(10)
	left.custom_minimum_size = Vector2(420, 0)
	body.add_child(left)
	_search = LineEdit.new()
	_search.placeholder_text = "Rechercher (ex. : mêlée, armure, critique, Kernel…)"
	_search.clear_button_enabled = true
	_search.add_theme_font_size_override("font_size", 20)
	_search.text_changed.connect(func(_t): _filter())
	_search.text_submitted.connect(func(_t): _open_first_visible())
	left.add_child(_search)
	_count = Ui.label("", 16, Ui.C_MUTED)
	left.add_child(_count)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.follow_focus = true
	left.add_child(sc)
	_list = Ui.vbox(6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_list)
	# colonne de droite : contenu
	var right := Ui.panel(20, Color(0.04, 0.03, 0.1, 0.9))
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	var rv := Ui.vbox(12)
	right.add_child(rv)
	_title = Ui.label("", 30, Ui.C_GOLD)
	rv.add_child(_title)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.selection_enabled = true
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.add_theme_font_size_override("normal_font_size", 20)
	_text.add_theme_font_size_override("bold_font_size", 20)
	_text.add_theme_font_size_override("italics_font_size", 20)
	_text.add_theme_constant_override("line_separation", 4)
	rv.add_child(_text)

	# sommaire regroupé par catégorie (ordre d'écriture conservé dans chaque catégorie)
	var order := ["Bases", "Combat", "Progression", "Modes"]
	for c in order:
		for sec in GuideContent.sections():
			if sec.cat == c:
				_sections.append(sec)
	var cat := ""
	for i in _sections.size():
		var s: Dictionary = _sections[i]
		s["plain"] = _norm(_strip_bbcode(s.title + "\n" + s.text))
		if s.cat != cat:
			cat = s.cat
			var cl := Ui.label(cat.to_upper(), 15, Ui.C_MUTED)
			cl.set_meta("cat", cat)
			_list.add_child(cl)
		var b := Ui.button(s.title, func(): _show(i), 0, 18)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.set_meta("cat", cat)
		_list.add_child(b)
		_buttons.append(b)
	_show(0)
	_filter()
	_search.call_deferred("grab_focus")


func _close() -> void:
	queue_free()


# ------------------------------------------------------------------ recherche
func _words() -> Array:
	var out := []
	for w in _norm(_search.text).split(" ", false):
		if w.length() >= 2:
			out.append(w)
	return out


func _filter() -> void:
	var words := _words()
	var shown := 0
	var visible_cats := {}
	for i in _sections.size():
		var s: Dictionary = _sections[i]
		var ok := true
		var hits := 0
		for w in words:
			var n: int = s.plain.count(w)
			if n == 0:
				ok = false
				break
			hits += n
		var b: Button = _buttons[i]
		b.visible = ok
		b.text = s.title + ("   (%d)" % hits if not words.is_empty() and ok else "")
		if ok:
			shown += 1
			visible_cats[s.cat] = true
	for c in _list.get_children():
		if c is Label:
			c.visible = visible_cats.has(c.get_meta("cat"))
	if words.is_empty():
		_count.text = "%d sections — tapez un mot pour chercher dans tout le guide" % _sections.size()
	elif shown == 0:
		_count.text = "Aucun résultat pour « %s »" % _search.text
	else:
		_count.text = "%d section%s contien%s « %s »" % [shown, "s" if shown > 1 else "", "nent" if shown > 1 else "t", _search.text]
	if not words.is_empty() and shown > 0 and not _buttons[_current].visible:
		_open_first_visible()
	else:
		_show(_current)


func _open_first_visible() -> void:
	for i in _buttons.size():
		if _buttons[i].visible:
			_show(i)
			return


func _show(i: int) -> void:
	_current = i
	var s: Dictionary = _sections[i]
	_title.text = s.title
	for j in _buttons.size():
		_buttons[j].modulate = Color(1, 1, 1) if j != i else Color(1.25, 1.2, 0.7)
	_text.text = _highlight(s.text, _words())
	_text.scroll_to_line(0)
	if not _words().is_empty():
		_scroll_to_first.call_deferred(_words()[0])


func _scroll_to_first(word: String) -> void:
	var idx := _norm(_text.get_parsed_text()).find(word)
	if idx >= 0:
		_text.scroll_to_line(max(0, _text.get_character_line(idx) - 2))


## Surligne les mots cherchés, uniquement dans le texte (jamais à l'intérieur des balises BBCode).
func _highlight(bb: String, words: Array) -> String:
	if words.is_empty():
		return bb
	var out := ""
	var i := 0
	while i < bb.length():
		if bb[i] == "[":
			var j := bb.find("]", i)
			if j < 0:
				j = bb.length() - 1
			out += bb.substr(i, j - i + 1)
			i = j + 1
			continue
		var j2 := bb.find("[", i)
		if j2 < 0:
			j2 = bb.length()
		out += _mark(bb.substr(i, j2 - i), words)
		i = j2
	return out


func _mark(seg: String, words: Array) -> String:
	var n := _norm(seg)   # même longueur que seg : les positions correspondent
	var marks := []
	for w in words:
		var k := n.find(w)
		while k >= 0:
			marks.append([k, k + w.length()])
			k = n.find(w, k + w.length())
	if marks.is_empty():
		return seg
	marks.sort_custom(func(a, b): return a[0] < b[0])
	var out := ""
	var pos := 0
	for m in marks:
		if m[0] < pos:
			continue
		out += seg.substr(pos, m[0] - pos) + "[bgcolor=#5a4a0080][color=%s]%s[/color][/bgcolor]" % [HL, seg.substr(m[0], m[1] - m[0])]
		pos = m[1]
	return out + seg.substr(pos)


static func _strip_bbcode(t: String) -> String:
	var re := RegEx.new()
	re.compile("\\[[^\\]]*\\]")
	return re.sub(t, "", true)


## Minuscules sans accents, caractère par caractère (la longueur ne change pas).
static func _norm(t: String) -> String:
	const FROM := "àâäáãåçéèêëíìîïñóòôöõúùûüýÿœæÀÂÄÁÃÅÇÉÈÊËÍÌÎÏÑÓÒÔÖÕÚÙÛÜÝŒÆ’"
	const TO := "aaaaaaceeeeiiiinooooouuuuyyoeaaaaaaceeeeiiiinooooouuuuyoe'"
	var low := t.to_lower()
	var out := ""
	for ch in low:
		var k := FROM.find(ch)
		out += TO[k] if k >= 0 else ch
	return out

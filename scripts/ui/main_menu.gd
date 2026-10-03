extends Control
## Menu principal.

var _profile_box: VBoxContainer
var _logo: Control


func _ready() -> void:
	Ui.screen_base(self, "res://assets/backgrounds/titre.png", 0.35)
	Audio.play_music("menu")

	var left := Ui.vbox(14)
	Ui.place(left, Control.PRESET_CENTER_LEFT, Vector2(110, -260))
	left.custom_minimum_size = Vector2(420, 0)
	add_child(left)
	# Paramètres et « Quitter le jeu » sont dans la barre en haut à gauche ; profil et personnalisation
	# s'ouvrent en cliquant sur la carte joueur en haut à droite.
	left.add_child(Ui.button("Campagne", _campaign, 420, 34))
	left.add_child(Ui.button("Multijoueur", func(): Game.goto("play"), 420, 34))
	left.add_child(Ui.spacer(6))
	left.add_child(Ui.button("Guide du jeu", func(): Ui.open_guide(), 420))
	left.add_child(Ui.button("Arbres de compétences", func(): Game.goto("skills"), 420))
	left.add_child(Ui.button("Battle Pass", func(): Game.goto("battlepass"), 420))
	left.add_child(Ui.button("Amis & messages", func(): Ui.open_social("amis"), 420))
	left.add_child(Ui.button("Bugs & suggestions", func(): Ui.open_feedback(), 420))
	(left.get_child(0) as Button).call_deferred("grab_focus")

	# Logo
	var logo_tex = Db.tex("res://assets/sprites/ui/logo.png")
	if logo_tex:
		var tr := TextureRect.new()
		tr.texture = logo_tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.custom_minimum_size = Vector2(760, 300)
		Ui.place(tr, Control.PRESET_CENTER_TOP, Vector2(-430, 20))
		_logo = tr
	else:
		var t := Ui.title("CYBERVOR", 120)
		Ui.place(t, Control.PRESET_CENTER_TOP, Vector2(-300 + 260, 60))
		_logo = t
	add_child(_logo)

	# Profil (en haut à droite)
	var pp := Ui.panel(16)
	Ui.place(pp, Control.PRESET_TOP_RIGHT, Vector2(-430, 30))
	pp.custom_minimum_size = Vector2(400, 0)
	pp.mouse_filter = Control.MOUSE_FILTER_STOP
	pp.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	pp.tooltip_text = "Modifier mon profil : pseudo, héros, apparence"
	var normal_style: StyleBox = pp.get_theme_stylebox("panel")
	var hover_style := Ui.box(Color(Ui.C_PANEL_2, 0.97), Ui.C_ACCENT, 3, 14)
	pp.mouse_entered.connect(func(): pp.add_theme_stylebox_override("panel", hover_style))
	pp.mouse_exited.connect(func(): pp.add_theme_stylebox_override("panel", normal_style))
	pp.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			Audio.play("clic")
			Ui.open_profile())
	add_child(pp)
	_profile_box = Ui.vbox(6)
	pp.add_child(_profile_box)
	_refresh_profile()
	Profile.changed.connect(_refresh_profile)

	_build_patchnotes()

	var foot := Ui.label("Cybervor v%s — %s" % [ProjectSettings.get_setting("application/config/version"), "en ligne" if Backend.online else "hors ligne"], 16, Ui.C_MUTED)
	Ui.place(foot, Control.PRESET_BOTTOM_RIGHT, Vector2(-330, -40))
	add_child(foot)

	var tip := Ui.label(_random_tip(), 18, Ui.C_GOLD)
	Ui.place(tip, Control.PRESET_BOTTOM_LEFT, Vector2(110, -60))
	add_child(tip)


## Notes de version, à droite sous la carte profil (data/patchnotes.json, la plus récente en premier).
func _build_patchnotes() -> void:
	var f := FileAccess.open("res://data/patchnotes.json", FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	if not (data is Dictionary) or not (data.get("versions") is Array):
		return
	var panel := Ui.panel(16, Color(Ui.C_PANEL, 0.88))
	Ui.place(panel, Control.PRESET_TOP_RIGHT, Vector2(-430, 260))
	panel.custom_minimum_size = Vector2(400, 600)
	add_child(panel)
	var v := Ui.vbox(8)
	panel.add_child(v)
	v.add_child(Ui.label("Notes de version", 26, Ui.C_BORDER))
	var txt := RichTextLabel.new()
	txt.bbcode_enabled = true
	txt.scroll_active = true
	txt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	txt.custom_minimum_size = Vector2(368, 530)
	txt.add_theme_font_size_override("normal_font_size", 16)
	txt.add_theme_font_size_override("bold_font_size", 19)
	txt.focus_mode = Control.FOCUS_ALL   # défilement possible à la manette
	txt.add_theme_constant_override("paragraph_separation", 5)
	var cur := str(ProjectSettings.get_setting("application/config/version"))
	var out := ""
	for ver in data.versions:
		var head := "[b][color=#%s]v%s[/color][/b]  [color=#%s]%s[/color]" % [Ui.C_GOLD.to_html(false), ver.version,
			Ui.C_MUTED.to_html(false), _fr_date(String(ver.get("date", "")))]
		if String(ver.version) == cur:
			head += "  [color=#%s]· votre version[/color]" % Ui.C_GOOD.to_html(false)
		out += head + "\n"
		if ver.get("title", "") != "":
			out += "[b]%s[/b]\n" % ver.title
		for n in ver.get("notes", []):
			out += "[color=#%s]•[/color] %s\n" % [Ui.C_ACCENT.to_html(false), n]
		out += "\n"
	txt.text = out.strip_edges()
	v.add_child(txt)


static func _fr_date(iso: String) -> String:
	var p := iso.split("-")
	if p.size() != 3:
		return iso
	var mois := ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre", "octobre", "novembre", "décembre"]
	return "%d %s %s" % [int(p[2]), mois[clampi(int(p[1]) - 1, 0, 11)], p[0]]


func _process(_d: float) -> void:
	if _logo:
		_logo.rotation = sin(Time.get_ticks_msec() / 900.0) * 0.015
		_logo.pivot_offset = _logo.size / 2


func _refresh_profile() -> void:
	if not is_instance_valid(_profile_box):
		return
	for c in _profile_box.get_children():
		c.queue_free()
	var d = Profile.data
	var top := Ui.hbox(12)
	top.add_child(Ui.icon(Db.characters.get(d.character, {}).get("sprite", ""), 72))
	var info := Ui.vbox(2)
	info.add_child(Ui.label(Settings.player_name, 26, Ui.C_BORDER))
	var title_id: String = d.cosmetics.title
	if title_id != "":
		info.add_child(Ui.label("« %s »" % Db.battlepass.titles.get(title_id, ""), 16, Ui.C_GOLD))
	info.add_child(Ui.label("Niveau %d" % int(d.level), 20))
	top.add_child(info)
	_profile_box.add_child(top)
	var xpb := ProgressBar.new()
	xpb.max_value = Profile.xp_for_level(d.level)
	xpb.value = d.xp
	xpb.show_percentage = false
	xpb.custom_minimum_size = Vector2(0, 12)
	_profile_box.add_child(xpb)
	var cur := Ui.hbox(8)
	cur.add_child(Ui.icon("res://assets/sprites/ui/puces.png", 30))
	cur.add_child(Ui.label(str(int(d.puces)), 20, Ui.C_GOLD))
	cur.add_child(Ui.spacer(0, 20))
	cur.add_child(Ui.icon("res://assets/sprites/ui/neons.png", 30))
	cur.add_child(Ui.label(str(int(d.neons)), 20, Ui.C_ACCENT))
	cur.add_child(Ui.spacer(0, 20))
	cur.add_child(Ui.icon("res://assets/sprites/ui/point_competence.png", 30))
	cur.add_child(Ui.label(str(Profile.available_points()), 20, Ui.C_BORDER))
	_profile_box.add_child(cur)
	_profile_box.add_child(Ui.label("Battle Pass : palier %d / %d" % [Profile.bp_tier(), Db.battlepass.tiers.size()], 18, Ui.C_MUTED))
	_profile_box.add_child(Ui.label("✎ Cliquez pour modifier votre profil", 15, Ui.C_ACCENT, HORIZONTAL_ALIGNMENT_RIGHT))
	for c in _profile_box.get_children():
		_ignore_mouse(c)


func _ignore_mouse(n: Node) -> void:
	if n is Control:
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in n.get_children():
		_ignore_mouse(c)


## Campagne : solo, directement sur la carte (la coop en ligne passe par Multijoueur).
func _campaign() -> void:
	Game.goto("campaign")


func _random_tip() -> String:
	var tips = [
		"Astuce : vos armes tirent toutes seules. Concentrez-vous sur l'esquive (et sur votre dignité).",
		"Astuce : la récolte vous donne des données bonus à la fin de chaque vague.",
		"Astuce : deux armes identiques de même rang fusionnent en boutique pour monter de rang.",
		"Astuce : Mamie RAM ne se trompe jamais. Sauf sur les dates. Et les noms. Et la météo.",
		"Astuce : en coop, l'XP est partagée. L'amitié aussi, en théorie.",
		"Astuce : chaque niveau de compte rapporte un point de compétence. Le battle pass, lui, c'est pour la classe.",
		"Astuce : la chance augmente la rareté des améliorations et des objets en boutique.",
	]
	return tips[randi() % tips.size()]

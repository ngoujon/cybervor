extends Control
## Fenêtre « Mon profil », ouverte en cliquant sur la carte joueur (en haut à droite du menu principal).
## Onglet Profil : pseudo (unique en ligne), héros, code ami, statistiques. Onglet Personnalisation : cosmétiques.

const Cosmetics := preload("res://scripts/ui/cosmetics.gd")

var start_tab := 0
var _tabs: TabContainer
var _name_edit: LineEdit
var _name_status: Label
var _hero_box: HFlowContainer
var _avatar: TextureRect
var _hat: TextureRect
var _avatar_name: Label


func _ready() -> void:
	theme = Ui.theme
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var p := Ui.panel(24)
	Ui.place(p, Control.PRESET_CENTER, Vector2(-760, -460))
	p.custom_minimum_size = Vector2(1520, 920)
	add_child(p)
	var root := Ui.vbox(12)
	p.add_child(root)
	var head := Ui.hbox(12)
	root.add_child(head)
	head.add_child(Ui.title("Mon profil", 46))
	head.add_child(Ui.spacer())
	head.add_child(Ui.button("Fermer (Échap)", queue_free, 0, 20))
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_theme_font_size_override("font_size", 22)
	root.add_child(_tabs)
	_tabs.add_child(_build_profile())
	var cos := Cosmetics.new()
	cos.embedded = true
	_tabs.add_child(cos)
	_tabs.current_tab = start_tab
	_tabs.tab_changed.connect(func(_i): _refresh_avatar())
	_refresh_avatar()


func _build_profile() -> Control:
	var h := Ui.hbox(24)
	h.name = "Profil"
	# --- avatar
	var ap := Ui.panel(20, Color(Ui.C_PANEL_2, 0.7))
	ap.custom_minimum_size = Vector2(420, 0)
	h.add_child(ap)
	var av := Ui.vbox(8)
	av.alignment = BoxContainer.ALIGNMENT_CENTER
	ap.add_child(av)
	var stage := Control.new()
	stage.custom_minimum_size = Vector2(380, 380)
	av.add_child(stage)
	_avatar = Ui.icon("", 280)
	_avatar.position = Vector2(50, 90)
	_avatar.size = Vector2(280, 280)
	stage.add_child(_avatar)
	_hat = Ui.icon("", 140)
	_hat.position = Vector2(120, 10)
	_hat.size = Vector2(140, 140)
	stage.add_child(_hat)
	_avatar_name = Ui.label("", 30, Ui.C_BORDER, HORIZONTAL_ALIGNMENT_CENTER)
	av.add_child(_avatar_name)
	av.add_child(Ui.button("Changer d'apparence →", func(): _tabs.current_tab = 1, 0, 18))

	# --- informations
	var right := Ui.vbox(14)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(right)
	right.add_child(Ui.label("Pseudo", 24, Ui.C_GOLD))
	var nr := Ui.hbox(10)
	right.add_child(nr)
	_name_edit = LineEdit.new()
	_name_edit.text = Settings.player_name
	_name_edit.max_length = 20
	_name_edit.custom_minimum_size = Vector2(420, 0)
	_name_edit.add_theme_font_size_override("font_size", 24)
	_name_edit.text_submitted.connect(func(_t): _save_name())
	nr.add_child(_name_edit)
	nr.add_child(Ui.button("Enregistrer", _save_name, 0, 20))
	_name_status = Ui.label("3 à 20 caractères. Votre pseudo est unique : vos amis peuvent vous ajouter avec." if Backend.online
		else "Hors ligne : le pseudo sera vérifié (unicité) à la prochaine connexion.", 16, Ui.C_MUTED)
	right.add_child(_name_status)
	if Backend.online and Backend.my_code != "":
		var cr := Ui.hbox(10)
		cr.add_child(Ui.label("Code ami : " + Backend.my_code, 20, Ui.C_BORDER))
		cr.add_child(Ui.button("Copier", func():
			DisplayServer.clipboard_set(Backend.my_code)
			Ui.toast("Code ami copié !"), 0, 16))
		right.add_child(cr)

	_build_cloud(right)

	right.add_child(Ui.label("Héros", 24, Ui.C_GOLD))
	_hero_box = HFlowContainer.new()
	_hero_box.add_theme_constant_override("h_separation", 10)
	_hero_box.add_theme_constant_override("v_separation", 10)
	right.add_child(_hero_box)
	_fill_heroes()

	right.add_child(Ui.label("Statistiques", 24, Ui.C_GOLD))
	var d = Profile.data
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 30)
	grid.add_theme_constant_override("v_separation", 6)
	right.add_child(grid)
	var stats := [
		["Niveau de compte", str(int(d.level))],
		["Points de compétence", str(Profile.available_points())],
		["Puces", str(int(d.puces))],
		["Néons", str(int(d.neons))],
		["Battle pass", "palier %d / %d" % [Profile.bp_tier(), Db.battlepass.tiers.size()]],
		["Missions réussies", "%d / %d" % [d.campaign.completed.size(), _mission_count()]],
		["Record en survie", "vague %d" % int(d.campaign.best_endless)],
		["Titre", Db.battlepass.titles.get(d.cosmetics.title, "—") if d.cosmetics.title != "" else "—"],
	]
	for s in stats:
		grid.add_child(Ui.label(s[0], 18, Ui.C_MUTED))
		grid.add_child(Ui.label(s[1], 20))
	return h


# ------------------------------------------------------------------ sauvegarde cloud
var _cloud_label: Label


func _build_cloud(parent: Control) -> void:
	if not Backend.enabled():
		return
	var row := Ui.hbox(10)
	parent.add_child(row)
	row.add_child(Ui.label("Sauvegarde cloud", 24, Ui.C_GOLD))
	_cloud_label = Ui.label("", 18)
	row.add_child(_cloud_label)
	_cloud_status(Backend.cloud_state)
	Backend.cloud_status_changed.connect(_cloud_status)
	var cr := Ui.hbox(10)
	parent.add_child(cr)
	var code_l := Ui.label("Code de sauvegarde : ••••-••••-••••", 18, Ui.C_MUTED)
	cr.add_child(code_l)
	var show := Ui.button("Afficher", Callable(), 0, 16)
	show.pressed.connect(func():
		code_l.text = "Code de sauvegarde : " + Backend.save_code()
		show.visible = false)
	cr.add_child(show)
	cr.add_child(Ui.button("Copier", func():
		DisplayServer.clipboard_set(Backend.save_code())
		Ui.toast("Code de sauvegarde copié : gardez-le secret !"), 0, 16))
	var rr := Ui.hbox(10)
	parent.add_child(rr)
	var edit := LineEdit.new()
	edit.placeholder_text = "Sur un autre PC ? Collez ici votre code de sauvegarde"
	edit.custom_minimum_size = Vector2(520, 0)
	rr.add_child(edit)
	rr.add_child(Ui.button("Récupérer", func(): _restore(edit.text.strip_edges()), 0, 16))


func _cloud_status(state: String) -> void:
	if not is_instance_valid(_cloud_label):
		return
	var txt: Array = {
		"ok": ["✓ synchronisée", Ui.C_BORDER],
		"syncing": ["synchronisation…", Ui.C_MUTED],
		"pending": ["⏳ progrès hors ligne en attente d'envoi (automatique au retour de la connexion)", Ui.C_GOLD],
		"offline": ["hors ligne", Ui.C_MUTED],
	}.get(state, ["", Ui.C_MUTED])
	_cloud_label.text = txt[0]
	_cloud_label.add_theme_color_override("font_color", txt[1])


func _restore(code: String) -> void:
	if code.length() < 8:
		Ui.toast("Collez d'abord votre code de sauvegarde.", Ui.C_GOLD)
		return
	Ui.confirm("Récupérer cette sauvegarde ?", "La progression de ce PC sera remplacée par celle du cloud liée à ce code.", "Récupérer", func():
		var res: Dictionary = await Backend.restore_save(code)
		if res.has("_error"):
			Ui.toast(String(res.get("detail", "Échec de la récupération.")), Ui.C_GOLD, 4.0)
			Audio.play("erreur")
			return
		Ui.toast("Sauvegarde récupérée : bon retour, %s !" % res.get("name", ""), Ui.C_BORDER, 4.0)
		queue_free()
		Game.goto("main_menu"))


func _mission_count() -> int:
	var n := 0
	for z in Db.campaign.zones:
		n += z.missions.size()
	return n


func _fill_heroes() -> void:
	for c in _hero_box.get_children():
		c.queue_free()
	for id in Db.characters:
		var c: Dictionary = Db.characters[id]
		var unlocked := Profile.character_unlocked(id)
		var b := Ui.button(c.name if unlocked else "🔒 ???", func(): _pick_hero(id), 0, 18)
		b.icon = Db.tex(c.sprite)
		b.expand_icon = false
		b.add_theme_constant_override("icon_max_width", 48)
		b.toggle_mode = true
		b.button_pressed = Profile.data.character == id
		b.disabled = not unlocked
		if not unlocked:
			b.tooltip_text = "Terminez la mission « %s » pour débloquer ce héros." % Db.mission(c.unlock).get("name", c.unlock)
		_hero_box.add_child(b)


func _pick_hero(id: String) -> void:
	Profile.data.character = id
	Profile.save()
	Profile.changed.emit()
	Audio.play("clic")
	_fill_heroes()
	_refresh_avatar()


func _save_name() -> void:
	var wanted := _name_edit.text.strip_edges()
	if wanted == Settings.player_name:
		return
	_name_status.text = "Vérification…"
	_name_status.add_theme_color_override("font_color", Ui.C_MUTED)
	var res: Dictionary = await Backend.change_name(wanted)
	if not is_instance_valid(self):
		return
	if res.has("_error"):
		_name_status.text = res.detail
		_name_status.add_theme_color_override("font_color", Ui.C_BAD)
		Audio.play("erreur")
		return
	_name_edit.text = res.name
	_name_status.text = "Pseudo enregistré : « %s » !" % res.name
	_name_status.add_theme_color_override("font_color", Ui.C_GOOD)
	Audio.play("achat")
	_refresh_avatar()


func _refresh_avatar() -> void:
	if not is_instance_valid(_avatar):
		return
	var d = Profile.data
	_avatar.texture = Db.tex(Db.characters.get(d.character, {}).get("sprite", ""))
	_avatar.modulate = Ui.color_of_cosmetic(d.cosmetics.color)
	_hat.texture = Db.tex(Db.battlepass.hats.get(d.cosmetics.hat, {}).get("sprite", "")) if d.cosmetics.hat != "" else null
	_avatar_name.text = Settings.player_name

extends Control
## Écran de mise à jour : au lancement (recherche + installation automatique) ou à la demande du joueur
## (Game.params.info = version à installer). Relance le jeu une fois la nouvelle version en place.

var _status: Label
var _bar: ProgressBar
var _buttons: HBoxContainer


func _ready() -> void:
	Ui.screen_base(self, "res://assets/backgrounds/titre.png", 0.75)
	var box := Ui.vbox(22)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.custom_minimum_size = Vector2(900, 0)
	Ui.place(box, Control.PRESET_CENTER, Vector2(-450, -170))
	add_child(box)
	box.add_child(Ui.title("Cybervor", 72))
	box.add_child(Ui.label("Version %s" % Updater.current, 18, Ui.C_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	_status = Ui.label("Recherche de mises à jour…", 26, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(900, 34)
	_bar.max_value = 1.0
	_bar.step = 0.001
	_bar.show_percentage = false
	_bar.visible = false
	box.add_child(_bar)
	_buttons = Ui.hbox(16)
	_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(_buttons)
	_run.call_deferred()


func _run() -> void:
	var info: Dictionary = Game.params.get("info", {})
	if info.is_empty():
		info = await Updater.check()
		if info.is_empty():
			_continue()
			return
	print("[MAJ] installation de la version %s" % info.version)
	_status.text = "Nouvelle version %s : installation…" % info.version
	_bar.visible = true
	var err := await Updater.install(info, _on_progress)
	if Updater._test_dir() != "" and err == "":
		await Updater._shot("installee_%s.png" % info.version)
	if err == "":
		_status.text = "Mise à jour %s installée ! Redémarrage…" % info.version
		await get_tree().create_timer(1.2).timeout
		Updater.restart()
		return
	_status.text = "La mise à jour a échoué : %s" % err
	_status.add_theme_color_override("font_color", Ui.C_GOLD)
	_bar.visible = false
	Audio.play("erreur")
	_buttons.add_child(Ui.button("Réessayer", func(): Game.goto("update"), 240, 22))
	_buttons.add_child(Ui.button("Site de téléchargement", func():
		OS.shell_open(Backend.base_url + "/#telecharger"), 0, 22))
	_buttons.add_child(Ui.button("Jouer sans mettre à jour", _continue, 0, 22))


func _on_progress(frac: float, text: String) -> void:
	if not is_inside_tree():
		return
	_bar.value = frac
	_status.text = text


func _continue() -> void:
	Game.goto("main_menu")
	Updater.start_watch()

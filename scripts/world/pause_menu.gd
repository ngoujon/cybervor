extends Control
## Menu pause (met le jeu en pause uniquement en solo).

var world: Node


func _ready() -> void:
	theme = Ui.theme
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not Net.is_online():
		get_tree().paused = true
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var p := Ui.panel(30)
	Ui.place(p, Control.PRESET_CENTER, Vector2(-280, -330))
	p.custom_minimum_size = Vector2(560, 0)
	add_child(p)
	var v := Ui.vbox(14)
	p.add_child(v)
	v.add_child(Ui.title("Pause" if not Net.is_online() else "Menu", 56))
	if Net.is_online():
		v.add_child(Ui.label("(la partie continue en multijoueur !)", 18, Ui.C_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	var resume := Ui.button("Reprendre", _close, 0, 26)
	v.add_child(resume)
	v.add_child(Ui.button("Guide du jeu (F3)", func(): Ui.open_guide(), 0, 24))
	v.add_child(Ui.button("Paramètres", _settings, 0, 24))
	v.add_child(Ui.button("Amis & messages", func(): Ui.open_social("amis"), 0, 24))
	v.add_child(Ui.button("Signaler un bug / une suggestion", func(): Ui.open_feedback(), 0, 24))
	v.add_child(Ui.button("Abandonner la partie", _quit, 0, 24))
	v.add_child(Ui.button("Quitter le jeu", Ui.confirm_quit, 0, 24))
	resume.call_deferred("grab_focus")
	Ui.push_modal(self, _close)


func _settings() -> void:
	Ui.open_settings()


func _close() -> void:
	get_tree().paused = false
	queue_free()


func _quit() -> void:
	get_tree().paused = false
	world.quit_run()

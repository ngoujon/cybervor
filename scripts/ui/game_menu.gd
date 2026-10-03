extends Control
## Menu rapide ouvert par Échap hors partie (dans une partie, c'est le menu pause du monde).
## Échap le referme (pile de modales gérée par Ui).


func _ready() -> void:
	theme = Ui.theme
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var p := Ui.panel(30)
	Ui.place(p, Control.PRESET_CENTER, Vector2(-280, -300))
	p.custom_minimum_size = Vector2(560, 0)
	add_child(p)
	var v := Ui.vbox(14)
	p.add_child(v)
	v.add_child(Ui.title("Menu", 56))
	var resume := Ui.button("Reprendre", queue_free, 0, 26)
	v.add_child(resume)
	if Game.current_screen != "main_menu":
		v.add_child(Ui.button("Menu principal", _main_menu, 0, 24))
	v.add_child(Ui.button("Paramètres", Ui.open_settings, 0, 24))
	v.add_child(Ui.button("Amis & messages", func(): Ui.open_social("amis"), 0, 24))
	v.add_child(Ui.button("Signaler un bug / une suggestion", func(): Ui.open_feedback(), 0, 24))
	v.add_child(Ui.button("Quitter le jeu", Ui.confirm_quit, 0, 24))
	v.add_child(Ui.label("Échap : fermer", 16, Ui.C_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	resume.call_deferred("grab_focus")


func _main_menu() -> void:
	if Net.is_online():
		Net.close()   # quitte le salon multijoueur proprement
	queue_free()
	Game.goto("main_menu")

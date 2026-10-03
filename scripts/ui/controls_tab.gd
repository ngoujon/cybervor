extends VBoxContainer
## Onglet « Commandes » des paramètres : raccourcis de l'esquive et des 5 sorts actifs.
## Pour chaque action : touche principale, touche secondaire (clavier ou boutons de la souris) et bouton manette.
## Cliquer (ou valider à la manette) sur une case puis appuyer sur la touche / le bouton voulu.
## Échap : annuler · Suppr : vider la case.

const SLOT_TITLES := ["Principal", "Secondaire", "Manette"]
const CAPTURE_TIMEOUT := 8.0

var _buttons := {}        # action -> [Button, Button, Button]
var _capture := {}        # {action, slot, button, t} pendant la capture
var _info: Label


func _ready() -> void:
	name = "Commandes"
	add_theme_constant_override("separation", 14)
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(Ui.label("Choisissez vos raccourcis : touches du clavier, boutons de la souris (clic, molette, boutons latéraux) et manette.", 18, Ui.C_MUTED))
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 10)
	add_child(grid)
	grid.add_child(Ui.label("", 18))
	for t in SLOT_TITLES:
		grid.add_child(Ui.label(t, 20, Ui.C_GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	grid.add_child(Ui.label("", 18))
	for act in Settings.BINDABLE:
		grid.add_child(Ui.label(Settings.BIND_NAMES[act], 22))
		var row := []
		for slot in 3:
			var b := Ui.button("", _start_capture.bind(act, slot), 250, 20)
			b.tooltip_text = "Cliquez puis appuyez sur %s. Échap : annuler, Suppr : vider." % ("un bouton de la manette" if slot == 2 else "une touche ou un bouton de la souris")
			grid.add_child(b)
			row.append(b)
		_buttons[act] = row
		var r := Ui.button("↺", func():
			Settings.reset_bindings(act)
			_refresh(), 0, 20)
		r.tooltip_text = "Rétablir les raccourcis par défaut de « %s »" % Settings.BIND_NAMES[act]
		grid.add_child(r)
	_info = Ui.label("", 18, Ui.C_GOLD)
	add_child(_info)
	var h := Ui.hbox(16)
	add_child(h)
	h.add_child(Ui.button("Tout rétablir par défaut", func():
		Settings.reset_bindings()
		_refresh()
		_info.text = "Raccourcis par défaut rétablis.", 0, 20))
	add_child(Ui.label("Fixes : ZQSD / WASD / flèches / stick gauche / croix pour bouger · Échap / Start : menu · Entrée : discuter (multijoueur).", 17, Ui.C_MUTED))
	_refresh()


func _refresh() -> void:
	for act in _buttons:
		var b := Settings.binding(act)
		for slot in 3:
			_buttons[act][slot].text = Settings.code_label(b[slot])


func _start_capture(act: String, slot: int) -> void:
	if not _capture.is_empty():
		_end_capture()
	await get_tree().process_frame   # ignore l'appui qui a ouvert la capture
	var btn: Button = _buttons[act][slot]
	btn.text = "Bouton manette…" if slot == 2 else "Appuyez sur une touche…"
	_capture = {"action": act, "slot": slot, "button": btn, "t": CAPTURE_TIMEOUT}
	_info.text = "« %s » (%s) : %s · Échap : annuler · Suppr : vider" % [Settings.BIND_NAMES[act], SLOT_TITLES[slot].to_lower(),
		"appuyez sur un bouton de la manette (ou une gâchette)" if slot == 2 else "appuyez sur une touche ou un bouton de la souris"]


func capturing() -> bool:
	return not _capture.is_empty()


func _process(delta: float) -> void:
	if _capture.is_empty():
		return
	_capture.t -= delta
	if _capture.t <= 0:
		_info.text = "Délai dépassé : raccourci inchangé."
		_end_capture()


func _input(event: InputEvent) -> void:
	if _capture.is_empty() or not event.is_pressed() or event.is_echo():
		return
	var pad_slot: bool = _capture.slot == 2
	if event is InputEventKey:
		get_viewport().set_input_as_handled()
		if event.physical_keycode == KEY_ESCAPE or event.keycode == KEY_ESCAPE:
			_info.text = "Modification annulée."
			_end_capture()
			return
		if event.physical_keycode in [KEY_DELETE, KEY_BACKSPACE]:
			_assign("")
			return
		if pad_slot:
			_info.text = "Cette case attend un bouton de la manette (Échap : annuler)."
			return
	elif event is InputEventMouseButton:
		if pad_slot:
			return
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
		if event is InputEventJoypadMotion and absf(event.axis_value) < 0.6:
			return
		get_viewport().set_input_as_handled()
		if not pad_slot:
			_info.text = "Cette case attend une touche ou la souris : utilisez la colonne « Manette »."
			return
	else:
		return
	var code := Settings.event_to_str(event)
	if code == "":
		return
	if code in Settings.RESERVED:
		_info.text = "« %s » est réservé (déplacements ou menu). Choisissez autre chose." % Settings.code_label(code)
		Audio.play("erreur")
		return
	_assign(code)


func _assign(code: String) -> void:
	var act: String = _capture.action
	var slot: int = _capture.slot
	var taken := Settings.set_binding(act, slot, code)
	if code == "":
		_info.text = "Raccourci retiré."
	elif taken != "" and taken != act:
		_info.text = "« %s » est maintenant pour %s (retiré de %s)." % [Settings.code_label(code), Settings.BIND_NAMES[act], Settings.BIND_NAMES[taken]]
	else:
		_info.text = "« %s » → %s" % [Settings.code_label(code), Settings.BIND_NAMES[act]]
	Audio.play("clic")
	_end_capture()


func _end_capture() -> void:
	var btn: Button = _capture.get("button")
	_capture = {}
	_refresh()
	if is_instance_valid(btn):
		btn.grab_focus.call_deferred()

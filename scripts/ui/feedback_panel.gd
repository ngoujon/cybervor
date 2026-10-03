extends Control
## Fenêtre « Bugs & suggestions » (séparée du panneau social). Ouverture : Ui.open_feedback() — raccourci F1.
## À gauche : liste publique des retours des joueurs, avec recherche et filtres.
## À droite : formulaire de signalement (avec les retours similaires, pour éviter les doublons)
## ou détail d'un retour (« Moi aussi », commentaires).

const STATUS_COLORS := {
	"nouveau": Color("#a99cc9"), "confirmé": Color("#ffd166"), "en cours": Color("#5ff7ff"),
	"corrigé": Color("#7dff9b"), "refusé": Color("#ff6b6b"), "doublon": Color("#ff6b6b"),
}

var _status: Label
var _search: LineEdit
var _kind: OptionButton
var _sort: OptionButton
var _list: VBoxContainer
var _right: VBoxContainer
var _search_timer: Timer
var _current_id := -1
# formulaire
var _f_kind: OptionButton
var _f_title: LineEdit
var _f_text: TextEdit
var _f_tech: CheckBox
var _f_similar: VBoxContainer
var _f_status: Label
var _similar_timer: Timer


func _ready() -> void:
	theme = Ui.theme
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var p := Ui.panel(24)
	Ui.place(p, Control.PRESET_CENTER, Vector2(-760, -470))
	p.custom_minimum_size = Vector2(1520, 940)
	add_child(p)
	var root := Ui.vbox(12)
	p.add_child(root)

	var head := Ui.hbox(12)
	root.add_child(head)
	head.add_child(Ui.title("Bugs & suggestions", 44))
	head.add_child(Ui.spacer())
	_status = Ui.label("", 18, Ui.C_GOLD)
	head.add_child(_status)
	head.add_child(Ui.button("Fermer (Échap)", queue_free, 0, 20))

	var bar := Ui.hbox(10)
	root.add_child(bar)
	_search = LineEdit.new()
	_search.placeholder_text = "🔍 Rechercher un bug ou une suggestion (ex. laser, boss, son, manette)…"
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.clear_button_enabled = true
	_search.add_theme_font_size_override("font_size", 20)
	_search.text_changed.connect(func(_t): _search_timer.start())
	bar.add_child(_search)
	_kind = _option(["Tout", "🐞 Bugs", "💡 Suggestions"])
	_kind.item_selected.connect(func(_i): _load_list())
	bar.add_child(_kind)
	_sort = _option(["Les plus soutenus", "Les plus récents"])
	_sort.item_selected.connect(func(_i): _load_list())
	bar.add_child(_sort)
	bar.add_child(Ui.button("＋ Nouveau signalement", _show_form, 0, 20))

	var body := Ui.hbox(16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	var lp := Ui.panel(10, Color(Ui.C_PANEL_2, 0.6))
	lp.custom_minimum_size = Vector2(620, 0)
	body.add_child(lp)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lp.add_child(sc)
	_list = Ui.vbox(8)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_list)
	var rp := Ui.panel(16, Color(Ui.C_PANEL_2, 0.6))
	rp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(rp)
	_right = Ui.vbox(10)
	rp.add_child(_right)

	_search_timer = _timer(0.35, _load_list)
	_similar_timer = _timer(0.5, _load_similar)
	if not Backend.enabled():
		_status.text = "Hors ligne : la liste publique n'est pas disponible."
	_show_form()
	_load_list()


func _timer(wait: float, cb: Callable) -> Timer:
	var t := Timer.new()
	t.one_shot = true
	t.wait_time = wait
	t.timeout.connect(cb)
	add_child(t)
	return t


func _option(items: Array) -> OptionButton:
	var o := OptionButton.new()
	for it in items:
		o.add_item(it)
	o.add_theme_font_size_override("font_size", 18)
	return o


func _kind_filter() -> String:
	return ["", "bug", "suggestion"][_kind.selected]


# ------------------------------------------------------------------ liste
func _load_list() -> void:
	_clear(_list)
	if not Backend.enabled():
		_list.add_child(Ui.label("La liste des retours des joueurs s'affiche quand le jeu est connecté au serveur.\n\nVous pouvez quand même envoyer un signalement : il partira automatiquement à la prochaine connexion.", 18, Ui.C_MUTED))
		return
	_list.add_child(Ui.label("Chargement…", 18, Ui.C_MUTED))
	var res = await Backend.feedback_list(_search.text, _kind_filter(), "votes" if _sort.selected == 0 else "recent")
	if not is_instance_valid(self):
		return
	_clear(_list)
	if not (res is Dictionary) or res.has("_error"):
		_list.add_child(Ui.label("Impossible de charger la liste : %s" % (res.detail if res is Dictionary else "?"), 18, Ui.C_BAD))
		return
	var items: Array = res.get("feedback", [])
	if items.is_empty():
		var msg := "Aucun résultat pour « %s ». Vous êtes peut-être le premier à le signaler !" % _search.text if _search.text != "" else "Aucun retour pour l'instant. Lancez-vous !"
		_list.add_child(Ui.label(msg, 18, Ui.C_MUTED))
		return
	for it in items:
		_list.add_child(_row(it))


func _row(it: Dictionary) -> Control:
	var b := Button.new()
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 76)
	b.toggle_mode = false
	b.add_theme_stylebox_override("normal", Ui.box(Color(Ui.C_PANEL, 0.95), Ui.C_BORDER.darkened(0.55) if int(it.id) != _current_id else Ui.C_BORDER, 2, 10))
	b.add_theme_stylebox_override("hover", Ui.box(Color(Ui.C_PANEL_2, 1.0), Ui.C_BORDER, 2, 10))
	b.pressed.connect(func(): _show_detail(int(it.id)))
	Ui.wire_sfx(b)
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 10)
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(m)
	var v := Ui.vbox(2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(v)
	var t := Ui.label(("🐞 " if it.kind == "bug" else "💡 ") + String(it.title), 19)
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(t)
	var meta := Ui.label("👍 %d   💬 %d   ·   %s   ·   par %s" % [int(it.votes), int(it.comments), it.status, it.author], 15, STATUS_COLORS.get(it.status, Ui.C_MUTED))
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(meta)
	return b


# ------------------------------------------------------------------ détail d'un retour
func _show_detail(fid: int) -> void:
	_current_id = fid
	_clear(_right)
	_right.add_child(Ui.label("Chargement…", 18, Ui.C_MUTED))
	var d = await Backend.feedback_get(fid)
	if not is_instance_valid(self) or _current_id != fid:
		return
	_clear(_right)
	if not (d is Dictionary) or d.has("_error"):
		_right.add_child(Ui.label("Impossible de charger ce retour.", 18, Ui.C_BAD))
		return
	var top := Ui.hbox(10)
	_right.add_child(top)
	top.add_child(Ui.button("← Nouveau signalement", _show_form, 0, 16))
	top.add_child(Ui.spacer())
	top.add_child(Ui.label(String(d.status).to_upper(), 18, STATUS_COLORS.get(d.status, Ui.C_MUTED)))
	var t := Ui.label(("🐞 " if d.kind == "bug" else "💡 ") + String(d.title), 26, Ui.C_BORDER)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_right.add_child(t)
	_right.add_child(Ui.label("Signalé par %s le %s" % [d.author, _date(d.created)], 15, Ui.C_MUTED))
	var txt := Ui.rich("", 18)
	txt.text = String(d.text)
	txt.fit_content = true
	_right.add_child(txt)

	var vr := Ui.hbox(10)
	_right.add_child(vr)
	var vote := Ui.button(("✔ Vous avez soutenu  (%d)" if d.voted else "👍 Moi aussi !  (%d)") % int(d.votes), func(): _vote(fid), 0, 20)
	vote.disabled = not Backend.online
	vote.tooltip_text = "Vous avez le même problème ou la même envie ? Soutenez ce retour plutôt que d'en créer un nouveau."
	vr.add_child(vote)
	vr.add_child(Ui.label("Même souci ? Soutenez-le plutôt que d'en créer un doublon.", 15, Ui.C_MUTED))

	_right.add_child(Ui.label("Discussion (%d)" % d.comments_list.size(), 22, Ui.C_GOLD))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_right.add_child(sc)
	var cl := Ui.vbox(6)
	cl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(cl)
	if d.comments_list.is_empty():
		cl.add_child(Ui.label("Pas encore de commentaire. Ajoutez des détails pour aider l'équipe !", 16, Ui.C_MUTED))
	for c in d.comments_list:
		var cp := Ui.panel(8, Color(Ui.C_PANEL, 0.9), Ui.C_ACCENT.darkened(0.4) if c.mine else Ui.C_BORDER.darkened(0.6))
		var cv := Ui.vbox(2)
		cp.add_child(cv)
		cv.add_child(Ui.label("%s · %s" % [c.author, _date(c.created)], 14, Ui.C_ACCENT if c.mine else Ui.C_BORDER))
		var ct := Ui.label(String(c.text), 17)
		ct.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cv.add_child(ct)
		cl.add_child(cp)
	var ir := Ui.hbox(8)
	_right.add_child(ir)
	var input := LineEdit.new()
	input.placeholder_text = "Ajouter un détail, une précision, une idée…" if Backend.online else "Connectez-vous au serveur pour participer."
	input.editable = Backend.online
	input.max_length = 1000
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ir.add_child(input)
	var send := func():
		var text := input.text.strip_edges()
		if text.length() < 2:
			return
		input.editable = false
		var r = await Backend.feedback_comment(fid, text)
		if not is_instance_valid(self):
			return
		if r is Dictionary and r.has("_error"):
			Ui.toast(r.detail, Ui.C_BAD)
			input.editable = true
			return
		Audio.play("achat")
		_show_detail(fid)
		_load_list()
	input.text_submitted.connect(func(_t): send.call())
	var sb := Ui.button("Commenter", send, 0, 18)
	sb.disabled = not Backend.online
	ir.add_child(sb)


func _vote(fid: int) -> void:
	var r = await Backend.feedback_vote(fid)
	if not is_instance_valid(self):
		return
	if r is Dictionary and r.has("_error"):
		Ui.toast(r.detail, Ui.C_BAD)
		return
	Audio.play("ramasse")
	if r.get("voted", false):
		Ui.toast("Merci ! Votre soutien fait remonter ce retour.", Ui.C_GOOD)
	_show_detail(fid)
	_load_list()


# ------------------------------------------------------------------ nouveau signalement
func _show_form() -> void:
	_current_id = -1
	_clear(_right)
	_right.add_child(Ui.label("Nouveau signalement", 26, Ui.C_BORDER))
	_right.add_child(Ui.label("Un bug ? Une idée géniale ? Une plainte au sujet de la moustache du Noyau ? Dites-nous tout !", 17, Ui.C_MUTED))
	var h := Ui.hbox(10)
	_right.add_child(h)
	h.add_child(Ui.label("Type :", 20))
	_f_kind = _option(["🐞 Bug", "💡 Suggestion"])
	h.add_child(_f_kind)
	_f_title = LineEdit.new()
	_f_title.placeholder_text = "Titre court (ex. « Le laser traverse les murs »)"
	_f_title.max_length = 90
	_f_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_f_title.text_changed.connect(func(_t): _similar_timer.start())
	h.add_child(_f_title)
	_f_similar = Ui.vbox(4)
	_right.add_child(_f_similar)
	_f_text = TextEdit.new()
	_f_text.placeholder_text = "Décrivez ce qui s'est passé (ce que vous faisiez, ce que vous attendiez, ce qui est arrivé)…"
	_f_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_f_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_f_text.add_theme_font_size_override("font_size", 19)
	_f_text.add_theme_stylebox_override("normal", Ui.box(Color("#100d26"), Ui.C_BORDER.darkened(0.4), 2, 10))
	_right.add_child(_f_text)
	_f_tech = CheckBox.new()
	_f_tech.text = "Joindre les infos techniques (visibles par l'équipe seulement)"
	_f_tech.button_pressed = true
	_f_tech.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_right.add_child(_f_tech)
	var bh := Ui.hbox(12)
	_right.add_child(bh)
	bh.add_child(Ui.button("Envoyer", _send, 240, 22))
	_f_status = Ui.label("", 17, Ui.C_GOOD)
	_f_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_f_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bh.add_child(_f_status)
	var pending := Backend.pending_feedback_count()
	if pending > 0:
		_f_status.text = "%d retour(s) en attente d'envoi (hors ligne)." % pending
	_f_title.call_deferred("grab_focus")


## Retours qui ressemblent au titre en cours de saisie (anti-doublons).
func _load_similar() -> void:
	if not is_instance_valid(_f_similar) or not Backend.enabled():
		return
	var q := _f_title.text.strip_edges()
	_clear(_f_similar)
	if q.length() < 3:
		return
	var words := Array(q.split(" ", false)).filter(func(w): return w.length() >= 3)
	if words.is_empty():
		return
	var found := {}
	for w in words.slice(0, 4):   # recherche mot par mot pour trouver aussi les formulations proches
		var res = await Backend.feedback_list(w, "", "votes")
		if not is_instance_valid(_f_similar):
			return
		if res is Dictionary and not res.has("_error"):
			for it in res.get("feedback", []):
				found[int(it.id)] = it
	if found.is_empty() or _f_title.text.strip_edges() != q:
		return
	var items := found.values()
	items.sort_custom(func(a, b): return int(a.votes) > int(b.votes))
	_f_similar.add_child(Ui.label("Déjà signalé ? Si c'est le même, soutenez-le plutôt (👍 Moi aussi) :", 16, Ui.C_GOLD))
	for it in items.slice(0, 4):
		var b := Ui.button(("🐞 " if it.kind == "bug" else "💡 ") + "%s   (👍 %d)" % [it.title, int(it.votes)], func(): _show_detail(int(it.id)), 0, 16)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_f_similar.add_child(b)


func _send() -> void:
	var text := _f_text.text.strip_edges()
	var title := _f_title.text.strip_edges()
	if text.length() < 3 and title.length() < 3:
		Ui.toast("Écrivez au moins quelques mots 🙂", Ui.C_BAD)
		return
	if text.length() < 3:
		text = title
	var ctx := Ui.tech_context() if _f_tech.button_pressed else {}
	var kind := "bug" if _f_kind.selected == 0 else "suggestion"
	_f_status.text = "Envoi…"
	var r: String = await Backend.send_feedback(kind, text, ctx, title)
	if not is_instance_valid(self):
		return
	Audio.play("achat")
	Ui.toast("Merci pour votre retour ! Mamie RAM le lira avec ses lunettes.", Ui.C_GOOD)
	if r == "sent":
		_show_form()
		_f_status.text = "Merci ! Votre %s est maintenant visible dans la liste." % ("rapport de bug" if kind == "bug" else "suggestion")
		_load_list()
	else:
		_f_text.text = ""
		_f_title.text = ""
		_f_status.text = "Merci ! Enregistré hors ligne : il sera envoyé dès la prochaine connexion."


# ------------------------------------------------------------------ utilitaires
func _clear(n: Node) -> void:
	for c in n.get_children():
		c.queue_free()


func _date(t) -> String:
	var d := Time.get_datetime_dict_from_unix_time(int(t))
	return "%02d/%02d/%d" % [d.day, d.month, d.year]

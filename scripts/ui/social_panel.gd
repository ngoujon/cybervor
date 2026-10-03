extends Control
## Panneau social, utilisable partout (menus et en jeu) : amis et messagerie privée.
## Ouverture : Ui.open_social(onglet) — raccourci F2. Les bugs / suggestions ont leur propre fenêtre (F1).

const TABS := ["amis", "messages"]

var start_tab := "amis"
var chat_with := ""          # player_id de la conversation ouverte

var _tabs: TabContainer
var _friends_box: VBoxContainer
var _code_label: Label
var _add_edit: LineEdit
var _status: Label
var _conv_list: VBoxContainer
var _conv_title: Label
var _conv_log: RichTextLabel
var _conv_input: LineEdit
var _last_msg_id := 0
var _friends: Array = []
var _poll_t := 0.0


func _ready() -> void:
	theme = Ui.theme
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var p := Ui.panel(24)
	Ui.place(p, Control.PRESET_CENTER, Vector2(-680, -430))
	p.custom_minimum_size = Vector2(1360, 860)
	add_child(p)
	var root := Ui.vbox(12)
	p.add_child(root)
	var head := Ui.hbox(12)
	root.add_child(head)
	head.add_child(Ui.title("Social", 46))
	head.add_child(Ui.spacer())
	_status = Ui.label("", 18, Ui.C_GOLD)
	head.add_child(_status)
	head.add_child(Ui.button("Fermer (Échap)", queue_free, 0, 20))

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_theme_font_size_override("font_size", 22)
	root.add_child(_tabs)
	_tabs.add_child(_build_friends())
	_tabs.add_child(_build_messages())
	_tabs.current_tab = max(0, TABS.find(start_tab))
	_tabs.tab_changed.connect(func(_i): _refresh())
	if not Backend.online:
		_status.text = "Hors ligne : amis et messages nécessitent le serveur (Paramètres > Réseau)."
	_refresh()


func _process(delta: float) -> void:
	_poll_t += delta
	if _poll_t > 3.0 and _tabs.current_tab == 1 and chat_with != "":
		_poll_t = 0.0
		_load_messages()


func _refresh() -> void:
	match _tabs.current_tab:
		0:
			_load_friends()
		1:
			_load_friends()
			if chat_with != "":
				_load_messages()


# ------------------------------------------------------------------ amis
func _build_friends() -> Control:
	var v := Ui.vbox(12)
	v.name = "Amis"
	var top := Ui.hbox(12)
	v.add_child(top)
	_code_label = Ui.label("Votre code ami : …", 24, Ui.C_BORDER)
	top.add_child(_code_label)
	top.add_child(Ui.button("Copier", func():
		DisplayServer.clipboard_set(Backend.my_code)
		Ui.toast("Code ami copié !"), 0, 18))
	top.add_child(Ui.spacer())
	_add_edit = LineEdit.new()
	_add_edit.placeholder_text = "Pseudo du joueur (ou son code ami)"
	_add_edit.custom_minimum_size = Vector2(420, 0)
	_add_edit.text_submitted.connect(func(_t): _add_friend())
	top.add_child(_add_edit)
	top.add_child(Ui.button("Ajouter en ami", _add_friend, 0, 20))
	v.add_child(Ui.label("Tapez simplement le pseudo de votre ami. Dans un salon multijoueur, vous pouvez aussi cliquer sur « + Ami » à côté d'un joueur.", 17, Ui.C_MUTED))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	_friends_box = Ui.vbox(8)
	_friends_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_friends_box)
	return v


func _load_friends() -> void:
	if not Backend.online:
		_fill_friends([], "Connectez-vous au serveur méta pour gérer vos amis.")
		return
	var res: Dictionary = await Backend.friends()
	if not is_instance_valid(self):
		return
	if res.has("_error"):
		_fill_friends([], res.detail)
		return
	_code_label.text = "Votre code ami : " + res.my_code
	_friends = res.friends
	_fill_friends(_friends, "Aucun ami pour l'instant. Partagez votre code !")
	_fill_conv_list()


func _fill_friends(list: Array, empty_text: String) -> void:
	for c in _friends_box.get_children():
		c.queue_free()
	if list.is_empty():
		_friends_box.add_child(Ui.label(empty_text, 20, Ui.C_MUTED))
		return
	for f in list:
		var row := Ui.panel(10, Color(Ui.C_PANEL_2, 0.9), Ui.C_GOOD if f.online else Ui.C_BORDER.darkened(0.5))
		var h := Ui.hbox(12)
		row.add_child(h)
		h.add_child(Ui.label("●", 22, Ui.C_GOOD if f.online else Ui.C_MUTED))
		var v := Ui.vbox(0)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(Ui.label(f.name, 22))
		var st := {"accepted": "Ami" + (" — en ligne" if f.online else " — hors ligne"), "incoming": "Vous a envoyé une demande d'ami", "outgoing": "Demande envoyée, en attente…"}
		v.add_child(Ui.label(st.get(f.status, ""), 16, Ui.C_MUTED))
		h.add_child(v)
		match f.status:
			"incoming":
				h.add_child(Ui.button("Accepter", func(): _act(Backend.accept_friend.bind(f.player_id), "Vous êtes maintenant amis avec %s !" % f.name), 0, 18))
				h.add_child(Ui.button("Refuser", func(): _act(Backend.remove_friend.bind(f.player_id), "Demande refusée."), 0, 18))
			"accepted":
				var label := "Discuter" + (" (%d)" % f.unread if int(f.unread) > 0 else "")
				h.add_child(Ui.button(label, func(): _open_chat(f.player_id), 0, 18))
				h.add_child(Ui.button("Retirer", func(): _act(Backend.remove_friend.bind(f.player_id), "%s a été retiré de vos amis." % f.name), 0, 18))
			"outgoing":
				h.add_child(Ui.button("Annuler", func(): _act(Backend.remove_friend.bind(f.player_id), "Demande annulée."), 0, 18))
		_friends_box.add_child(row)


func _act(action: Callable, ok_text: String) -> void:
	var res = await action.call()
	if res is Dictionary and res.has("_error"):
		Ui.toast(res.detail, Ui.C_BAD)
		Audio.play("erreur")
	else:
		Ui.toast(ok_text, Ui.C_GOOD)
		Audio.play("achat")
	Backend.poll_social()
	_load_friends()


func _add_friend() -> void:
	var code := _add_edit.text.strip_edges()
	if code == "":
		return
	if not Backend.online:
		Ui.toast("Hors ligne : impossible d'ajouter un ami.", Ui.C_BAD)
		return
	_add_edit.clear()
	_act(Backend.add_friend_auto.bind(code), "Demande d'ami envoyée à %s !" % code)


# ------------------------------------------------------------------ messages
func _build_messages() -> Control:
	var h := Ui.hbox(16)
	h.name = "Messages"
	var left := Ui.panel(10)
	left.custom_minimum_size = Vector2(340, 0)
	h.add_child(left)
	var lsc := ScrollContainer.new()
	lsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(lsc)
	_conv_list = Ui.vbox(6)
	_conv_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lsc.add_child(_conv_list)
	var right := Ui.vbox(8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(right)
	_conv_title = Ui.label("Choisissez un ami à gauche", 24, Ui.C_BORDER)
	right.add_child(_conv_title)
	_conv_log = RichTextLabel.new()
	_conv_log.bbcode_enabled = true
	_conv_log.scroll_following = true
	_conv_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_conv_log.add_theme_font_size_override("normal_font_size", 20)
	right.add_child(_conv_log)
	var ih := Ui.hbox(8)
	right.add_child(ih)
	_conv_input = LineEdit.new()
	_conv_input.placeholder_text = "Votre message… (Entrée pour envoyer)"
	_conv_input.max_length = 500
	_conv_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_conv_input.text_submitted.connect(func(_t): _send())
	ih.add_child(_conv_input)
	ih.add_child(Ui.button("Envoyer", _send, 0, 20))
	return h


func _fill_conv_list() -> void:
	if _conv_list == null:
		return
	for c in _conv_list.get_children():
		c.queue_free()
	var any := false
	for f in _friends:
		if f.status != "accepted":
			continue
		any = true
		var txt: String = ("● " if f.online else "○ ") + f.name + (" (%d)" % f.unread if int(f.unread) > 0 else "")
		var b := Ui.button(txt, _open_chat.bind(f.player_id), 0, 18)
		b.toggle_mode = true
		b.button_pressed = f.player_id == chat_with
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_conv_list.add_child(b)
	if not any:
		_conv_list.add_child(Ui.label("Ajoutez des amis pour discuter.", 18, Ui.C_MUTED))


func _open_chat(player_id: String) -> void:
	chat_with = player_id
	_last_msg_id = 0
	_conv_log.clear()
	for f in _friends:
		if f.player_id == player_id:
			_conv_title.text = "Conversation avec " + f.name
	_tabs.current_tab = 1
	_load_messages()
	_conv_input.call_deferred("grab_focus")


func _load_messages() -> void:
	if chat_with == "" or not Backend.online:
		return
	var res: Dictionary = await Backend.messages(chat_with, _last_msg_id)
	if not is_instance_valid(self) or res.has("_error"):
		return
	for m in res.get("messages", []):
		_last_msg_id = max(_last_msg_id, int(m.id))
		var t := Time.get_datetime_dict_from_unix_time(int(m.created))
		var who := "Vous" if m.mine else _friend_name(chat_with)
		var col := "#5ff7ff" if m.mine else "#ff5fd2"
		_conv_log.append_text("[color=#a59fd0]%02d:%02d[/color] [color=%s]%s :[/color] %s\n" % [t.hour, t.minute, col, who, String(m.text).replace("[", "(")])


func _friend_name(pid: String) -> String:
	for f in _friends:
		if f.player_id == pid:
			return f.name
	return "?"


func _send() -> void:
	var text := _conv_input.text.strip_edges()
	if text == "" or chat_with == "":
		return
	_conv_input.clear()
	var res: Dictionary = await Backend.send_message(chat_with, text)
	if res.has("_error"):
		Ui.toast(res.detail, Ui.C_BAD)
		return
	_load_messages()


# ------------------------------------------------------------------ bugs & suggestions

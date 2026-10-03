extends Control
## Arbres de compétences : 5 arbres, nœuds à rangs avec prérequis, réinitialisation payante.

const CELL := Vector2(170, 140)
const NODE_SIZE := 92

var _tree_idx := 0
var _canvas: Control
var _info: VBoxContainer
var _header: Label
var _tabs: HBoxContainer
var _selected := ""
var _node_buttons := {}


func _ready() -> void:
	Ui.screen_base(self, "res://assets/backgrounds/zone_noyau.png", 0.82)
	Audio.play_music("menu")
	var root := Ui.vbox(14)
	add_child(Ui.margin(root, 40))
	root.add_child(Ui.title("Arbres de compétences"))
	_header = Ui.label("", 24, Ui.C_GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	root.add_child(_header)
	_tabs = Ui.hbox(10)
	_tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(_tabs)

	var body := Ui.hbox(20)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	var cp := Ui.panel(20)
	cp.custom_minimum_size = Vector2(5 * CELL.x + 60, 5 * CELL.y + 40)
	body.add_child(cp)
	_canvas = Control.new()
	_canvas.custom_minimum_size = Vector2(5 * CELL.x, 5 * CELL.y)
	_canvas.draw.connect(_draw_links)
	cp.add_child(_canvas)
	var ip := Ui.panel(22)
	ip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(ip)
	_info = Ui.vbox(12)
	ip.add_child(_info)

	var bar := Ui.hbox(16)
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(bar)
	bar.add_child(Ui.button("Retour", func(): Game.goto("main_menu"), 240))
	bar.add_child(Ui.button("Réinitialiser (%d puces)" % Profile.respec_cost(), _respec, 360))
	_show_tree(0)


func _show_tree(i: int) -> void:
	_tree_idx = i
	_selected = ""
	for c in _tabs.get_children():
		c.queue_free()
	for k in Db.skills.trees.size():
		var t: Dictionary = Db.skills.trees[k]
		var b := Ui.button(t.name, _show_tree.bind(k), 200, 22)
		b.toggle_mode = true
		b.button_pressed = k == i
		b.icon = Db.tex(t.icon)
		b.expand_icon = false
		b.add_theme_constant_override("icon_max_width", 36)
		_tabs.add_child(b)
	_rebuild()


func _rebuild() -> void:
	var tree: Dictionary = Db.skills.trees[_tree_idx]
	_header.text = "Points disponibles : %d   •   Points dépensés : %d   •   Niveau de compte : %d" % [Profile.available_points(), Profile.spent_points(), Profile.data.level]
	for c in _canvas.get_children():
		c.queue_free()
	_node_buttons.clear()
	var col := Color(tree.color)
	for n in tree.nodes:
		var rank = Profile.skill_rank(n.id)
		var reqs = Profile.skill_requirements_met(n.id)
		var b := Button.new()
		b.custom_minimum_size = Vector2(NODE_SIZE, NODE_SIZE)
		b.size = Vector2(NODE_SIZE, NODE_SIZE)
		b.position = _node_pos(n) - Vector2(NODE_SIZE, NODE_SIZE) / 2
		var border := col if rank > 0 else (col.darkened(0.4) if reqs else Color("#3a3560"))
		var bg := Color(col.darkened(0.55), 1) if rank > 0 else Color("#141033")
		var is_ult: bool = n.cost >= 5
		b.add_theme_stylebox_override("normal", Ui.box(bg, border, 4, 46 if not is_ult else 14))
		b.add_theme_stylebox_override("hover", Ui.box(bg.lightened(0.15), Ui.C_GOLD, 4, 46 if not is_ult else 14))
		b.add_theme_stylebox_override("pressed", Ui.box(bg.lightened(0.15), Ui.C_GOLD, 5, 46 if not is_ult else 14))
		b.icon = Db.tex(tree.icon)
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.modulate = Color.WHITE if (rank > 0 or reqs) else Color(0.55, 0.55, 0.65)
		b.tooltip_text = "%s (%d/%d)\n%s" % [n.name, rank, n.max, n.desc]
		b.pressed.connect(_select.bind(n.id))
		Ui.wire_sfx(b)
		_canvas.add_child(b)
		var rl := Ui.label("%d/%d" % [rank, n.max], 18, Ui.C_GOLD if rank >= n.max else Ui.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
		rl.position = _node_pos(n) + Vector2(-30, NODE_SIZE / 2.0 - 4)
		rl.custom_minimum_size = Vector2(60, 0)
		_canvas.add_child(rl)
		_node_buttons[n.id] = b
	_canvas.queue_redraw()
	if _selected == "":
		_selected = tree.nodes[0].id
	_show_info(_selected)


func _node_pos(n: Dictionary) -> Vector2:
	return Vector2((n.pos[0] + 0.5) * CELL.x, (n.pos[1] + 0.5) * CELL.y - 10)


func _draw_links() -> void:
	var tree: Dictionary = Db.skills.trees[_tree_idx]
	var col := Color(tree.color)
	for n in tree.nodes:
		for r in n.req:
			var rn = Db.skill_node(r)
			var active = Profile.skill_rank(r) > 0 and Profile.skill_rank(n.id) > 0
			var avail = Profile.skill_rank(r) > 0
			var c := col if active else (col.darkened(0.45) if avail else Color("#2b2650"))
			_canvas.draw_line(_node_pos(rn), _node_pos(n), Color(0, 0, 0, 0.6), 12, true)
			_canvas.draw_line(_node_pos(rn), _node_pos(n), c, 6, true)


func _select(id: String) -> void:
	_selected = id
	_show_info(id)


func _show_info(id: String) -> void:
	for c in _info.get_children():
		c.queue_free()
	var tree: Dictionary = Db.skills.trees[_tree_idx]
	var n = Db.skill_node(id)
	var rank = Profile.skill_rank(id)
	var top := Ui.hbox(12)
	top.add_child(Ui.icon(tree.icon, 72))
	var tv := Ui.vbox(2)
	tv.add_child(Ui.label(tree.name, 20, Color(tree.color)))
	tv.add_child(Ui.label(tree.desc, 16, Ui.C_MUTED))
	top.add_child(tv)
	_info.add_child(top)
	_info.add_child(HSeparator.new())
	_info.add_child(Ui.title(n.name, 36, Ui.C_TEXT))
	var d := Ui.label(n.desc, 22)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.add_child(d)
	_info.add_child(Ui.label("Rang : %d / %d" % [rank, n.max], 22, Ui.C_GOLD))
	_info.add_child(Ui.label("Coût : %d point%s par rang" % [n.cost, "s" if n.cost > 1 else ""], 20, Ui.C_MUTED))
	if rank > 0:
		var total := {}
		for k in n.stats:
			total[k] = n.stats[k] * rank
		_info.add_child(Ui.label("Bonus actuel :\n" + Db.format_stats(total), 20, Ui.C_GOOD))
	if not n.req.is_empty():
		var names := []
		for r in n.req:
			names.append(Db.skill_node(r).name)
		_info.add_child(Ui.label("Requiert %s : %s" % ["l'un de" if n.get("req_any", false) else "", ", ".join(names)], 18, Ui.C_MUTED if Profile.skill_requirements_met(id) else Ui.C_BAD))
	var b := Ui.button("Améliorer" if rank > 0 else "Débloquer", _unlock.bind(id), 260, 26)
	b.disabled = not Profile.skill_unlockable(id)
	if rank >= n.max:
		b.text = "Maîtrisé !"
	_info.add_child(b)


func _unlock(id: String) -> void:
	if Profile.unlock_skill(id):
		Audio.play("niveau")
		Ui.flash(Color(Db.skills.trees[_tree_idx].color, 0.25))
		_rebuild()
		_show_info(id)
	else:
		Audio.play("erreur")


func _respec() -> void:
	if Profile.spent_points() == 0:
		Ui.toast("Rien à réinitialiser.")
		return
	if Profile.respec():
		Audio.play("reroll")
		Ui.toast("Compétences réinitialisées ! Tous vos points sont rendus.", Ui.C_GOOD)
		Game.goto("skills")
	else:
		Audio.play("erreur")
		Ui.toast("Pas assez de puces.", Ui.C_BAD)

extends Control
## Interface des sorts en jeu :
##  - en bas au centre : esquive (Espace) + jusqu'à 5 sorts actifs (touches 1 à 5) avec leur recharge ;
##  - sur le côté droit, à la verticale : les sorts passifs (sans limite) avec leur rang.

const SLOT := 76

var world: Node
var _bar: HBoxContainer
var _passives: VBoxContainer
var _slots: Array = []       # [{panel, icon, shade, label, key}]
var _dodge: Dictionary = {}
var _sig := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bar = Ui.hbox(10)
	_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Ui.place(_bar, Control.PRESET_CENTER_BOTTOM, Vector2(-330, -SLOT - 34))
	_bar.custom_minimum_size = Vector2(660, SLOT + 24)
	add_child(_bar)
	_passives = Ui.vbox(6)
	_passives.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Ui.place(_passives, Control.PRESET_CENTER_RIGHT, Vector2(-86, -250))
	add_child(_passives)
	# libellés des touches : suivent les réglages et le périphérique utilisé (clavier ou manette)
	Settings.binds_changed.connect(_relabel)
	Settings.input_device_changed.connect(func(_p): _relabel())


func _relabel() -> void:
	_sig = ""
	if is_inside_tree() and world:
		refresh()


## Reconstruit l'affichage quand les sorts du joueur local changent.
func refresh() -> void:
	var st: Dictionary = world.public.get(Net.my_id(), {})
	var spells: Dictionary = st.get("spells", {})
	var actives: Array = st.get("actives", [])
	var sig := JSON.stringify([spells, actives])
	if sig == _sig and not _slots.is_empty():
		return
	_sig = sig
	for c in _bar.get_children():
		c.queue_free()
	for c in _passives.get_children():
		c.queue_free()
	_slots.clear()
	var me = world.player_nodes.get(Net.my_id())
	var ddef: Dictionary = Db.spells.dodges.get(me.character if me else "patatron", {})
	_dodge = _slot(ddef.get("icon", ""), Settings.hud_label("dash"), Color(ddef.get("color", "#ffffff")),
		"%s (%s)\n%s" % [ddef.get("name", "Esquive"), Settings.hud_label("dash"), ddef.get("desc", "")], true)
	_bar.add_child(_spacer())
	for i in int(Db.spells.get("max_actives", 5)):
		if i < actives.size():
			var def: Dictionary = Db.spells.spells[actives[i]]
			var rank: int = spells.get(actives[i], 1)
			var key := Settings.hud_label("spell_%d" % (i + 1))
			_slots.append(_slot(def.icon, key, Color(def.color), "%s — rang %d (%s)\n%s" % [def.name, rank, key, describe(actives[i], rank)], false, rank))
		else:
			_slots.append(_slot("", Settings.hud_label("spell_%d" % (i + 1)), Ui.C_MUTED, "Emplacement libre : choisissez un sort actif en montant de niveau.", false))
	# passifs : colonne verticale à droite
	var any := false
	for sid in spells:
		var def2: Dictionary = Db.spells.spells[sid]
		if def2.type != "passive":
			continue
		any = true
		_passives.add_child(_passive_row(sid, def2, spells[sid]))
	if any:
		_passives.move_child(_title_label("Passifs"), 0)


func _title_label(t: String) -> Label:
	var l := Ui.label(t, 15, Ui.C_GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_passives.add_child(l)
	return l


func _spacer() -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(14, 0)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s


func _slot(icon_path: String, key: String, col: Color, tip: String, dodge: bool, rank := 0) -> Dictionary:
	var p := Ui.panel(4, Color(0.05, 0.03, 0.12, 0.85), col if icon_path != "" else Color(Ui.C_MUTED, 0.4))
	p.custom_minimum_size = Vector2(SLOT, SLOT)
	p.tooltip_text = tip
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	_bar.add_child(p)
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(holder)
	var ic := Ui.icon(icon_path, SLOT - 12)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ic.position = Vector2(2, 2)
	holder.add_child(ic)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.62)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.position = Vector2(-2, -2)
	shade.size = Vector2(SLOT - 4, 0)
	holder.add_child(shade)
	var cdl := Ui.label("", 24, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	cdl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cdl.position = Vector2(0, SLOT / 2.0 - 22)
	cdl.custom_minimum_size = Vector2(SLOT - 8, 0)
	holder.add_child(cdl)
	var kl := Ui.label(key, 14 if dodge or key.length() > 3 else 16, Ui.C_GOLD)
	kl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	kl.position = Vector2(-2, SLOT - 32)
	holder.add_child(kl)
	if rank > 0:
		var rl := Ui.label("★%d" % rank, 14, Ui.C_BORDER)
		rl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rl.position = Vector2(SLOT - 40, -4)
		holder.add_child(rl)
	return {"panel": p, "shade": shade, "label": cdl, "empty": icon_path == ""}


func _passive_row(sid: String, def: Dictionary, rank: int) -> Control:
	var p := Ui.panel(3, Color(0.05, 0.03, 0.12, 0.8), Color(def.color))
	p.custom_minimum_size = Vector2(64, 64)
	p.tooltip_text = "%s — rang %d\n%s" % [def.name, rank, describe(sid, rank)]
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(holder)
	var ic := Ui.icon(def.icon, 54)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(ic)
	# pastilles de rang
	for r in int(def.get("max", 5)):
		var dot := ColorRect.new()
		dot.color = Color(def.color) if r < rank else Color(1, 1, 1, 0.18)
		dot.size = Vector2(8, 4)
		dot.position = Vector2(2 + r * 10, 52)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(dot)
	return p


func _process(_d: float) -> void:
	if not visible or world == null:
		return
	var me = world.player_nodes.get(Net.my_id())
	if me and not _dodge.is_empty():
		_cooldown(_dodge, me.dash_cd, me.dodge_cooldown())
	for i in _slots.size():
		var s: Dictionary = _slots[i]
		if s.empty:
			continue
		var cd = world.my_cd.get(i, [0.0, 0.0])
		_cooldown(s, max(0.0, float(cd[0]) - world.server_time), float(cd[1]))


func _cooldown(s: Dictionary, left: float, total: float) -> void:
	var k: float = clamp(left / total, 0.0, 1.0) if total > 0 else 0.0
	s.shade.size.y = (SLOT - 8) * k
	s.label.text = ("%.1f" % left if left < 3.0 else str(int(ceil(left)))) if left > 0.05 else ""


# ------------------------------------------------------------------ descriptions
const DMG_TYPES := {"melee": ["Physique", "#ff8a5c", "melee"], "ranged": ["Distance", "#ffd166", "ranged"],
	"tech": ["Techno", "#5ff7ff", "tech"], "support": ["Soutien", "#06ffa5", ""]}


## Type de dégâts d'un sort actif : [libellé, couleur, statistique] (vide pour les passifs).
static func dmg_type(sid: String) -> Array:
	var def: Dictionary = Db.spells.spells[sid]
	if def.type != "active":
		return []
	return DMG_TYPES.get(def.get("dmg_type", "tech"), DMG_TYPES.tech)


## Description d'un sort avec ses valeurs au rang donné ({dmg}, {radius}…).
static func describe(sid: String, rank: int) -> String:
	var def: Dictionary = Db.spells.spells[sid]
	var vals := {}
	var base: Dictionary = def.get("base", {})
	var up: Dictionary = def.get("up", {})
	for k in base:
		var b = base[k]
		if b is Dictionary:
			for k2 in b:
				var mult: float = float(rank) if def.kind == "stats" else 1.0
				vals[k2] = _fmt(float(b[k2]) * mult + float(up.get(k, {}).get(k2, 0.0)) * (rank - 1))
		elif not (b is String):
			vals[k] = _fmt(float(b) + float(up.get(k, 0.0)) * (rank - 1))
	var txt: String = def.desc.format(vals)
	if def.type == "active":
		var t := dmg_type(sid)
		if not t.is_empty() and t[2] != "":
			txt += " Puissance +12 %% par vague, +4 %% par point de %s." % Db.stat_name(t[2]).to_lower()
		txt += "  (recharge %s s)" % vals.get("cd", "?")
	return txt


static func _fmt(v: float) -> String:
	if abs(v - round(v)) < 0.05:
		return str(int(round(v)))
	return ("%.1f" % v).replace(".", ",")

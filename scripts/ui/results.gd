extends Control
## Écran de fin de partie : statistiques, récompenses, dialogue de conclusion (campagne).

const DialogueBox := preload("res://scripts/ui/dialogue_box.gd")


func _ready() -> void:
	var r: Dictionary = Game.last_results
	var victory: bool = r.get("victory", false)
	var zone = Db.zone_of_mission(r.get("mission", ""))
	var bg: String = zone.get("background", "res://assets/backgrounds/titre.png") if r.get("mode", "") != "pvp" else "res://assets/backgrounds/pvp.png"
	Ui.screen_base(self, bg, 0.7)
	Audio.play_music("victoire" if victory else "defaite", 0.5, false)

	var reward = Profile.apply_run_rewards(r)
	Backend.report_run(r)

	var root := Ui.vbox(16)
	add_child(Ui.margin(root, 50))
	var title := "VICTOIRE !" if victory else "DÉFAITE…"
	if r.get("mode", "") == "pvp":
		title = "VOTRE ÉQUIPE A GAGNÉ !" if r.get("pvp_win", false) else "Match terminé : %s l'emporte" % r.get("pvp_winner_name", "?")
	elif r.get("mode", "") == "endless":
		title = "Survie terminée : vague %d" % r.get("waves", 0)
	root.add_child(Ui.title(title, 72, Ui.C_GOOD if victory or r.get("pvp_win", false) else Ui.C_ACCENT))
	var sub := _quip(r)
	if r.get("mode", "") == "pvp":
		sub = "Arène %dv%d contre %s — %s" % [r.get("team_size", 1), r.get("team_size", 1), Db.AI_LEVELS[int(r.get("ai_level", 1))].name, sub]
	else:
		sub = "Difficulté : %s (récompenses x%.2f) — %s" % [Db.DIFFICULTIES[int(r.get("difficulty", 1))].name, float(r.get("reward_mult", 1.0)), sub]
	var quip := Ui.label(sub, 22, Ui.C_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	root.add_child(quip)

	var body := Ui.hbox(30)
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	var sp := Ui.panel(24)
	sp.custom_minimum_size = Vector2(560, 0)
	body.add_child(sp)
	var sv := Ui.vbox(10)
	sp.add_child(sv)
	sv.add_child(Ui.label("Statistiques", 30, Ui.C_BORDER))
	for row in [["Vagues survécues", r.get("waves", 0)], ["Ennemis éliminés", r.get("kills", 0)], ["Boss vaincus", r.get("bosses", 0)],
			["Données ramassées", r.get("data", 0)], ["Niveaux gagnés", r.get("levels", 0)], ["Dégâts infligés", r.get("damage_dealt", 0)]]:
		var h := Ui.hbox(10)
		h.add_child(Ui.label(row[0], 22))
		h.add_child(Ui.spacer())
		h.add_child(Ui.label(str(row[1]), 22, Ui.C_GOLD))
		sv.add_child(h)
	if r.get("mode", "") == "pvp":
		var h2 := Ui.hbox(10)
		h2.add_child(Ui.label("Manches gagnées", 22))
		h2.add_child(Ui.spacer())
		h2.add_child(Ui.label(str(r.get("pvp_rounds", 0)), 22, Ui.C_GOLD))
		sv.add_child(h2)

	var rp := Ui.panel(24)
	rp.custom_minimum_size = Vector2(560, 0)
	body.add_child(rp)
	var rv := Ui.vbox(10)
	rp.add_child(rv)
	rv.add_child(Ui.label("Récompenses", 30, Ui.C_BORDER))
	rv.add_child(_reward_row("res://assets/sprites/ui/xp.png", "+%d XP de compte" % reward.account_xp))
	rv.add_child(_reward_row("res://assets/sprites/ui/titre.png", "+%d XP de battle pass" % reward.bp_xp))
	rv.add_child(_reward_row("res://assets/sprites/ui/puces.png", "+%d puces" % reward.puces))
	if reward.levels > 0:
		rv.add_child(_reward_row("res://assets/sprites/ui/point_competence.png", "Niveau %d atteint ! +%d point(s) de compétence" % [Profile.data.level, reward.levels], Ui.C_GOOD))
	if reward.tiers > 0:
		rv.add_child(_reward_row("res://assets/sprites/ui/neons.png", "+%d palier(s) de battle pass !" % reward.tiers, Ui.C_ACCENT))
	for c in reward.challenges:
		rv.add_child(Ui.label("✔ Défi : " + String(c.text).replace("{n}", str(int(c.n))), 18, Ui.C_GOOD))
	if reward.first_clear:
		rv.add_child(Ui.label("Première victoire sur cette mission !", 20, Ui.C_GOLD))
		var m = Db.mission(r.get("mission", ""))
		for cid in Db.characters:
			if Db.characters[cid].unlock == m.get("id", "#"):
				rv.add_child(Ui.label("Nouveau héros débloqué : " + Db.characters[cid].name + " !", 22, Ui.C_ACCENT))

	var cont := Ui.button("Continuer", func(): Game.leave_results(), 320, 28)
	cont.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	root.add_child(cont)
	cont.call_deferred("grab_focus")

	if reward.levels > 0 or reward.tiers > 0:
		Audio.play("palier")

	# Dialogue de conclusion (campagne, victoire)
	if victory and r.get("mode", "") == "campaign":
		var m2 = Db.mission(r.get("mission", ""))
		if m2.has("outro"):
			var d := DialogueBox.new()
			d.lines = m2.outro
			d.hero_id = Profile.data.character
			add_child(d)


func _reward_row(icon: String, text: String, col: Color = Ui.C_TEXT) -> Control:
	var h := Ui.hbox(12)
	h.add_child(Ui.icon(icon, 40))
	h.add_child(Ui.label(text, 22, col))
	return h


func _quip(r: Dictionary) -> String:
	if r.get("victory", false):
		return ["Mamie RAM vous envoie un bisou numérique.", "Le Noyau fait semblant de ne pas être vexé.", "Les bugs ont été corrigés. Pour l'instant."][randi() % 3]
	if r.get("mode", "") == "pvp":
		return "Bien joué, gladiateurs. Les robots du public ont adoré."
	return ["Avez-vous essayé de l'éteindre et de le rallumer ?", "Erreur 404 : victoire introuvable.", "Pas grave, on dira que c'était un test de charge."][randi() % 3]

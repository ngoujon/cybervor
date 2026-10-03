extends Node
## Écran « salon » d'un serveur dédié sans interface : attend les joueurs, journalise l'état.

var _t := 0.0


func _ready() -> void:
	print("[Serveur] Salon prêt. Joueurs connectés : %d" % Net.human_ids().size())


func _process(delta: float) -> void:
	_t += delta
	if _t > 30.0:
		_t = 0.0
		print("[Serveur] Salon : %d joueur(s), mode %s" % [Net.human_ids().size(), Net.lobby.mode])

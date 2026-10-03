class_name GuideContent
extends RefCounted
## Contenu du guide du jeu (menu d'accueil et menu Échap). Les textes de règles sont écrits ici ; les listes
## (armes, objets, statistiques, héros, ennemis) sont générées depuis les données pour rester à jour.
## Chaque section : {id, title, cat, text (BBCode)}.

const C_MELEE := "#ff8a5c"
const C_RANGED := "#ffd166"
const C_TECH := "#5ff7ff"
const C_SUPPORT := "#06ffa5"
const C_KEY := "#ffd166"

## Explication de chaque statistique (clé de data/stats.json).
const STAT_HELP := {
	"max_hp": "Points de vie maximum. À 0, vous êtes hors service.",
	"hp_regen": "Régénère des PV en continu : environ 0,12 PV par seconde par point.",
	"life_steal": "Chance (en %) de récupérer 1 PV à chaque coup porté. Excellent avec les armes qui tirent vite.",
	"damage": "Bonus en % appliqué à TOUS vos dégâts : armes de mêlée, à distance, techno, et sorts.",
	"melee": "Dégâts de mêlée : ajoute des dégâts aux armes de catégorie [color=#ff8a5c]Mêlée[/color] (lame, marteau, shuriken) et +4 % de puissance aux sorts de type Mêlée.",
	"ranged": "Dégâts à distance : ajoute des dégâts aux armes de catégorie [color=#ffd166]Distance[/color] (pistolets, mitrailleuse, railgun, roquettes) et +4 % de puissance aux sorts de type Distance.",
	"tech": "Dégâts techno : ajoute des dégâts aux armes de catégorie [color=#5ff7ff]Techno[/color] (bobine Tesla, orbes, lance-flammes, mines), aux drones et aux brûlures, et +4 % de puissance aux sorts de type Techno.",
	"attack_speed": "Vitesse d'attaque en % : réduit le temps entre deux tirs de toutes les armes.",
	"crit": "Chance (en %) qu'un coup soit critique. Un critique inflige ×2 (plus le bonus de Dégâts critiques).",
	"range": "Portée des armes. Les armes de mêlée ne profitent que de la moitié du bonus.",
	"armor": "Réduit les dégâts reçus : dégâts × 1 / (1 + armure / 15). 15 d'armure = dégâts divisés par 2. Une armure négative augmente les dégâts reçus.",
	"dodge": "Chance (en %) d'éviter complètement un coup.",
	"speed": "Vitesse de déplacement en %.",
	"luck": "Chance : objets plus rares en boutique et en montée de niveau, plus de coffres et de soins lâchés par les ennemis.",
	"harvest": "Récolte : données gagnées automatiquement à la fin de chaque vague.",
	"pickup": "Portée de ramassage : distance à laquelle les données et objets au sol sont attirés vers vous.",
	"xp_gain": "Bonus d'expérience en %.",
	"crit_dmg": "Ajoute des dégâts aux coups critiques (en %, en plus du ×2).",
	"knockback": "Recul infligé aux ennemis touchés (sauf les boss).",
	"projectiles": "Projectiles supplémentaires par tir (et orbes supplémentaires).",
	"pierce": "Nombre d'ennemis supplémentaires qu'un projectile traverse.",
	"explode_on_kill": "Chance (en %) qu'un ennemi vaincu explose et blesse ses voisins.",
	"burn_chance": "Chance (en %) d'enflammer l'ennemi touché : dégâts sur la durée, augmentés par vos Dégâts techno.",
	"drones": "Drones d'appui qui tournent autour de vous et tirent dans la direction visée (dégâts techno).",
	"chain": "Rebonds supplémentaires des éclairs en chaîne.",
	"shield": "Boucliers : chacun bloque entièrement un coup, rechargés à chaque vague.",
	"revive": "Sauvegardes automatiques : vous revenez avec 50 % de vos PV au lieu d'être mis hors service.",
	"dash": "Réduit la recharge de l'esquive (−30 % par point).",
	"shop_discount": "Réduction (en %) sur les prix de la boutique.",
	"data_gain": "Bonus (en %) sur les données ramassées.",
	"ranged_mult": "Multiplicateur des dégâts des armes à distance (ex. Brutus : −30 %).",
	"extra_choice": "Choix supplémentaires proposés à chaque montée de niveau.",
	"start_data": "Données supplémentaires au début de la partie.",
	"free_reroll": "Relances gratuites de la boutique à chaque vague.",
	"thorns": "Épines : inflige ces dégâts à l'ennemi qui vous touche au corps à corps.",
	"boss_damage": "Bonus de dégâts (en %) contre les boss.",
}

const AI_TEXT := {
	"chase": "fonce sur le joueur le plus proche",
	"ranged": "garde ses distances et tire des projectiles",
	"exploder": "court vers vous et explose au contact",
	"healer": "soigne les ennemis autour de lui : à abattre en priorité",
	"dasher": "creuse sous terre puis surgit en chargeant",
	"turret": "reste immobile et tire en cercle",
	"phantom": "se téléporte près de vous",
	"boss": "boss : motifs d'attaque variés, enrage à la moitié de ses PV",
}

const CLASS_NAMES := {"melee": "Mêlée", "ranged": "Distance", "tech": "Techno"}
const CLASS_COLORS := {"melee": C_MELEE, "ranged": C_RANGED, "tech": C_TECH}


static func key(k: String) -> String:
	return "[color=%s][b]%s[/b][/color]" % [C_KEY, k]


static func sections() -> Array:
	var s: Array = []
	s.append({"id": "principe", "cat": "Bases", "title": "Le principe du jeu", "text": """Cybervor est un [b]survivor d'arène[/b] : des hordes de bugs et de virus arrivent par [b]vagues[/b], et il faut survivre jusqu'à la fin du chrono de chaque vague.

[b]Pendant une vague[/b] : vous vous déplacez, vous esquivez, et vos [b]armes tirent toutes seules dans la direction de votre curseur[/b] dès qu'un ennemi est à portée. Vous lancez vos [b]sorts[/b] (touches 1 à 5) vers le curseur. Les ennemis vaincus lâchent des [b]données[/b] (la monnaie du jeu) et de l'expérience.

[b]Entre deux vagues[/b] : la [b]boutique[/b] s'ouvre. Achetez des armes (jusqu'à 6), des objets qui augmentent vos statistiques, et des armes actives qui ajoutent des sorts à votre barre de raccourcis. Quand vous êtes prêt, cliquez sur « Prêt ! Vague suivante ».

[b]Objectif[/b] : en campagne, tenir toutes les vagues de la mission (la dernière cache souvent un boss) ; en survie, tenir le plus longtemps possible ; en arène PvP, gagner 3 manches contre l'équipe adverse."""})
	s.append({"id": "commandes", "cat": "Bases", "title": "Commandes", "text": """[b]Clavier et souris[/b]
• Se déplacer : %s ou %s ou les flèches
• Viser : [b]la souris[/b] (les armes et les sorts partent vers le curseur)
• Esquive : %s
• Sorts de la barre de raccourcis : %s à %s
• Pause / menu : %s — Chat (multijoueur) : %s
• Signaler un bug : %s — Amis et messages : %s

[b]Manette[/b]
• Se déplacer : stick gauche — Viser : [b]stick droit[/b] (la dernière direction est gardée quand vous le relâchez)
• Esquive et sorts : selon vos réglages — Pause : Start — LB / RB : changer d'onglet dans les menus

Toutes les touches de l'esquive et des sorts se règlent dans [b]Paramètres › Commandes[/b], y compris sur les boutons de la souris et de la manette.""" % [key("ZQSD"), key("WASD"), key("Espace"), key("1"), key("5"), key("Échap"), key("Entrée"), key("F1"), key("F2")]})
	s.append({"id": "visee", "cat": "Bases", "title": "Viser : tout part vers le curseur", "text": """Il n'y a [b]pas de visée automatique[/b] : c'est vous qui choisissez la direction.

• [b]Armes[/b] : elles tirent automatiquement (vous n'avez pas à cliquer), mais [b]toujours dans la direction du curseur[/b] (ou du stick droit). Elles ne tirent que lorsqu'un adversaire se trouve à portée, pour ne pas gaspiller vos tirs.
• [b]Éclairs en chaîne[/b] (bobine Tesla) : frappent l'ennemi le plus proche [b]dans un cône[/b] devant votre curseur, puis rebondissent.
• [b]Mines[/b] : sont lancées devant vous, dans la direction visée.
• [b]Orbes[/b] : tournent autour de vous et blessent tout ce qu'elles touchent (elles ne visent pas).
• [b]Sorts[/b] : se lancent vers le point visé (zones, frappes, lasers, salves…). Les lasers et frappes demandent de viser précisément.
• [b]Lancement automatique des sorts[/b] (option du menu Paramètres › Jeu) : les sorts partent dès qu'ils sont prêts, toujours vers votre curseur."""})
	s.append({"id": "degats", "cat": "Combat", "title": "Les types de dégâts (Mêlée, Distance, Techno)", "text": """Chaque arme et chaque sort actif appartient à une [b]catégorie de dégâts[/b]. Il y en a trois, plus le Soutien :

[color=%s][b]Mêlée[/b][/color] — lames, marteau, shuriken : coups au corps à corps ou à courte portée. Profite de la statistique [b]Dégâts de mêlée[/b]. Les armes de mêlée ne profitent que de la moitié des bonus de Portée.
[color=%s][b]Distance[/b][/color] — pistolets, mitrailleuse, pompe, railgun, roquettes : projectiles à longue portée. Profite de [b]Dégâts à distance[/b].
[color=%s][b]Techno[/b][/color] — bobine Tesla, orbes, lance-flammes, mines, drones, brûlures : énergie et gadgets. Profite de [b]Dégâts techno[/b].
[color=%s][b]Soutien[/b][/color] — sorts de soin, de bouclier, de renforts ou de bonus : ils n'infligent pas de dégâts.

[b]Comment sont calculés les dégâts d'une arme ?[/b]
1. On part des [b]dégâts de base[/b] de l'arme (selon son rang I à IV).
2. On ajoute les points de la statistique de sa catégorie, multipliés par le coefficient de l'arme. Exemple : le Pistolaser a un coefficient de ×1,0 en Dégâts à distance → avec 5 points de Dégâts à distance, il gagne +5 dégâts par tir. Certaines armes mélangent deux catégories (le shuriken : mêlée ×0,6 et distance ×0,4).
3. Le tout est multiplié par la statistique [b]Dégâts %%[/b] (qui compte pour toutes les catégories).
4. Coup critique (chance = Coups critiques %%) : ×2, plus les Dégâts critiques.

[b]Exemple[/b] : Pistolaser rang I (8 dégâts), 5 Dégâts à distance, +20 %% de Dégâts → (8 + 5) × 1,2 = [b]15,6 dégâts[/b] par tir.

[b]Et les sorts actifs ?[/b] Leur puissance augmente de [b]+4 %% par point[/b] de la statistique de leur type, de [b]+12 %% par vague[/b] écoulée, et profite aussi de Dégâts %%.

[b]Conseil[/b] : spécialisez-vous ! Si vos armes sont surtout à distance, achetez les objets qui donnent des Dégâts à distance. Le type de chaque arme est affiché dans la boutique (« Distance — Dégâts 13 — Cadence… ») et le type de chaque sort sur sa carte et dans l'infobulle de la barre de raccourcis.""" % [C_MELEE, C_RANGED, C_TECH, C_SUPPORT]})
	s.append({"id": "armes", "cat": "Combat", "title": "Armes : rangs, fusion et liste", "text": _weapons_text()})
	s.append({"id": "sorts", "cat": "Combat", "title": "Sorts actifs et bonus passifs", "text": """Dans la boutique, certaines offres ne sont pas des armes classiques :

• [b]Arme active / Objet actif[/b] : ajoute un [b]sort[/b] dans votre [b]barre de raccourcis[/b] (5 emplacements, touches 1 à 5). Le sort se lance vers le curseur, puis se recharge (le temps restant s'affiche sur la case). Les objets actifs communs (Canon laser, Railgun d'épaule, Rayon cryo, Frappe orbitale, Grenade IEM, Mini trou noir) sont accessibles à tous les héros.
• [b]Arme passive[/b] : un [b]bonus permanent[/b] (statistiques, aura, effet périodique). Les passifs possédés s'affichent à droite de l'écran.

[b]Rangs[/b] : racheter un sort que vous possédez déjà le fait monter de rang (★2, ★3…), ce qui augmente ses effets.
[b]Barre pleine[/b] : avec 5 sorts actifs, il faut en revendre un (bouton « Vendre ») pour en acheter un nouveau. Les flèches ◀ ▶ réorganisent la barre.
[b]Infobulles[/b] : survolez un sort de la barre ou un passif à droite pour voir sa description, son type de dégâts, sa touche et sa recharge.
[b]Esquive[/b] (Espace) : propre à chaque héros (roulade, téléportation, charge…), invulnérable pendant un court instant."""})
	s.append({"id": "boutique", "cat": "Progression", "title": "Boutique, données et revente", "text": """Les [b]données[/b] (cristaux bleus) sont la monnaie de la partie. On les gagne en ramassant ce que lâchent les ennemis, et grâce à la [b]Récolte[/b] en fin de vague. En coop, les données ramassées sont partagées entre tous les joueurs.

• Chaque vague, la boutique propose de nouvelles offres. [b]Relancer[/b] remplace les offres contre quelques données (le prix augmente à chaque relance).
• Les prix augmentent au fil des vagues ; les premières boutiques sont moins chères, et il y a toujours au moins une offre abordable (en [b]PROMO[/b] si besoin).
• [b]Revendre[/b] une arme ou un sort rend environ 35 % de son prix : le montant est indiqué sur le bouton (« Vendre +7 »).
• [b]Rareté[/b] : Commun, [color=#4cc9f0]Rare[/color], [color=#c77dff]Épique[/color], [color=#ffb703]Légendaire[/color]. Les objets rares deviennent plus fréquents au fil des vagues et avec la Chance.
• [b]Objets[/b] : ils s'additionnent (en posséder deux exemplaires double leur effet)."""})
	s.append({"id": "niveaux", "cat": "Progression", "title": "Expérience et montée de niveau", "text": """Les ennemis vaincus donnent de l'expérience. À chaque niveau gagné pendant une vague, vous choisirez une [b]amélioration de statistique[/b] au début de l'entracte (avant la boutique). Sa valeur dépend de sa rareté (Commun à Légendaire), plus fréquente avec la Chance.

Le [b]niveau de compte[/b] (menu principal) est différent : il monte avec toutes vos parties et donne des [b]points de compétence[/b] pour les arbres de compétences."""})
	s.append({"id": "stats", "cat": "Combat", "title": "Toutes les statistiques", "text": _stats_text()})
	s.append({"id": "objets", "cat": "Progression", "title": "Liste des objets", "text": _items_text()})
	s.append({"id": "heros", "cat": "Bases", "title": "Les héros", "text": _heroes_text()})
	s.append({"id": "ennemis", "cat": "Combat", "title": "Ennemis et boss", "text": _enemies_text()})
	s.append({"id": "arenes", "cat": "Combat", "title": "Arènes, failles et obstacles", "text": """Chaque partie génère une [b]arène différente[/b] : côtes découpées, lobes, baies, presqu'îles… Au-delà du bord et dans les [b]failles[/b] du sol, c'est le vide : on ne peut pas y marcher.

• Les [b]projectiles passent au-dessus[/b] du vide : on peut tirer par-dessus une faille.
• Les esquives de type [b]téléportation[/b] permettent de franchir une faille.
• Les ennemis contournent les failles : profitez-en pour les faire tourner autour.
• Il reste toujours assez de place pour circuler partout, même pour un boss.
• En arène PvP, la carte est symétrique pour que les deux équipes soient à égalité."""})
	s.append({"id": "modes", "cat": "Modes", "title": "Modes de jeu et difficulté", "text": _modes_text()})
	s.append({"id": "competences", "cat": "Progression", "title": "Compétences, battle pass et récompenses", "text": """• [b]Arbres de compétences[/b] (menu principal) : 5 arbres — Assaut, Blindage, Technologie, Piratage, Récolte. Les points viennent du niveau de compte ; les bonus s'appliquent à toutes vos parties. Une réinitialisation est possible contre des puces.
• [b]Battle pass « Surtension »[/b] : 40 paliers de récompenses (chapeaux, couleurs, titres, puces, néons). Les défis quotidiens et hebdomadaires font progresser plus vite.
• [b]Monnaies[/b] : [color=#ffd166]puces[/color] (récompenses de partie) et [color=#ff5fd2]néons[/color] (récompenses du battle pass).
• Les héros se débloquent en terminant les zones de la campagne."""})
	s.append({"id": "multi", "cat": "Modes", "title": "Multijoueur, salons et sauvegarde", "text": """• [b]Multijoueur › Créer une partie[/b] : crée un salon en ligne (Coopération ou Arène PvP) que les autres joueurs voient dans « Parties ouvertes » et peuvent rejoindre.
• [b]Réseau local (LAN)[/b] : héberger sur votre PC et donner votre adresse IP à vos amis.
• Tout le monde doit avoir [b]la même version[/b] du jeu : le jeu se met à jour automatiquement au lancement, et vous propose la mise à jour si une nouvelle version sort pendant que vous jouez.
• [b]Sauvegarde cloud[/b] : votre progression est synchronisée en ligne. Hors ligne, le jeu garde vos progrès et les renvoie à la reconnexion. Votre [b]code de sauvegarde[/b] (Profil) permet de retrouver votre progression sur un autre PC — gardez-le secret.
• [b]Social[/b] : amis par code ami, messagerie, chat d'équipe en jeu (Entrée)."""})
	s.append({"id": "astuces", "cat": "Bases", "title": "Astuces", "text": """• Restez en mouvement : la plupart des ennemis vous foncent dessus.
• Visez les [b]Méduses-soin[/b] en premier : elles soignent les autres ennemis.
• Les [b]Kamikazes[/b] explosent au contact : esquivez-les ou abattez-les de loin.
• Spécialisez vos armes dans une catégorie (Mêlée, Distance ou Techno) pour que vos objets de dégâts profitent à toutes.
• 15 points d'armure divisent les dégâts reçus par deux : très efficace contre les boss.
• La Récolte rapporte des données à chaque vague : investir tôt est rentable.
• Les failles sont vos alliées : mettez-en une entre vous et la horde, vos tirs passent au-dessus."""})
	return s


static func _weapons_text() -> String:
	var t := """[b]Rangs[/b] : I, II, III, IV (plus le rang est élevé, plus les dégâts sont forts et la cadence rapide).
[b]Fusion[/b] : achetez une arme que vous avez déjà, au même rang : les deux fusionnent en une arme du rang supérieur.
[b]Limite[/b] : 6 armes. Elles flottent autour de vous sur des drones et tirent vers votre curseur.

"""
	for wid in Db.weapons:
		var d: Dictionary = Db.weapons[wid]
		if not d is Dictionary or not d.has("damage"):
			continue
		var cls: String = d.get("class", "ranged")
		var sc := []
		for k in d.get("scale", {}):
			sc.append("×%s %s" % [str(snapped(float(d.scale[k]), 0.1)).replace(".", ","), String(Db.stats.get(k, {}).get("name", k))])
		var dmg := []
		for v in d.damage:
			dmg.append(str(v))
		t += "[color=%s][b]%s[/b][/color] — [color=%s]%s[/color] — dégâts %s (rangs I à IV) — bonus : %s\n%s\n\n" % [
			Ui.C_TEXT.to_html(false), d.get("name", wid), CLASS_COLORS.get(cls, C_RANGED), CLASS_NAMES.get(cls, cls),
			" / ".join(dmg), ", ".join(sc), d.get("desc", "")]
	return t.strip_edges()


static func _stats_text() -> String:
	var t := ""
	for k in Db.stats:
		if k == "_doc" or not Db.stats[k] is Dictionary:
			continue
		t += "[b]%s[/b] : %s\n" % [Db.stats[k].get("name", k), STAT_HELP.get(k, "")]
	return t.strip_edges()


static func _items_text() -> String:
	var t := "Les objets s'achètent en boutique et s'additionnent.\n\n"
	for iid in Db.items:
		var d = Db.items[iid]
		if not d is Dictionary:
			continue
		var fx := []
		for k in d.get("stats", {}):
			var v: float = float(d.stats[k])
			fx.append("%s%s %s" % ["+" if v >= 0 else "", str(v).trim_suffix(".0"), String(Db.stats.get(k, {}).get("name", k))])
		var r: int = int(d.get("rarity", 0))
		t += "[color=#%s][b]%s[/b][/color] (%s) : %s — [i]%s[/i]\n" % [Db.RARITY_COLORS[r].to_html(false), d.get("name", iid), Db.RARITY_NAMES[r], ", ".join(fx), d.get("desc", "")]
	return t.strip_edges()


static func _heroes_text() -> String:
	var t := "Chaque héros a ses bonus, son arme de départ, son esquive et son propre arbre de sorts en boutique.\n\n"
	for cid in Db.characters:
		var c: Dictionary = Db.characters[cid]
		var wname: String = Db.weapons.get(c.get("weapon", ""), {}).get("name", "")
		var dodge: Dictionary = Db.spells.dodges.get(cid, {})
		var unlock: String = "disponible dès le départ" if String(c.get("unlock", "")) == "" else "se débloque en campagne"
		t += "[b]%s[/b] — %s\n%s\nArme de départ : %s — Esquive : %s — %s\n\n" % [c.name, c.desc, c.passive, wname, dodge.get("name", ""), unlock]
	return t.strip_edges()


static func _enemies_text() -> String:
	var t := "Les ennemis deviennent plus résistants à chaque vague. Des [b]élites[/b] (plus gros, plus forts) apparaissent dans les vagues avancées.\n\n"
	var bosses := ""
	for eid in Db.enemies:
		var e = Db.enemies[eid]
		if not e is Dictionary or eid == "trojan_mini":
			continue
		var line := "[b]%s[/b] : %s.\n" % [e.get("name", eid), AI_TEXT.get(e.get("ai", ""), "")]
		if e.get("ai", "") == "boss":
			bosses += line
		else:
			t += line
	if eid_has_split():
		t += "[b]Cheval de Troie[/b] : se divise en Mini-Troies quand il est détruit.\n"
	return (t + "\n[b]Boss[/b] (fin de chaque zone de campagne, et toutes les 5 vagues en survie) :\n" + bosses).strip_edges()


static func eid_has_split() -> bool:
	return Db.enemies.get("trojan", {}).has("split")


static func _modes_text() -> String:
	var t := """[b]Campagne[/b] : 5 zones de 4 missions, avec dialogues. Jouable en solo ou en coop (jusqu'à 4).
[b]Survie infinie[/b] : vagues sans fin, un boss toutes les 5 vagues.
[b]Arène PvP[/b] : équipes de 1v1 à 4v4, contre des joueurs et/ou des IA. Premier à 3 manches.

[b]Difficulté[/b] (campagne et survie) :
"""
	for d in Db.DIFFICULTIES:
		t += "• [b]%s[/b] : PV des ennemis ×%s, dégâts ×%s, récompenses ×%s — %s\n" % [d.name, str(d.hp).replace(".", ","), str(d.dmg).replace(".", ","), str(d.reward).replace(".", ","), d.desc]
	t += "\n[b]Niveaux de l'IA[/b] (arène) : "
	var names := []
	for a in Db.AI_LEVELS:
		names.append(a.name)
	return t + ", ".join(names) + "."

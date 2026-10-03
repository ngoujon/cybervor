extends Node
## Mise à jour automatique du jeu (version Windows exportée).
##  - au lancement : l'écran « update » cherche une nouvelle version, la télécharge, l'installe et relance le jeu ;
##  - jeu déjà ouvert : vérification toutes les 5 minutes ; la mise à jour est proposée au joueur, jamais
##    pendant une partie ou dans un salon (elle attend son retour au menu). « Plus tard » : elle s'installera
##    toute seule au prochain lancement.
## Manifeste publié avec le site : <url du serveur>/version.json
##   {"version": "0.2.0", "file": "Cybervor.zip", "size": 70934346, "sha256": "…", "notes": ["…"]}
## Remplacement de l'exe : Windows interdit d'écraser un exe en cours d'exécution mais autorise de le renommer :
## Cybervor.exe -> Cybervor.exe.old (supprimé au lancement suivant), puis Cybervor.exe.new -> Cybervor.exe.

signal update_found(info: Dictionary)

const CHECK_EVERY := 300.0
const DOWNLOAD_DIR := "user://maj"
const EXE_IN_ZIP := "Cybervor/Cybervor.exe"
## Écrans où l'on ne dérange pas le joueur (partie, salon multijoueur, choix du héros avant une partie).
const BUSY_SCREENS := ["world", "lobby", "character_select", "results", "update", "server", ""]

var current: String = str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
var latest: Dictionary = {}
var installed := ""    # version téléchargée et installée, active au prochain lancement
var _declined := ""    # version pour laquelle le joueur a répondu « Plus tard »
var _waiting_menu := false
var _timer: Timer


func _ready() -> void:
	if OS.get_name() == "Windows" and OS.has_feature("template"):
		var old := OS.get_executable_path() + ".old"
		if FileAccess.file_exists(old):
			DirAccess.remove_absolute(old)   # ancienne version, remplacée au lancement précédent


## Mise à jour possible : jeu exporté pour Windows, serveur configuré, hors outils de test.
func enabled() -> bool:
	if OS.get_environment("CYBERVOR_UPDATE_URL") != "" and OS.has_feature("template"):
		return not Profile.sandbox
	return OS.get_name() == "Windows" and OS.has_feature("template") and not OS.has_feature("dedicated_server") \
		and manifest_url() != "" and not Profile.sandbox


func manifest_url() -> String:
	if OS.get_environment("CYBERVOR_UPDATE_URL") != "":
		return OS.get_environment("CYBERVOR_UPDATE_URL")
	return Backend.base_url + "/version.json" if Backend.base_url != "" else ""


## Lance la vérification périodique (appelée une fois le menu principal atteint).
func start_watch() -> void:
	if _timer or not enabled():
		return
	_timer = Timer.new()
	_timer.wait_time = float(OS.get_environment("CYBERVOR_UPDATE_EVERY")) if OS.get_environment("CYBERVOR_UPDATE_EVERY") != "" else CHECK_EVERY
	_timer.autostart = true
	_timer.timeout.connect(_periodic)
	add_child(_timer)
	Game.screen_changed.connect(func(_s):
		if _waiting_menu and not is_busy():
			_waiting_menu = false
			_propose.call_deferred())
	print("[MAJ] version %s, vérification toutes les %d s" % [current, int(_timer.wait_time)])
	if _test_dir() != "" and OS.get_environment("CYBERVOR_UPDATE_TEST_GAME") == "1":
		_test_in_game()


static func is_newer(a: String, b: String) -> bool:
	var pa := a.split(".")
	var pb := b.split(".")
	for i in maxi(pa.size(), pb.size()):
		var x := int(pa[i]) if i < pa.size() else 0
		var y := int(pb[i]) if i < pb.size() else 0
		if x != y:
			return x > y
	return false


func is_busy() -> bool:
	return Game.current_screen in BUSY_SCREENS or Net.is_online()


## Interroge le manifeste. Renvoie les infos de la nouvelle version, ou {} si le jeu est à jour.
func check() -> Dictionary:
	if manifest_url() == "":
		return {}
	var http := HTTPRequest.new()
	http.timeout = 6.0
	add_child(http)
	var sep := "&" if "?" in manifest_url() else "?"
	if http.request(manifest_url() + sep + "t=%d" % Time.get_unix_time_from_system()) != OK:
		http.queue_free()
		return {}
	var res: Array = await http.request_completed
	http.queue_free()
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
		return {}
	var info = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	if not (info is Dictionary) or not info.has("version") or not info.has("file"):
		return {}
	var v := String(info.version)
	if not is_newer(v, current) or (installed != "" and not is_newer(v, installed)):
		return {}
	latest = info
	return info


func _periodic() -> void:
	var info := await check()
	if info.is_empty() or String(info.version) == _declined:
		return
	update_found.emit(info)
	if is_busy():
		_waiting_menu = true   # proposée dès le retour au menu, sans interrompre la partie
	else:
		_propose()


func _propose() -> void:
	if latest.is_empty() or Ui.modal_open():
		_waiting_menu = not latest.is_empty()
		return
	var notes: Array = latest.get("notes", [])
	var txt := "La version %s de Cybervor est disponible (vous avez la %s)." % [latest.version, current]
	if not notes.is_empty():
		txt += "\n\n" + "\n".join(notes.slice(0, 5).map(func(n): return "• " + str(n)))
	txt += "\n\nLe téléchargement prend environ une minute, puis le jeu redémarre. Votre progression est conservée."
	print("[MAJ] proposition de la version %s (écran : %s)" % [latest.version, Game.current_screen])
	var dlg := Ui.confirm("Mise à jour disponible !", txt, "Mettre à jour", func():
		Profile.save()
		Game.goto("update", {"info": latest}), "Plus tard", func():
		_declined = String(latest.version)
		Ui.toast("Elle s'installera automatiquement au prochain lancement.", Ui.C_MUTED, 3.5))
	if _test_dir() != "":
		_test_accept(dlg)


## Télécharge et installe la version décrite par info. progress(fraction 0..1, texte).
## Renvoie "" si tout s'est bien passé, sinon le message d'erreur.
func install(info: Dictionary, progress: Callable) -> String:
	var exe := OS.get_executable_path()
	var dir := exe.get_base_dir()
	DirAccess.make_dir_recursive_absolute(DOWNLOAD_DIR)
	var zip_path := ProjectSettings.globalize_path(DOWNLOAD_DIR + "/Cybervor.zip")
	# --- téléchargement
	var url := String(info.file)
	if not url.begins_with("http"):
		url = manifest_url().get_base_dir() + "/" + url
	var http := HTTPRequest.new()
	http.download_file = zip_path
	http.timeout = 0.0
	add_child(http)
	if http.request(url) != OK:
		http.queue_free()
		return "Impossible de lancer le téléchargement."
	var done := []
	http.request_completed.connect(func(r, code, _h, _b): done.append([r, code]))
	var total := float(info.get("size", 0))
	while done.is_empty():
		var got := http.get_downloaded_bytes()
		var tot := total if total > 0 else float(maxi(http.get_body_size(), 1))
		progress.call(clampf(got / tot, 0.0, 1.0) * 0.85, "Téléchargement… %.1f / %.1f Mo" % [got / 1048576.0, tot / 1048576.0])
		await get_tree().create_timer(0.1).timeout
	http.queue_free()
	if done[0][0] != HTTPRequest.RESULT_SUCCESS or done[0][1] != 200:
		return "Téléchargement interrompu (code %d). Vérifiez votre connexion." % done[0][1]
	# --- vérification de l'intégrité
	progress.call(0.87, "Vérification du fichier…")
	await get_tree().process_frame
	if info.has("sha256") and _sha256(zip_path) != String(info.sha256).to_lower():
		DirAccess.remove_absolute(zip_path)
		return "Le fichier téléchargé est corrompu. Réessayez dans un instant."
	# --- extraction
	progress.call(0.9, "Installation…")
	await get_tree().process_frame
	var zr := ZIPReader.new()
	if zr.open(zip_path) != OK:
		return "Archive de mise à jour illisible."
	var files := zr.get_files()
	if not EXE_IN_ZIP in files:
		zr.close()
		return "Archive de mise à jour incomplète."
	var new_exe := exe + ".new"
	var f := FileAccess.open(new_exe, FileAccess.WRITE)
	if f == null:
		zr.close()
		return "Impossible d'écrire dans le dossier du jeu (%s). Téléchargez la nouvelle version depuis le site." % dir
	f.store_buffer(zr.read_file(EXE_IN_ZIP))
	f.close()
	for path in files:   # fichiers d'accompagnement (LISEZMOI, icône…)
		if path == EXE_IN_ZIP or path.ends_with("/") or not path.begins_with("Cybervor/"):
			continue
		var out := FileAccess.open(dir + "/" + path.trim_prefix("Cybervor/"), FileAccess.WRITE)
		if out:
			out.store_buffer(zr.read_file(path))
			out.close()
	zr.close()
	DirAccess.remove_absolute(zip_path)
	# --- remplacement de l'exe (renommage : autorisé même pendant l'exécution)
	progress.call(0.97, "Remplacement de l'ancienne version…")
	if FileAccess.file_exists(exe + ".old"):
		DirAccess.remove_absolute(exe + ".old")
	if DirAccess.rename_absolute(exe, exe + ".old") != OK:
		DirAccess.remove_absolute(new_exe)
		return "Impossible de remplacer le jeu (fichier verrouillé ?)."
	if DirAccess.rename_absolute(new_exe, exe) != OK:
		DirAccess.rename_absolute(exe + ".old", exe)   # retour arrière
		return "Impossible d'installer la nouvelle version."
	installed = String(info.version)
	progress.call(1.0, "Mise à jour %s installée !" % info.version)
	return ""


func _sha256(path: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	while f.get_position() < f.get_length():
		ctx.update(f.get_buffer(1 << 20))
	return ctx.finish().hex_encode()


## Relance le jeu (la nouvelle version) et ferme celui-ci.
func restart() -> void:
	Settings.save_settings()
	OS.create_process(OS.get_executable_path(), OS.get_cmdline_args())
	get_tree().quit()


# ------------------------------------------------------------------ test de bout en bout (variables d'environnement)
## CYBERVOR_UPDATE_TEST=<dossier> : captures d'écran + acceptation automatique de la proposition.
## CYBERVOR_UPDATE_TEST_GAME=1 : lance une partie (pilotée par l'IA) pour vérifier qu'elle n'est pas interrompue.
func _test_dir() -> String:
	return OS.get_environment("CYBERVOR_UPDATE_TEST")


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_test_dir() + "/" + file)
	print("[MAJ] capture ", file)


func _test_accept(dlg: Control) -> void:
	await get_tree().create_timer(2.0).timeout
	await _shot("proposition_%s.png" % latest.version)
	if is_instance_valid(dlg):
		for b in dlg.find_children("*", "Button", true, false):
			if b.text == "Mettre à jour":
				print("[MAJ] test : clic sur « Mettre à jour »")
				b.pressed.emit()


func _test_in_game() -> void:
	await get_tree().create_timer(1.0).timeout
	Game.autotest = true
	Net.start_solo("endless")
	Net.lobby.mode = "endless"
	Game.server_start_session(Net.lobby.duplicate(true))
	print("[MAJ] test : partie lancée")
	await get_tree().create_timer(float(_timer.wait_time) * 2.0 + 6.0).timeout
	print("[MAJ] test : toujours en partie après la détection (écran %s, fenêtre ouverte : %s)" % [Game.current_screen, Ui.modal_open()])
	await _shot("en_partie.png")
	Game.autotest = false
	Engine.time_scale = 1.0
	Game.goto("main_menu")

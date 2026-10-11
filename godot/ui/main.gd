## The playable game: runs Rogue in a TerminalView.
##
## The environment is the real one: user name, time and pid (the dungeon
## seed), ROGUEOPTS (from the environment or --rogueopts=...). The "home"
## directory, where saved games and the score file live, is Godot's user data
## folder. Like `rogue -r`, a saved game there is restored at startup (and the
## save file is deleted). Closing the window during a game saves it, as the
## original does on SIGHUP.
##
## Command line (after --): --rogueopts=OPTS, --master (wizard-capable build),
## and Rogue's own arguments (-s, -d, a save file name).
extends Control

@onready var view: TerminalView = $TerminalView
var cs: Curses = null
var _running := false
var _closing := false


func _ready() -> void:
	get_tree().set_auto_accept_quit(false)
	view.key_pressed.connect(_on_key)
	_start()


func _start() -> void:
	RogueBase.reset()
	cs = Curses.new()
	RogueBase.cs = cs
	_setup_env()
	view.cs = cs
	cs.program_exited.connect(_on_exit)
	_running = true
	_play()


func _play() -> void:
	await Main.main()
	_on_exit(0)	# main() never returns in C; just in case


func _setup_env() -> void:
	var data := OS.get_user_data_dir()
	var name := ""
	for v in ["USER", "USERNAME", "LOGNAME"]:
		if name == "":
			name = OS.get_environment(v)
	RogueBase.env_name = name if name != "" else "rodney"
	RogueBase.env_home = data + "/"
	RogueBase.env_cwd = data
	RogueBase.env_scorefile = data + "/rogue.scr"
	RogueBase.env_lockfile = data + "/rogue.lck"
	RogueBase.env_time = int(Time.get_unix_time_from_system())
	RogueBase.env_pid = OS.get_process_id()
	RogueBase.env_uid = 1000
	RogueBase.env_sandbox = false

	var opts: Variant = null
	if OS.has_environment("ROGUEOPTS"):
		opts = OS.get_environment("ROGUEOPTS")
	var args := PackedStringArray(["rogue"])
	RogueBase.MASTER = false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--rogueopts="):
			opts = a.substr(len("--rogueopts="))
		elif a == "--master":
			RogueBase.MASTER = true
		else:
			args.append(a)
	if args.size() == 1 and FileAccess.file_exists(data + "/rogue.save"):
		args.append("-r")
	RogueBase.env_rogueopts = opts
	RogueBase.argv = args


func _on_key(code: int) -> void:
	if _running:
		cs.push_key(code)
	elif code == 13 or code == 10:
		cs.abandon()
		_start()
	elif code == 27 or code == ord("q"):
		get_tree().quit()


func _on_exit(_status: int) -> void:
	if not _running:
		return
	_running = false
	if _closing:
		get_tree().quit()
		return
	if not cs.curses_gone and not cs.isendwin():
		cs.endwin()
	cs.stdout_write("\n\n[Press Enter for a new game, Esc to quit]")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_closing = true
		_close()


## auto_save() a game in progress (not one that is ending), then quit.
func _close() -> void:
	if _running and not cs.curses_gone and not cs.isendwin() and RogueBase.pstats.s_hpt > 0:
		await Save.auto_save(0)	# exits: _on_exit quits
	get_tree().quit()

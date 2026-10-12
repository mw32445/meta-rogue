## The playable game: runs Rogue in a TerminalView.
##
## The environment is the real one: user name, time and pid (the dungeon
## seed), ROGUEOPTS (from the environment or --rogueopts=...). The "home"
## directory, where saved games and the score file live, is Godot's user data
## folder. Like `rogue -r`, a saved game there is restored at startup (and the
## save file is deleted). Closing the window during a game saves it, as the
## original does on SIGHUP.
##
## The playable game turns the gameplay switches on (RogueBase.fixes, .guild and
## .menus, docs/CHANGES.md): the known bugs are fixed, item commands list their
## items at once, and before every new game the Fighters' Guild (godot/guild,
## docs/GUILD.md) outfits the hero from the Hall of Fame's coffers (20 entries).
##
## Command line (after --): --rogueopts=OPTS, --master (wizard-capable build),
## --classic (the original game: no fixes, no Guild, and its own save and score
## files in the "classic" folder of the user data folder), --no-guild (no Guild
## screen: new games start with the issued kit), --windowed / --fullscreen (the
## display mode for this run, not saved), and Rogue's own arguments (-s, -d, a save
## file name).
##
## The window follows the video settings (VideoSettings, user://video.cfg; the
## first launch detects the screen and goes borderless fullscreen at its
## resolution). F10 opens OPTIONS - VIDEO (SettingsScreen) over whatever is shown;
## the game waits for its next key meanwhile. Alt+Enter switches between windowed
## and fullscreen.
extends Control

## Tests: start new games without the Guild screen (set before instantiate()).
static var skip_guild := false
## Tests: the video settings file, or "" to leave the window as it is (no settings
## are read, applied at startup or saved). Set before instantiate().
static var video_path := VideoSettings.PATH

@onready var view: TerminalView = $TerminalView
var cs: Curses = null
var _running := false
var _closing := false
## The Guild screen while it is open (it gets the keys), else null.
var _guild: GuildScreen = null
var _no_guild := false
var _data := ""
var video: VideoSettings
## The video settings screen while it is open (it gets the keys first), else null,
## and the screen it covers (the game's, the Guild's, or the end-of-game console).
var _settings: SettingsScreen = null
var _covered: Curses = null


func _ready() -> void:
	get_tree().set_auto_accept_quit(false)
	view.key_pressed.connect(_on_key)
	view.settings_requested.connect(_on_settings_key)
	view.fullscreen_toggled.connect(_on_fullscreen_key)
	_setup_video()
	_start()


## The video settings: the saved ones (on first launch the detected ones), with
## --windowed or --fullscreen for this run only.
func _setup_video() -> void:
	if video_path == "":
		video = VideoSettings.from_window(get_window())
		return
	video = VideoSettings.open(video_path, get_window())
	for a in OS.get_cmdline_user_args():
		if a == "--windowed":
			video.mode = VideoSettings.WINDOWED
		elif a == "--fullscreen" and video.mode == VideoSettings.WINDOWED:
			video.mode = VideoSettings.FULLSCREEN
	video.apply(get_window())


## A new run: a saved game is restored, a new game first visits the Guild.
func _start() -> void:
	_setup_env()
	if _guild_opens():
		_guild = GuildScreen.new(RogueBase.env_scorefile)
		_guild.descended.connect(_on_descend)
		view.cs = _guild.cs
		return
	_begin(null)


## The Guild opens before a new game (not a restore, -s or -d) in guild mode.
func _guild_opens() -> bool:
	return RogueBase.guild and not skip_guild and not _no_guild and RogueBase.argv.size() == 1


func _on_descend(lo: Dictionary) -> void:
	_guild = null
	_begin(lo)


## Start the game, with the Guild's purchases (or null).
func _begin(lo: Variant) -> void:
	RogueBase.reset()
	cs = Curses.new()
	RogueBase.cs = cs
	RogueBase.loadout = lo
	view.cs = cs
	cs.program_exited.connect(_on_exit)
	_running = true
	_play()


func _play() -> void:
	await Main.main()
	_on_exit(0)	# main() never returns in C; just in case


func _setup_env() -> void:
	var classic := false
	_no_guild = false
	for a in OS.get_cmdline_user_args():
		if a == "--classic":
			classic = true
		elif a == "--no-guild":
			_no_guild = true
	RogueBase.fixes = not classic
	RogueBase.guild = not classic
	RogueBase.menus = not classic
	RogueBase.exp_next = not classic
	_data = OS.get_user_data_dir()
	if classic:
		_data = _data.path_join("classic")
		DirAccess.make_dir_recursive_absolute(_data)
	var data := _data
	var user_name := ""
	for v in ["USER", "USERNAME", "LOGNAME"]:
		if user_name == "":
			user_name = OS.get_environment(v)
	RogueBase.env_name = user_name if user_name != "" else "rodney"
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
		elif not a.begins_with("--"):	# other --options belong to test scripts
			args.append(a)
	if args.size() == 1 and FileAccess.file_exists(data + "/rogue.save"):
		args.append("-r")
	RogueBase.env_rogueopts = opts
	RogueBase.argv = args


func _on_key(code: int) -> void:
	if _settings != null:
		_settings.key(code)
	elif _guild != null:
		_guild.key(code)
	elif _running:
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
	if _guild_next():
		var gold := HallOfFame.read_file(RogueBase.env_scorefile).coffers()
		cs.stdout_write("\n\nThe Guild's coffers now hold %d gold. [Enter: the Guild, Esc: quit]" % gold)
	else:
		cs.stdout_write("\n\n[Press Enter for a new game, Esc to quit]")


## Whether Enter will open the Guild: guild mode, a new game next (no Rogue
## arguments, no saved game).
func _guild_next() -> bool:
	if not RogueBase.guild or skip_guild or _no_guild:
		return false
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			return false
	return not FileAccess.file_exists(_data + "/rogue.save")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_closing = true
		_close()


## auto_save() a game in progress (not one that is ending), then quit. During the
## Guild there is nothing to save.
func _close() -> void:
	if _running and not cs.curses_gone and not cs.isendwin() and RogueBase.pstats.s_hpt > 0:
		await Save.auto_save(0)	# exits: _on_exit quits
	get_tree().quit()


# ---- video settings -------------------------------------------------------------

## F10: open OPTIONS - VIDEO over whatever is shown, or close it.
func _on_settings_key() -> void:
	if _settings != null:
		_close_settings()
		return
	_covered = view.cs
	video.sync(get_window())
	_settings = SettingsScreen.new(video, VideoSettings.screens(true))
	_settings.changed.connect(_on_video_changed)
	_settings.closed.connect(_close_settings)
	view.cs = _settings.cs


## Back to the screen it covered (redrawn whole); a game resumes with its next key.
func _close_settings() -> void:
	_settings = null
	view.cs = _covered
	_covered = null


func _on_video_changed() -> void:
	video.apply(get_window())
	video.save()


## Alt+Enter: windowed <-> fullscreen (on the window's monitor), saved.
func _on_fullscreen_key() -> void:
	video.sync(get_window())
	video.toggle_fullscreen()
	_on_video_changed()
	if _settings != null:
		_settings.draw()

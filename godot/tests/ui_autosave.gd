## UI test of auto-save and restore: plays a few keys, closes the window (the game
## must save itself), then starts again (the save must be restored and deleted).
## Needs a display (e.g. xvfb-run):
##   xvfb-run -s "-screen 0 1280x800x24" godot --path godot --script res://tests/ui_autosave.gd
## Prints "ui_autosave: OK" or "ui_autosave: FAILED ...". Uses (and cleans) the
## project's user data folder.
extends SceneTree

var _main: Node
var _frame := 0
var _phase := 0
var _save := ""
var _hero := Vector2i()


func _initialize() -> void:
	_save = OS.get_user_data_dir() + "/rogue.save"
	if FileAccess.file_exists(_save):
		DirAccess.remove_absolute(_save)
	_start()


func _start() -> void:
	load("res://ui/main.gd").skip_guild = true	# a new game starts at once
	load("res://ui/main.gd").video_path = ""	# the window as it is: no video settings
	_main = load("res://main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _phase == 0:
		if _frame == 10:
			for c in "lljj":
				RogueBase.cs.push_key(c.unicode_at(0))
		elif _frame == 20:
			_hero = Vector2i(RogueBase.hero.x, RogueBase.hero.y)
			# what closing the window does (main.gd's _close() then quits the app)
			Save.auto_save(0)
		elif _frame == 25:
			if not FileAccess.file_exists(_save):
				print("ui_autosave: FAILED: no save file after closing")
				quit(1)
				return false
			# start again in a fresh scene: the game must be restored
			_main.queue_free()
			_phase = 1
			_frame = 0
	elif _phase == 1:
		if _frame == 2:
			_start()
		elif _frame == 15:
			var ok := Vector2i(RogueBase.hero.x, RogueBase.hero.y) == _hero \
				and not FileAccess.file_exists(_save) \
				and RogueBase.curscr.get_cell(0, 0) & 0xFF == ord("F")	# "File name: ..."
			print("ui_autosave: OK" if ok else "ui_autosave: FAILED: hero %s vs %s, save left: %s" % [
				Vector2i(RogueBase.hero.x, RogueBase.hero.y), _hero, FileAccess.file_exists(_save)])
			quit(0 if ok else 1)
	return false

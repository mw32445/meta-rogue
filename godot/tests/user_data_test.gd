## Tests of the user data folder (ui/user_data.gd): Meta-Rogue's own folder, and the
## one-time copy of the player's files from the folder of the game's earlier name.
##   godot --headless --path godot --script res://tests/user_data_test.gd
## Prints one line per failed check and a summary; exit status 1 on any failure.
extends SceneTree

var _passed := 0
var _failed := 0
var _dir := ""


func _initialize() -> void:
	_dir = OS.get_user_data_dir().path_join("user_data_test")
	_remove(_dir)
	DirAccess.make_dir_recursive_absolute(_dir)
	_test_folder()
	_test_migrate()
	_test_not_twice()
	_test_nothing_old()
	_remove(_dir)
	print("user_data_test: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _check(what: String, ok: bool, detail: Variant = "") -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		print("FAIL %s %s" % [what, str(detail)])


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _remove(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for d in DirAccess.get_directories_at(path):
		_remove(path.path_join(d))
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	DirAccess.remove_absolute(path)


## The project's folder is Meta-Rogue's own, not Godot's app_userdata one.
func _test_folder() -> void:
	var u := OS.get_user_data_dir()
	_check("folder: Meta-Rogue's own", u.get_file() == "Meta-Rogue" and not u.contains("app_userdata")
		and ProjectSettings.get_setting("application/config/name") == "Meta-Rogue", u)
	for d in UserData.old_dirs():
		_check("folder: an old folder found exists and is named Rogue", DirAccess.dir_exists_absolute(d)
			and d.ends_with("app_userdata/Rogue"), d)


## An old folder like a player's: its files and its classic folder are copied; the
## lock, Godot's folders and the tests' are not; the old folder is left as it was.
func _test_migrate() -> void:
	var old := _dir.path_join("old")
	var files := {"rogue.scr": "scores", "rogue.save": "a game", "video.cfg": "[video]",
		"guild_prices.txt": "[coffers]", "mysave": "another game", "classic/rogue.scr": "classic scores",
		"classic/rogue.save": "a classic game"}
	for f in files:
		_write(old.path_join(f), files[f])
	_write(old.path_join("rogue.lck"), "")
	_write(old.path_join("logs/godot.log"), "log")
	_write(old.path_join("shader_cache/x"), "cache")
	_write(old.path_join("fixes_test/rogue.scr"), "a test's")
	var new := _dir.path_join("new")
	_write(new.path_join("logs/godot.log"), "this run's log")	# Godot makes it at startup
	var n := UserData.migrate([_dir.path_join("none"), old] as Array[String], new)
	var same := true
	for f in files:
		same = same and FileAccess.get_file_as_string(new.path_join(f)) == files[f]
	_check("migrate: the player's files, classic ones too", n == files.size() and same, n)
	_check("migrate: not the lock, nor Godot's or the tests' folders",
		not FileAccess.file_exists(new.path_join("rogue.lck"))
		and not DirAccess.dir_exists_absolute(new.path_join("shader_cache"))
		and not DirAccess.dir_exists_absolute(new.path_join("fixes_test"))
		and FileAccess.get_file_as_string(new.path_join("logs/godot.log")) == "this run's log")
	var kept := FileAccess.file_exists(old.path_join("rogue.lck"))
	for f in files:
		kept = kept and FileAccess.get_file_as_string(old.path_join(f)) == files[f]
	_check("migrate: the old folder is left as it was", kept)


## Once the new folder has the player's files, nothing is copied again.
func _test_not_twice() -> void:
	var old := _dir.path_join("old")
	var new := _dir.path_join("new")
	_write(old.path_join("rogue.scr"), "newer scores in the old folder")
	_check("again: nothing copied over the new folder's files", UserData.migrate([old] as Array[String], new) == 0
		and FileAccess.get_file_as_string(new.path_join("rogue.scr")) == "scores")
	var only_classic := _dir.path_join("only_classic")
	_write(only_classic.path_join("classic/rogue.scr"), "mine")
	_check("again: a classic folder alone counts as the player's",
		UserData.migrate([old] as Array[String], only_classic) == 0
		and not FileAccess.file_exists(only_classic.path_join("rogue.scr")))
	var with_cfg := _dir.path_join("with_cfg")
	_write(with_cfg.path_join("video.cfg"), "[video]")
	_check("again: video.cfg alone counts as the player's", UserData.migrate([old] as Array[String], with_cfg) == 0)


## No old folder: nothing happens; a missing new folder is made.
func _test_nothing_old() -> void:
	var new := _dir.path_join("fresh")
	_check("no old folder: nothing copied", UserData.migrate([_dir.path_join("none")] as Array[String], new) == 0
		and not DirAccess.dir_exists_absolute(new))
	var old := _dir.path_join("old")
	_check("a new folder that does not exist yet is made", UserData.migrate([old] as Array[String], new) > 0
		and FileAccess.file_exists(new.path_join("rogue.scr")))

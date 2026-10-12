## The player's data folder (user://), where the saved games, the score file (with the
## Hall of Fame), video.cfg and maybe guild_prices.txt live. project.godot gives
## Meta-Rogue a folder of its own (application/config/use_custom_user_dir):
##   Windows  %APPDATA%\Meta-Rogue
##   macOS    ~/Library/Application Support/Meta-Rogue
##   Linux    ~/.local/share/Meta-Rogue
## Before it was called Meta-Rogue, the game was a project named "Rogue" in Godot's
## default folder, <data folder>/godot/app_userdata/Rogue ("Godot" on Windows and
## macOS). The first start of Meta-Rogue copies the player's files from there
## (migrate()); the old folder is left as it is.
class_name UserData
extends RefCounted

## The project name the game had before Meta-Rogue.
const OLD_NAME := "Rogue"
## Files of the old folder that are not the player's: the score file's lock.
const SKIP: Array[String] = ["rogue.lck"]


## The folder where the game kept its data when it was named "Rogue", if it exists
## on this computer (at most one: "godot" and "Godot" are the same folder where
## names ignore case).
static func old_dirs() -> Array[String]:
	var out: Array[String] = []
	for g in ["godot", "Godot"]:
		var d := OS.get_data_dir().path_join(g).path_join("app_userdata").path_join(OLD_NAME)
		if out.is_empty() and DirAccess.dir_exists_absolute(d):
			out.append(d)
	return out


## Copy the player's files from the first folder of old that exists into new_dir,
## when new_dir holds none yet: the files at its top (saved games, rogue.scr,
## video.cfg, guild_prices.txt; not SKIP) and those of its "classic" folder (the
## files of --classic). Folders that Godot or the tests make (logs, caches) are not
## copied. Returns the number of files copied.
static func migrate(old: Array[String], new_dir: String) -> int:
	if DirAccess.dir_exists_absolute(new_dir) and (not DirAccess.get_files_at(new_dir).is_empty()
			or DirAccess.dir_exists_absolute(new_dir.path_join("classic"))):
		return 0
	for o in old:
		if DirAccess.dir_exists_absolute(o):
			var n := _copy_files(o, new_dir)
			if DirAccess.dir_exists_absolute(o.path_join("classic")):
				n += _copy_files(o.path_join("classic"), new_dir.path_join("classic"))
			return n
	return 0


## Copy the files at the top of from_dir (not SKIP) into to_dir, made if need be.
static func _copy_files(from_dir: String, to_dir: String) -> int:
	DirAccess.make_dir_recursive_absolute(to_dir)
	var n := 0
	for f in DirAccess.get_files_at(from_dir):
		if not SKIP.has(f) and DirAccess.copy_absolute(from_dir.path_join(f), to_dir.path_join(f)) == OK:
			n += 1
	return n

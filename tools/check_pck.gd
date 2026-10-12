## Check the game data of an exported Meta-Rogue, loaded with --main-pack (a .pck, or
## an executable with the .pck embedded):
##   - the project's name and version are NAME and VERSION;
##   - guild_prices.txt is there and reads without errors;
##   - every game script (each .gd under the source folder SRC, outside tests/) is
##     there and compiles, and the tests are not there.
##   godot --headless --main-pack PCK --script "$PWD/tools/check_pck.gd" -- \
##       --src=/abs/godot --name=Meta-Rogue --version=1.0.0
## Prints "check_pck: OK (N scripts)" or one line per failure; exit status 1 on any.
## tools/check_export.py runs it.
extends SceneTree

var _failed := 0


func _initialize() -> void:
	var o := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			o[a.substr(2, a.find("=") - 2)] = a.substr(a.find("=") + 1)
	_expect("name", ProjectSettings.get_setting("application/config/name"), o.get("name"))
	_expect("version", ProjectSettings.get_setting("application/config/version"), o.get("version"))
	var shipped := "res://guild_prices.txt"
	if not FileAccess.file_exists(shipped):
		_fail("no guild_prices.txt in the game data")
	else:
		var p: GuildPrices = GuildPrices.from_file(shipped)
		if not p.errors.is_empty():
			_fail("guild_prices.txt: %s" % p.errors[0])
	var scripts := _scripts(String(o.get("src", "")), "")
	if scripts.is_empty():
		_fail("no scripts found in --src=%s" % o.get("src", ""))
	for s in scripts:
		var res := "res://" + s
		if not ResourceLoader.exists(res):
			_fail("missing " + res)
			continue
		var sc := load(res) as Script
		if sc == null or not sc.can_instantiate():
			_fail("does not compile: " + res)
	for t in ["res://tests/replay.gd", "res://tests/guild_test.gd"]:
		if ResourceLoader.exists(t):
			_fail("a test is in the game data: " + t)
	if _failed == 0:
		print("check_pck: OK (%d scripts)" % scripts.size())
	quit(1 if _failed > 0 else 0)


func _expect(what: String, got: Variant, want: Variant) -> void:
	if str(got) != str(want):
		_fail("%s is '%s', not '%s'" % [what, got, want])


func _fail(why: String) -> void:
	_failed += 1
	print("check_pck: FAIL " + why)


## The .gd files under src/rel, as paths relative to src, without tests/ and dot
## folders.
func _scripts(src: String, rel: String) -> Array[String]:
	var out: Array[String] = []
	var d := src.path_join(rel)
	for f in DirAccess.get_files_at(d):
		if f.ends_with(".gd"):
			out.append(rel.path_join(f) if rel != "" else f)
	for sub in DirAccess.get_directories_at(d):
		if not sub.begins_with(".") and not (rel == "" and sub == "tests"):
			out.append_array(_scripts(src, rel.path_join(sub) if rel != "" else sub))
	return out

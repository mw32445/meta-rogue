## Write Godot Engine's licence, its third-party components and their licences, as
## compiled into this Godot binary (Engine.get_license_text, get_copyright_info,
## get_license_info): the notices a game made with Godot must ship. tools/export.sh
## puts them in each download's LICENSES.txt.
##   godot --headless --path godot --script "$PWD/tools/godot_licenses.gd" -- --out=FILE
extends SceneTree


func _initialize() -> void:
	var path := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			path = a.substr(len("--out="))
	var out := PackedStringArray()
	out.append(Engine.get_license_text().strip_edges())
	out.append("")
	out.append("Godot Engine includes the following third-party components.")
	for c in Engine.get_copyright_info():
		out.append("")
		out.append("- " + c.name)
		for p in c.parts:
			for who in p.copyright:
				out.append("  Copyright " + who)
			out.append("  License: " + p.license)
	var texts := Engine.get_license_info()
	for k in texts:
		out.append("")
		out.append("---- License: %s ----" % k)
		out.append("")
		out.append(String(texts[k]).strip_edges())
	var f := FileAccess.open(path, FileAccess.WRITE) if path != "" else null
	if f == null:
		printerr("godot_licenses: give --out=FILE (a file that can be written)")
		quit(1)
		return
	f.store_string("\n".join(out) + "\n")
	f.close()
	quit(0)

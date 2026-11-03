@tool
extends RefCounted

## Builds the shipped min-version index from Godot's extension_api dumps.
##
## Diffs every full `extension_api_*.json` in the dev-only source_dir() in ascending
## version order and writes one compact `api_min_version.json`: each class / member /
## global mapped to its earliest Godot version, plus an `inherits` map for hierarchy walks.
## Re-run when dumps change: `preload("res://addons/gdpackage/src/editor_plugins/console_command/min_version/extract_api.gd").build()`

const UtilsRemote = preload("res://addons/gdpackage/src/class/utils_remote.gd")

const UFile = UtilsRemote.UFile

const ExportIgnore = preload("uid://c4pt5djyuf8c") #! resolve GDPackageSpec.ExportIgnore

const OUTPUT_PATH := "res://addons/gdpackage/src/editor_plugins/console_command/min_version/extension_api/api_min_version.json"


## The dumps folder inside gdpackage's own _export_ignore/ (or export_ignore/).
static func source_dir() -> String:
	return ExportIgnore.dir_or_default("res://addons/gdpackage").path_join("extension_api/")


## Build the merged index. Returns the output path (empty on failure).
static func build() -> String:
	# Discover every extension_api_*.json dump and read its version from the
	# header (authoritative, major-agnostic), ascending by version.
	var source := source_dir()
	var dumps := []  # [{path:String, version:String}]
	for file_name in DirAccess.get_files_at(source):
		if not (file_name.begins_with("extension_api_") and file_name.ends_with(".json")):
			continue
		var path := source.path_join(file_name)
		var data: Dictionary = UFile.read_from_json(path)
		var header: Dictionary = data.get("header", {})
		if not header.has("version_minor"):
			printerr("extract_api: no header version in ", path)
			continue
		var version := "%d.%d" % [int(header.get("version_major", 4)), int(header.get("version_minor"))]
		dumps.append({"path": path, "version": version})
	if dumps.is_empty():
		printerr("extract_api: no extension_api_*.json dumps in ", source)
		return ""
	dumps.sort_custom(func(a, b): return _version_code(a["version"]) < _version_code(b["version"]))

	var classes := {}       # name -> earliest version
	var members := {}       # class -> { member -> earliest version }
	var utils := {}         # utility fn -> earliest version
	var global_enums := {}  # enum value name -> earliest version
	var inherits := {}      # class -> parent (newest dump wins)

	for entry in dumps:
		var v: String = entry["version"]
		var data: Dictionary = UFile.read_from_json(entry["path"])
		if data.is_empty():
			printerr("extract_api: could not read ", entry["path"])
			continue

		var all_classes: Array = data.get("classes", []) + data.get("builtin_classes", [])
		for c: Dictionary in all_classes:
			var name: String = c.get("name", "")
			if name == "":
				continue
			if not classes.has(name):
				classes[name] = v
			inherits[name] = c.get("inherits", "")
			var md: Dictionary = members.get(name, {})
			_collect_members(c, md, v)
			members[name] = md

		for fn: Dictionary in data.get("utility_functions", []):
			var fname: String = fn.get("name", "")
			if fname != "" and not utils.has(fname):
				utils[fname] = v
		for en: Dictionary in data.get("global_enums", []):
			for val: Dictionary in en.get("values", []):
				var vname: String = val.get("name", "")
				if vname != "" and not global_enums.has(vname):
					global_enums[vname] = v

	var version_list := []
	for entry in dumps:
		version_list.append(entry["version"])

	var index := {
		"versions": version_list,
		"classes": classes,
		"members": members,
		"utils": utils,
		"global_enums": global_enums,
		"inherits": inherits,
	}

	var f := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if f == null:
		printerr("extract_api: could not open for write ", OUTPUT_PATH)
		return ""
	f.store_string(JSON.stringify(index))
	f.close()

	var member_total := 0
	for c in members:
		member_total += (members[c] as Dictionary).size()
	print("extract_api: wrote ", OUTPUT_PATH, " — ", classes.size(), " classes, ",
		member_total, " members, ", utils.size(), " utils, ",
		global_enums.size(), " global enum values (versions ",
		dumps[0]["version"], "..", dumps[-1]["version"], ")")
	return OUTPUT_PATH


## Ordering key for a "major.minor" version string (major*1000+minor).
static func _version_code(v: String) -> int:
	var parts := v.split(".")
	if parts.size() >= 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
		return int(parts[0]) * 1000 + int(parts[1])
	return -1


## Add a class dict's own members to `md`, keeping the earliest version seen.
static func _collect_members(c: Dictionary, md: Dictionary, v: String) -> void:
	for key in ["methods", "properties", "signals", "constants"]:
		for m: Dictionary in c.get(key, []):
			var name: String = m.get("name", "")
			if name != "" and not md.has(name):
				md[name] = v
	for e: Dictionary in c.get("enums", []):
		var ename: String = e.get("name", "")
		if ename != "" and not md.has(ename):
			md[ename] = v
		for val: Dictionary in e.get("values", []):
			var vname: String = val.get("name", "")
			if vname != "" and not md.has(vname):
				md[vname] = v

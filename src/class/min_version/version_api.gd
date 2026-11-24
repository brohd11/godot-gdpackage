extends RefCounted

## Version oracle for the min_version checker.
##
## Loads the single merged `extension_api/api_min_version.json` produced by
## `extract_api.gd` and answers "what is the earliest Godot version that contains
## this class / member / global?". An empty string means "not in any dump" —
## treated by callers as user-defined / unknown and skipped.

const UtilsRemote = preload("res://addons/gdpackage/src/class/utils_remote.gd")
const UFile = UtilsRemote.UFile

## Lowest version the index covers; findings at/below it don't raise the floor.
## Derived from the index's baked "versions" list (fallback if the index lacks it).
var baseline := "4.0"

var _index := {}
var _loaded := false


func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var path: String = get_script().resource_path.get_base_dir().path_join("extension_api/api_min_version.json")
	if FileAccess.file_exists(path):
		_index = UFile.read_from_json(path)
		var versions: Array = _index.get("versions", [])
		if not versions.is_empty():
			baseline = versions[0]


func has_index() -> bool:
	_ensure_loaded()
	return not _index.is_empty()


func has_class(name: String) -> bool:
	_ensure_loaded()
	return (_index.get("classes", {}) as Dictionary).has(name)


func is_global_utility(name: String) -> bool:
	_ensure_loaded()
	return (_index.get("utils", {}) as Dictionary).has(name)


func class_min_version(name: String) -> String:
	_ensure_loaded()
	return (_index.get("classes", {}) as Dictionary).get(name, "")


func utility_min_version(name: String) -> String:
	_ensure_loaded()
	return (_index.get("utils", {}) as Dictionary).get(name, "")


func global_enum_min_version(name: String) -> String:
	_ensure_loaded()
	return (_index.get("global_enums", {}) as Dictionary).get(name, "")


## Earliest version `member` appears on `class_nm` or any ancestor (walking the
## `inherits` chain). "" if not found anywhere.
func member_min_version(class_nm: String, member: String) -> String:
	_ensure_loaded()
	var members: Dictionary = _index.get("members", {})
	var inherits: Dictionary = _index.get("inherits", {})
	var current := class_nm
	var guard := 0
	while current != "" and guard < 64:
		var own: Dictionary = members.get(current, {})
		if own.has(member):
			return own[member]
		current = inherits.get(current, "")
		guard += 1
	return ""


## Ordering key for a "major.minor" version string (major*1000+minor), so 4.7 <
## 4.8 < 4.10 < 5.0 with no version table. -1 when unparseable.
static func version_code(v: String) -> int:
	var parts := v.split(".")
	if parts.size() >= 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
		return int(parts[0]) * 1000 + int(parts[1])
	return -1


static func max_version(a: String, b: String) -> String:
	if a == "":
		return b
	if b == "":
		return a
	return a if version_code(a) >= version_code(b) else b

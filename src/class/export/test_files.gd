extends RefCounted
## Classifies separate GDScript tests without loading them: release workspaces may not contain
## their frameworks. Cache inheritance so shared test bases are read once per scan.

const StringMap = preload("uid://btml0a8r6vbbn") #! resolve UtilR.Strings.StringMap
const FRAMEWORK_CLASSES = ["GutTest", "GdUnitTestSuite"]
const FRAMEWORK_PATHS = ["/addons/gut/test.gd", "/addons/gdUnit4/src/GdUnitTestSuite.gd"]

var class_paths:Dictionary = {}
var _headers:Dictionary = {}
var _frameworks:Dictionary = {}


func index_classes(files:Array) -> void:
	_frameworks.clear()
	for path:String in files:
		if path.get_extension() != "gd":
			continue
		var header = _header(path)
		if header.name != "":
			class_paths[header.name] = path


func is_test(path:String) -> bool:
	return path.ends_with("_test.gd") or is_framework_test(path)


func is_framework_test(path:String) -> bool:
	if path.get_extension() != "gd":
		return false
	if _frameworks.has(path):
		return _frameworks[path]
	_frameworks[path] = false # also breaks cyclic custom inheritance
	if FRAMEWORK_PATHS.any(func(base): return path.ends_with(base)):
		_frameworks[path] = true
		return true
	var header = _header(path)
	if header.base in FRAMEWORK_CLASSES:
		_frameworks[path] = true
		return true
	var parent:String = header.path
	if parent == "":
		parent = class_paths.get(header.base, "")
	elif parent.begins_with("uid://"):
		var id = ResourceUID.text_to_id(parent)
		parent = ResourceUID.get_id_path(id) if ResourceUID.has_id(id) else ""
	elif parent.is_relative_path():
		parent = path.get_base_dir().path_join(parent).simplify_path()
	_frameworks[path] = parent != "" and is_framework_test(parent)
	return _frameworks[path]


func _header(path:String) -> Dictionary:
	if _headers.has(path):
		return _headers[path]
	var header = {"name": "", "base": "", "path": ""}
	_headers[path] = header
	if not FileAccess.file_exists(path):
		return header
	var text = FileAccess.get_file_as_string(path)
	var map = StringMap.new(text, StringMap.Mode.STRING)
	var names = RegEx.new()
	names.compile(r"(?m)^class_name[\t ]+([A-Za-z_]\w*)")
	for found in names.search_all(text):
		if not map.index_in_string_or_comment(found.get_start()):
			header.name = found.get_string(1)
			break
	var bases = RegEx.new()
	bases.compile("(?m)^(?:extends[\\t ]+|class_name[\\t ]+[A-Za-z_]\\w*[\\t ]+extends[\\t ]+)([\"']([^\"'\\n]+)[\"']|[A-Za-z_]\\w*)")
	for found in bases.search_all(text):
		if map.index_in_string_or_comment(found.get_start()):
			continue
		header.path = found.get_string(2)
		if header.path == "":
			header.base = found.get_string(1)
		break
	return header

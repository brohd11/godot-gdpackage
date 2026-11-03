extends "res://addons/gdpackage/src/class/export/parse/parse_base.gd"

const CAST_STRIP_NAMES = [
	"PE_STRIP_CAST_SCRIPT",
	"ScriptListManager"
]

const STRIP_CAST_TAG = "#! strip-cast"

var _cast_strip_names = []

var _cast_strip_callables = []

func _init() -> void:
	pass


func set_parse_settings(settings):
	# Copied: what follows appends to this list, and the settings dictionary belongs to the caller.
	_cast_strip_names = settings.get("strip_cast", []).duplicate()
	for nm in CAST_STRIP_NAMES:
		if not nm in _cast_strip_names:
			_cast_strip_names.append(nm)
	
	for file in ExportFileUtils.get_global_singleton_module_scripts():
		var script = load(file) as GDScript
		var global_name = script.get_global_name()
		if global_name != "" and not global_name in _cast_strip_names:
			_cast_strip_names.append(global_name)
	
	for _class_name in _cast_strip_names:
		_build_single_regex(_class_name, _cast_strip_callables)

func get_direct_dependencies(_file_path:String) -> Dictionary:
	var dependencies = {} 
	return dependencies

func pre_export() -> void:
	pass

func post_export_edit_file(_file_path:String, file_lines:Variant=null) -> Variant:
	var local_strip_callables = []
	for i:int in file_lines.size():
		var line:String = file_lines[i]
		if line.begins_with(STRIP_CAST_TAG):
			var names_str = line.get_slice(STRIP_CAST_TAG, 1)
			names_str = names_str.get_slice("#", 0)
			if not names_str.contains(","):
				_build_single_regex(names_str.strip_edges(), local_strip_callables)
			else:
				var names = names_str.split(",")
				for n in names:
					_build_single_regex(n.strip_edges(), local_strip_callables)
			#print("MADE CALLS::", local_strip_callables)
			continue
		
		for callable in _cast_strip_callables:
			line = _string_safe_regex_sub(line, callable)
		for callable in local_strip_callables:
			line = _string_safe_regex_sub(line, callable)
		file_lines[i] = line
	
	return file_lines

func post_export_edit_line(line:String) -> String:
	return line


func _build_single_regex(strip_name:String, collection:Array):
	#var strip_pattern = r"\s*(?:->|:)\s*%s(\.\w+)*\b\s*" % _class_name
	# new pattern handles "as" too
	var strip_pattern = r"(?:\s*(?:->|:)\s*|\s+as\s+)%s(\.\w+)*\b" % strip_name
	var regex = RegEx.new()
	regex.compile(strip_pattern)
	var anon = func(line:String) -> String:
		return regex.sub(line, "", true)
	
	collection.append(anon)

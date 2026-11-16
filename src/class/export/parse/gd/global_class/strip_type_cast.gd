extends "res://addons/gdpackage/src/class/export/parse/parse_base.gd"

var _cast_strip_names = []

var _cast_strip_callables = []

func _init() -> void:
	pass


func set_parse_settings(settings):
	# Copied: what follows appends to this list, and the settings dictionary belongs to the caller.
	_cast_strip_names = settings.get("strip_cast", []).duplicate()
	
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
	# `#! gdp-strip-cast A, B` covers the whole file, wherever the tag sits.
	var tag = "#! " + DependencyTags.STRIP_CAST
	var local_strip_callables = []
	for line:String in file_lines:
		if not line.begins_with(tag):
			continue
		for n in line.get_slice(tag, 1).get_slice("#", 0).split(",", false):
			if n.strip_edges() != "":
				_build_single_regex(n.strip_edges(), local_strip_callables)
	
	for i:int in file_lines.size():
		var line:String = file_lines[i]
		if line.begins_with(tag):
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
	# a type is never called, which keeps `{0:Singleton.method()}` intact. Possessive because it
	# would otherwise back off to `:Singleton` and pass the lookahead on the dot.
	var strip_pattern = r"(?:\s*(?:->|:)\s*|\s+as\s+)%s(?:\.\w+)*+\b(?!\s*\()" % strip_name
	var regex = RegEx.new()
	regex.compile(strip_pattern)
	var anon = func(line:String) -> String:
		return regex.sub(line, "", true)
	
	collection.append(anon)

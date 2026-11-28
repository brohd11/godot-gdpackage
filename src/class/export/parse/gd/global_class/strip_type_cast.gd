extends "res://addons/gdpackage/src/class/export/parse/parse_base.gd"

var _cast_strip_names = []

var _cast_strip_callables = []

func _init() -> void:
	pass


func set_parse_settings(_settings):
	_cast_strip_names = []

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
	var local_names = []
	for line:String in file_lines:
		if not line.begins_with(tag):
			continue
		for n in line.get_slice(tag, 1).get_slice("#", 0).split(",", false):
			if n.strip_edges() != "":
				local_names.append(n.strip_edges())
				_build_single_regex(n.strip_edges(), local_strip_callables)
	for n in _reduced_names(_cast_strip_names + local_names):
		_build_single_regex(n, local_strip_callables)

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


## reduce_access_paths has already rewritten `Head.Inner` to a binding (`Head_Inner`, or a const
## in scope), which the head's regex can't match, so the rewritten names are stripped too.
func _reduced_names(heads:Array) -> Array:
	var names = []
	if not export_obj.reduce_access_paths:
		return names
	var plan:Dictionary = export_obj.access_reductions.get(_content_path(), {})
	for expression:String in plan:
		var entry:Dictionary = plan[expression]
		if entry.get("literal", false) or not expression.get_slice(".", 0) in heads:
			continue
		# parse_gd writes whichever of the two is already in scope; both name the same type
		for n in [entry.name, export_obj.access_bindings.get(expression)]:
			if n != null and not n in names and not n in heads:
				names.append(n)
	return names


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

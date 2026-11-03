extends "res://addons/gdpackage/src/class/export/parse/parse_base.gd"

const REPLACEMENT_TEXT = 'Engine.get_singleton(&"EditorInterface")'

var _ei_regex:= RegEx.new()
var string_regex:RegEx

var _replace_editor_interface:=false

func _init() -> void:
	string_regex = URegex.get_strings()
	
	var ei_pattern = "\\bEditorInterface\\b"
	_ei_regex.compile(ei_pattern)

func set_parse_settings(settings):
	_replace_editor_interface = settings.get("replace_editor_interface", false)

func get_direct_dependencies(file_path:String) -> Dictionary:
	var dependencies = {} 
	return dependencies

func pre_export() -> void:
	pass


func post_export_edit_file(file_path:String, file_lines:Variant=null) -> Variant:
	return file_lines

func post_export_edit_line(line:String) -> String:
	if _replace_editor_interface:
		line = replace_editor_interface(line)
	return line


func replace_editor_interface(line: String) -> String:
	#if line.strip_edges() == "ei = EditorInterface":
		#return line #^ should be fine to replace
	
	var processor = func(code: String):
		return _ei_regex.sub(code, REPLACEMENT_TEXT, true)
	return URegex.string_safe_regex_sub(line, processor, string_regex)

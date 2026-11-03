extends "res://addons/gdpackage/src/class/export/parse/parse_base.gd"



func _init() -> void:
	pass

func set_parse_settings(_settings:Dictionary) -> void:
	pass

func get_direct_dependencies(_file_path:String) -> Dictionary:
	var dependencies:Dictionary = {}
	return dependencies

func pre_export() -> void:
	pass


func post_export_edit_file(_file_path:String, file_lines:Variant=null) -> Variant:
	return file_lines

func post_export_edit_line(line:String) -> String:
	var stripped:String = line.strip_edges()
	if stripped.begins_with("print_deb(") or stripped.begins_with("print_deb_err("):
		var print_idx:int = line.find("print_deb")
		line = line.insert(print_idx, "pass # ")
	return line

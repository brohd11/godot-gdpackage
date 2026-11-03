extends "res://addons/gdpackage/src/class/export/parse/parse_base.gd"

var backport_target:= 100

func set_parse_settings(settings):
	backport_target = settings.get("backport_target", 100)


func get_direct_dependencies(file_path:String) -> Dictionary:
	var dependencies = {} 
	return dependencies

func pre_export() -> void:
	pass

func post_export_edit_file(file_path:String, file_lines:Variant=null) -> Variant:
	if backport_target > 4:
		return file_lines
	
	for i in range(file_lines.size()):
		var line = file_lines[i]
		if line.begins_with("@abstract"):
			line = line.replace("@abstract", "")
			line = line.strip_edges()
			file_lines[i] = line
			#break why was this break here??
	
	return file_lines

func post_export_edit_line(line:String) -> String:
	return line

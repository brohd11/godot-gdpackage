extends "res://addons/gdpackage/src/class/export/parse/parse_base.gd"

const DPITexBackportTscn = preload("res://addons/gdpackage/src/class/export/parse/tscn/backport/dpi_texture.gd")
var dpi_tex_backport_tscn:DPITexBackportTscn

var backport_target:= 100

func _init() -> void:
	dpi_tex_backport_tscn = DPITexBackportTscn.new()

func set_parse_settings(settings):
	backport_target = settings.get("backport_target", 100)
	
	dpi_tex_backport_tscn.export_obj = export_obj

func get_direct_dependencies(file_path:String) -> Dictionary:
	var dependencies = {} 
	return dependencies

func pre_export() -> void:
	pass

func post_export_edit_file(file_path:String, file_lines:Variant=null) -> Variant:
	
	if backport_target < 5:
		file_lines = dpi_tex_backport_tscn.post_export_edit_file(file_path, file_lines)
	
	return file_lines

func post_export_edit_line(line:String) -> String:
	return line

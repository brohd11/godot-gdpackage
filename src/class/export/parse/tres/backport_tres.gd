extends "res://addons/gdpackage/src/class/export/parse/parse_base.gd"

const DPITexBackportTres = preload("res://addons/gdpackage/src/class/export/parse/tres/backport/dpi_texture.gd")
var dpi_tex_backport:DPITexBackportTres

var backport_target:= 100

func _init() -> void:
	dpi_tex_backport = DPITexBackportTres.new()

func set_parse_settings(settings):
	backport_target = settings.get("backport_target", 100)
	
	dpi_tex_backport.export_obj = export_obj

func get_direct_dependencies(file_path:String) -> Dictionary:
	var dependencies = {} 
	return dependencies

func pre_export() -> void:
	if backport_target < 5:
		dpi_tex_backport.pre_export()
	

func post_export_edit_file(file_path:String, file_lines:Variant=null) -> Variant:
	return file_lines

func post_export_edit_line(line:String) -> String:
	return line

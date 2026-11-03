extends "res://addons/gdpackage/src/class/export/parse/parse_base.gd"

func set_parse_settings(settings) -> void:
	pass

func get_direct_dependencies(file_path:String) -> Dictionary:
	return edges_to_dependencies(scan_direct_edges(file_path), {})


func post_export_edit_file(file_path:String, file_lines:Variant=null) -> Variant:
	return _rewrite_ser_file(file_path, '[gd_scene')

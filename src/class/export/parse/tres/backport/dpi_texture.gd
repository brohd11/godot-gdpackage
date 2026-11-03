extends "res://addons/gdpackage/src/class/export/parse/parse_base.gd"

var backport_target:= 100

func set_parse_settings(settings):
	backport_target = settings.get("backport_target", 100)

func get_direct_dependencies(file_path:String) -> Dictionary:
	var dependencies = {} 
	return dependencies

func pre_export() -> void:
	var dpi_texture_files = {}
	var files_to_copy = export_obj.files_to_copy.keys()
	var generated_files_path = export_obj.remote_dir.path_join("generated/svg")
	for file:String in files_to_copy:
		if not file.get_extension() == "tres":
			continue
		
		var f = FileAccess.open(file, FileAccess.READ)
		var first_line = f.get_line()
		if not first_line.find('[gd_resource type="DPITexture"') > -1:
			continue
		var file_data = {}
		var is_remote = not UFile.is_file_in_directory(file, export_obj.source)
		
		var file_name = file.get_basename().get_file()
		var path_hash = UFile.hash_string(file).substr(0, 8)
		var export_file_name = "%s_%s.svg" % [file_name, path_hash]
		
		var original_svg_path = file.get_base_dir().path_join(export_file_name)
		var svg_path = original_svg_path
		
		if is_remote:
			svg_path = generated_files_path.path_join(export_file_name)
		
		var export_path = export_obj.get_export_path(svg_path)
		var renamed_path = export_obj.get_renamed_path(svg_path)
		export_obj.adjusted_remote_paths[file] = renamed_path
		
		file_data[KeysData.TO] = export_path
		export_obj.check_file_has_valid_path(original_svg_path, export_path)
		
		dpi_texture_files[file] = file_data
	
	for file in dpi_texture_files.keys():
		export_obj.files_to_copy.erase(file)
	
	export_obj.shared_data["DPITextureBackport"] = dpi_texture_files
	
	if not export_obj.export_valid:
		return
	
	for file in dpi_texture_files.keys():
		var data = dpi_texture_files.get(file)
		var dpi_tex = load(file)
		
		var source = dpi_tex.get_source()
		var export_path = data.get(KeysData.TO)
		if not DirAccess.dir_exists_absolute(export_path.get_base_dir()):
			DirAccess.make_dir_recursive_absolute(export_path.get_base_dir())
		
		var file_access = FileAccess.open(export_path, FileAccess.WRITE)
		file_access.store_string(source)
		

func post_export_edit_file(file_path:String, file_lines:Variant=null) -> Variant:
	return file_lines

func post_export_edit_line(line:String) -> String:
	return line

extends "res://addons/gdpackage/src/class/export/parse/parse_base.gd"

const PLUGIN_EXPORTED_STRING = "const bool PLUGIN_EXPORTED = false"
const PLUGIN_EXPORTED_REPLACE = "const bool PLUGIN_EXPORTED = true"

var namespace_renames = {}

func set_parse_settings(settings) -> void:
	namespace_renames = settings.get("namespace_rename")

func edit_dep_file(line:String, to:String, remote_file:String, remote_dir:String, dependencies:Dictionary) -> String:
	return line

func post_export_edit_line(line:String) -> String:
	line = _update_file_export_flags(line)
	
	for namespace_name in namespace_renames.keys():
		if not line.find("using") > -1 and not line.find("namespace") > -1:
			return line
		if line.find(namespace_name) > -1:
			var namespace_replacement = namespace_renames.get(namespace_name)
			line = line.replace(namespace_name, namespace_replacement)
	
	return line

func _update_file_export_flags(line:String) -> String:
	if line.find(PLUGIN_EXPORTED_STRING) > -1:
		line = line.replace(PLUGIN_EXPORTED_STRING, PLUGIN_EXPORTED_REPLACE)
	return line

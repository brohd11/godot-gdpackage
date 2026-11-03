const LicenseText = preload("res://addons/gdpackage/src/editor_plugins/console_command/init/license/license_text.gd")
const ExportPaths = preload("res://addons/gdpackage/src/class/export/export_paths.gd")

# Never overwrites an existing LICENSE (prints an error and returns false instead).
static func generate(plugin_name:String, name:String, year:String, license_id:String, ctx) -> bool:
	var plugin_dir = ExportPaths.resolve_target(plugin_name)
	if plugin_dir == "":
		ctx.append_error("Invalid package target (expected a path inside this project): " + plugin_name)
		return false
	if not DirAccess.dir_exists_absolute(plugin_dir):
		ctx.append_error("Plugin folder not found: " + plugin_dir)
		return false

	var license_path = plugin_dir.path_join("LICENSE")
	if FileAccess.file_exists(license_path):
		ctx.append_error("LICENSE already exists: " + license_path)
		return false

	var text = LicenseText.get_text(license_id, name, year)
	if text == "":
		ctx.append_error("Unknown license type: " + license_id)
		return false

	var file = FileAccess.open(license_path, FileAccess.WRITE)
	if file == null:
		ctx.append_error("Could not open for writing: %s (%s)" % [license_path, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(text)
	file.close()

	EditorInterface.get_resource_filesystem().scan()
	ctx.append_output("Wrote %s license -> [url=%s]%s[/url]" % [license_id, license_path, license_path])
	return true

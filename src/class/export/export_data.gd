extends RefCounted

const _UtilsRemote = preload("res://addons/gdpackage/src/class/utils_remote.gd")
const _UtilsLocal = preload("res://addons/gdpackage/src/class/utils_local.gd")
const _Docs = preload("uid://01wqb0kamr3o") #! resolve GDPackageSpec.Docs

const Export = _UtilsLocal.ExportObj
const _ExternalDeps = _UtilsLocal.ExternalDeps
const _PackageCfg = preload("uid://ddo8w07hts45v") #! resolve GDPackageSpec.Cfg
const _ExportFileUtils = _UtilsLocal.ExportFileUtils
const KeysConfig = _ExportFileUtils.KeysConfig


var class_list_array = []
var class_list = {}
var class_path_lookup = {}

var data_valid:bool = false

var export_root:String = ""
var plugin_folder:String = ""
var full_export_path:String = ""
var pre_script:String
var post_script:String

var options:Dictionary = {}
## The released cfg's require list: deps an installer must add because they aren't bundled.
var exported_require:Array = []
## Top-level `external:` resolved; each export adds its own entries on top.
var external:Dictionary = {"dirs": [], "specs": []}
var overwrite:bool = true
var include_uid:bool = true
var include_import:bool = true
var move_global_files:bool = true
var ignore_src:bool = true
var ignore_tests:bool = true
var include_docs:bool = true
var include_project_license:bool = false

var file_parser: _UtilsLocal.FileParser
var parser_settings:Dictionary = {}
## Shared by every export in this config: a source file's tags do not change between them.
var tag_registry: _UtilsLocal.TagRegistry = _UtilsLocal.TagRegistry.new()
## Passed in rather than attached after: the whole crawl runs inside _init.
var reporter: _UtilsLocal.Reporter

var exports:Array[Export]

func _init(export_config_path, _reporter = null):
	reporter = _UtilsLocal.Reporter.or_default(_reporter)
	var export_data = _ExportFileUtils.get_export_data(export_config_path, reporter)
	if not export_data:
		return
	
	_ExportFileUtils.string_maps = {}
	
	export_root = export_data.get(KeysConfig.EXPORT_ROOT)
	plugin_folder = export_data.get(KeysConfig.PLUGIN_FOLDER)
	full_export_path = _ExportFileUtils.get_full_export_path(export_root, plugin_folder, export_config_path, reporter)
	if full_export_path == "":
		return
	
	post_script = export_data.get("post_script","")
	if post_script != "":
		if not _ExportFileUtils.check_export_script_valid(post_script, "post_export", reporter):
			return
	
	pre_script = export_data.get("pre_script","")
	if pre_script != "":
		if not _ExportFileUtils.check_export_script_valid(pre_script, "pre_export", reporter):
			return
	
	var strip_cast_path = export_config_path.get_base_dir().path_join("strip_cast.txt")
	var strip_cast_names = []
	if FileAccess.file_exists(strip_cast_path):
		var file = FileAccess.get_file_as_string(strip_cast_path)
		strip_cast_names = file.split("\n", false)
		for i in range(strip_cast_names.size()):
			strip_cast_names[i] = strip_cast_names[i].strip_edges()
	
	options = export_data.get(KeysConfig.OPTIONS)
	var exported = export_data.get(KeysConfig.EXPORTED_REQUIRE)
	if exported == null and options is Dictionary:
		exported = options.get(KeysConfig.Options.EXPORTED_DEPS) # pre-rename configs
	exported_require = exported if exported is Array else ([exported] if exported is String and exported != "" else [])
	external = _resolve_external(export_data.get(KeysConfig.EXTERNAL), export_config_path)
	if external.is_empty():
		return
	overwrite = options.get(KeysConfig.Options.OVERWRITE, false)
	include_uid = options.get(KeysConfig.Options.INCLUDE_UID, true)
	include_import = options.get(KeysConfig.Options.INCLUDE_IMPORT, true)
	move_global_files = options.get(KeysConfig.Options.MOVE_GLOBAL_FILES, true)
	ignore_src = options.get(KeysConfig.Options.IGNORE_SRC, false)
	ignore_tests = options.get(KeysConfig.Options.IGNORE_TESTS, true)
	include_docs = options.get(KeysConfig.Options.INCLUDE_DOCS, true)
	include_project_license = options.get(KeysConfig.Options.INCLUDE_PROJECT_LICENSE, false)

	# The config always sits in the _export_ignore (or export_ignore) dir, so docs are found beside it.
	var doc_source_dir = export_config_path.get_base_dir().path_join(_Docs.SOURCE_SUB_DIR)

	parser_settings = options.get(KeysConfig.Options.PARSER_SETTINGS, {})
	
	if not strip_cast_names.is_empty():
		parser_settings["parse_gd"]["strip_cast"] = strip_cast_names
	
	parser_settings = _sort_settings_dict(parser_settings)
	
	_get_class_list()
	
	var exports_array = export_data.get(KeysConfig.EXPORTS)
	for export in exports_array:
		var export_obj:Export = Export.new()
		export_obj.export_data = self
		export_obj.source = export.get(KeysConfig.Export.SOURCE)
		
		if not export_obj.source.ends_with("/"):
			export_obj.source = export_obj.source + "/"
		
		if not DirAccess.dir_exists_absolute(export_obj.source):
			reporter.error(export_obj.source + " does not exist.", true)
			return
		export_obj.export_name = _ExportFileUtils.get_export_name(export, plugin_folder, export_config_path, reporter)
		export_obj.export_folder = _ExportFileUtils.get_export_folder(export, export_config_path)
		if export_obj.export_name == "" or export_obj.export_folder == "":
			var raw_folder = String(export.get(KeysConfig.Export.EXPORT_FOLDER, ""))
			var reason = _ExportFileUtils.ExportPaths.export_folder_error(raw_folder)
			var msg = "export_folder \"%s\" %s" % [raw_folder, reason] if reason != "" else "invalid export_name or export_folder for " + export_obj.source
			reporter.error("GDPackage - " + msg, true)
			return

		# export_folder is the install path, so a source anywhere else is being renamed.
		export_obj.plugin_name = export_obj.source
		var install_path = "res://" + export_obj.export_folder
		if install_path != export_obj.source:
			export_obj.rename_plugin = true
			export_obj.new_plugin_name = install_path
		
		# Optional: the export_ignore dir is always skipped, which is all most configs listed here.
		var exclude = export.get(KeysConfig.Export.EXCLUDE, {})
		if not exclude is Dictionary:
			exclude = {}
		export_obj.exclude_directories = _array(exclude.get(KeysConfig.Export.Exclude.DIRECTORIES))
		export_obj.exclude_file_extensions = _array(exclude.get(KeysConfig.Export.Exclude.FILE_EXTENSIONS))
		export_obj.exclude_files = _array(exclude.get(KeysConfig.Export.Exclude.FILES))

		var own_external = _resolve_external(export.get(KeysConfig.Export.EXTERNAL), export_config_path)
		if own_external.is_empty():
			return
		export_obj.external_dirs = external.dirs.duplicate()
		for dir in own_external.dirs:
			if not dir in export_obj.external_dirs:
				export_obj.external_dirs.append(dir)
		export_obj.exported_require = _ExternalDeps.merge_require(
			_ExternalDeps.merge_require(exported_require, external.specs), own_external.specs)
		
		var default_remote_dir = export_obj.source.path_join("src/remote")
		export_obj.remote_dir = export.get(KeysConfig.Export.REMOTE_DIR, default_remote_dir)
		if not export_obj.remote_dir.begins_with(export_obj.source):
			export_obj.remote_dir = export_obj.source.path_join(export_obj.remote_dir)
		
		export_obj.source_files = _UtilsRemote.GetFiles.scan(export_obj.source)
		export_obj.export_dir_path = full_export_path.path_join(export_obj.export_name).path_join(export_obj.export_folder)
		export_obj.other_transfers = _array(export.get(KeysConfig.Export.OTHER_TRANSFERS))
		# Hides src/ in the release; should_move_global() has already pulled globals out of it.
		if ignore_src and DirAccess.dir_exists_absolute(export_obj.source.path_join("src")):
			export_obj.other_transfers.append({"to": "src/.gdignore"})
		# Documented as an option; older configs set it on the export entry.
		export_obj.ignore_dependencies = export.get(KeysConfig.Options.IGNORE_DEPENDENCIES,
			options.get(KeysConfig.Options.IGNORE_DEPENDENCIES, false))
		
		export_obj.file_parser = _UtilsLocal.FileParser.new()
		export_obj.file_parser.set_export_obj(export_obj)
		var overide_value = export.get(KeysConfig.Options.PARSER_OVERIDE_SETTINGS, {})
		var overide_settings:Dictionary = overide_value.duplicate(true) if overide_value is Dictionary else {}
		#overide_settings = _sort_settings_dict(overide_settings)
		
		for parse_key in parser_settings.keys():
			if not parse_key.begins_with("parse_"):
				continue
			# Copied so every export gets settings of its own.
			var parse_data:Dictionary = parser_settings.get(parse_key, {}).duplicate(true)
			if overide_settings.has(parse_key):
				if parse_key == "parse_gd" and overide_settings[parse_key].has("optimizer") and parse_data.has("optimizer"):
					var local:Variant = overide_settings[parse_key].optimizer
					if local is Dictionary and parse_data.optimizer is Dictionary:
						local.merge(parse_data.optimizer.duplicate(true))
				overide_settings[parse_key].merge(parse_data)
			else:
				overide_settings[parse_key] = parse_data
		
		# Runs after the merge so untyped settings in the settings-dict body override per-ext ones.
		overide_settings = _sort_settings_dict(overide_settings)
		
		var parse_gd_settings = overide_settings.get("parse_gd", {})
		export_obj.class_rename_ignore = parse_gd_settings.get("class_rename_ignore", [])
		export_obj.get_class_renames()
		export_obj.use_relative_paths = parse_gd_settings.get("use_relative_paths", false)
		export_obj.reduce_access_paths = parse_gd_settings.get("reduce_access_paths", true)
		
		export_obj.parser_overide_settings = overide_settings
		export_obj.file_parser.set_parser_settings(overide_settings)
		
		export_obj.get_valid_files_for_transfer()
		export_obj.sort_valid_files()
		export_obj.get_global_classes_used_in_valid_files()
		export_obj.get_file_dependencies()
		export_obj.get_global_class_export_paths()
		export_obj.resolve_dependency_placements()
		if not export_obj.export_valid:
			return
		export_obj.build_access_bindings()
		
		export_obj.gather_licenses()

		if include_docs and DirAccess.dir_exists_absolute(doc_source_dir):
			export_obj.gather_docs(doc_source_dir)

		export_obj.check_all_files_have_valid_path()
		
		export_obj.get_singleton_modules()
		
		if not export_obj.export_valid:
			return
		
		exports.append(export_obj)
	
	
	data_valid = true

## {dirs, specs} for an `external` value, or {} after reporting why it failed.
func _resolve_external(value, export_config_path:String) -> Dictionary:
	var items = _ExternalDeps.entries(value)
	if items.is_empty():
		return {"dirs": [], "specs": []}
	var resolved = _ExternalDeps.resolve(items)
	for e in resolved.errors:
		reporter.error("GDPackage - " + e, true)
	if not resolved.errors.is_empty():
		return {}
	var package_dir = export_config_path.get_base_dir().get_base_dir() # config sits in export_ignore/
	var cfg_path = _PackageCfg.find(package_dir)
	var cfg_text = FileAccess.get_file_as_string(cfg_path) if cfg_path != "" else ""
	# Specs need no check: DepResolver installs them for build and compile on its own.
	var required = _ExternalDeps.repo_ids(exported_require + Array(_ExternalDeps.DepResolver.cfg_require(cfg_text)))
	for item in items:
		if item.begins_with("res://") and not required.has(_ExternalDeps.dir_repo_id(item)):
			reporter.warn("GDPackage - external dir %s is in no require list; installers will not know to add it" % item)
	return {"dirs": resolved.dirs, "specs": resolved.specs}


static func _array(value) -> Array:
	return value if value is Array else []


func _sort_settings_dict(dict:Dictionary):
	var sorted_dict = {}
	var untyped_keys = []
	for parse_key in dict.keys():
		if not parse_key.begins_with("parse_"):
			untyped_keys.append(parse_key)
			continue
		
		sorted_dict[parse_key] = dict[parse_key]
	
	for parse_key in sorted_dict.keys():
		# Copied rather than written through: folding the untyped keys into the caller's dict
		# is how one export's settings used to leak into the next.
		var data:Dictionary = (sorted_dict[parse_key] as Dictionary).duplicate()

		for key in untyped_keys:
			data[key] = dict[key]
		sorted_dict[parse_key] = data

	return sorted_dict

func _get_class_list():
	var global_class_list = ProjectSettings.get_global_class_list()
	for class_dict in global_class_list:
		var _class_name = class_dict.get("class")
		var path = class_dict.get("path")
		var str_class_nm = String(_class_name)
		class_list[str_class_nm] = path
		class_path_lookup[path] = str_class_nm
		if _class_name not in class_list_array:
			class_list_array.append(_class_name)

func  should_move_global():
	return move_global_files or ignore_src

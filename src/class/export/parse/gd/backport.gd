extends "res://addons/gdpackage/src/class/export/parse/parse_base.gd"

const EI_BACKPORT_PATH = "res://addons/gdpackage/src/class/export/backport/ei_backport.gd"
const EI_BACKPORT = "_EIBackport"

const MISC_BACKPORT_PATH = "res://addons/gdpackage/src/class/export/backport/misc_backport_class.gd"
const MISC_BACKPORT = "MiscBackport"

const BACKPORT_FILES = [
	"res://addons/gdpackage/src/class/export/backport/context/context_backport.gd",
	"res://addons/gdpackage/src/class/export/backport/context/context_plugin_compat.gd",
	"res://addons/gdpackage/src/class/export/backport/ei_backport.gd",
	"res://addons/gdpackage/src/class/export/backport/misc_backport_class.gd",
	"res://addons/gdpackage/src/class/export/backport/sv_backport.gd"
]

const Backport4_0 = preload("res://addons/gdpackage/src/class/export/parse/gd/backport/4_0_backports.gd")
var backport4_0:Backport4_0

const BackportContext = preload("res://addons/gdpackage/src/class/export/parse/gd/backport/context_menu.gd")
var backport_context:BackportContext

const BackportStaticVar = preload("res://addons/gdpackage/src/class/export/parse/gd/backport/static_var_backport.gd")
var backport_static_var:BackportStaticVar

const Backport4_4 = preload("res://addons/gdpackage/src/class/export/parse/gd/backport/4_4_backports.gd")
var backport4_4:Backport4_4

const MiscBackportParse = preload("res://addons/gdpackage/src/class/export/parse/gd/backport/misc_backport.gd")
var misc_backport:MiscBackportParse

var backport_target:= -1


func _init() -> void:
	backport4_0 = Backport4_0.new()
	backport4_4 = Backport4_4.new()
	backport_static_var = BackportStaticVar.new()
	backport_context = BackportContext.new()
	misc_backport = MiscBackportParse.new()


func set_parse_settings(settings):
	backport_target = settings.get("backport_target", 100)
	
	backport4_0.set_parse_settings(settings)
	backport4_4.set_parse_settings(settings)
	
	backport_static_var.export_obj = export_obj
	backport_static_var.set_parse_settings(settings)
	
	backport_context.export_obj = export_obj
	backport_context.set_parse_settings(settings)
	
	misc_backport.set_parse_settings(settings)



func get_direct_dependencies(file_path:String) -> Dictionary:
	var dependencies = {}
	return dependencies

func pre_export():
	backport_static_var.pre_export()


func post_export_edit_file(file_path:String, file_lines:Variant=null) -> Variant:
	if backport_target == 100:
		return file_lines
	
	var extends_class = file_extends_class(file_lines, backport_target)
	if backport_target < 4:
		backport4_0.current_file_path = export_obj.file_parser.current_file_path_parsing
		
		for i in range(file_lines.size()):
			var line = file_lines[i]
			line = backport_context.post_export_edit_line(line)
			file_lines[i] = line
		
		var file_as_text = "\n".join(file_lines)
		var converted_file = backport4_0.backport_raw_strings(file_as_text)
		file_lines = converted_file.split("\n")
		
		file_lines = backport_context.post_export_edit_file(file_path, file_lines) # internal check for version
		
	if backport_target < 2:
		file_lines = backport_static_var.post_export_edit_file(file_path, file_lines) # internal check for version
		
	
	
	if backport_target < 5:
		file_lines = backport4_4.post_export_edit_file(file_path, file_lines)
		
	
	if not extends_class:
		if backport_target < 2:
			file_lines.append("# GDPACKAGE EDITORINTERFACE BACKPORT")
			file_lines.append(get_backport_file_path(self, EI_BACKPORT, EI_BACKPORT_PATH, export_obj))
			
			#file_lines.append("### GDPACKAGE EDITORINTERFACE BACKPORT")
			file_lines.append("")
		
		var has_backport_preloaded := false
		for line in file_lines:
			if line.begins_with("const %s" % MISC_BACKPORT): 
				has_backport_preloaded =  true
		
		if not has_backport_preloaded:
			file_lines.append("# GDPACKAGE MISC BACKPORT")
			file_lines.append(get_backport_file_path(self, MISC_BACKPORT, MISC_BACKPORT_PATH, export_obj))
			
			#file_lines.append("### GDPACKAGE MISC BACKPORT")
			file_lines.append("")
	
	for i in range(file_lines.size()):
		var line = file_lines[i]
		if line.strip_edges() == "const BACKPORTED = 100":
			line = "const BACKPORTED = %s" % backport_target
			file_lines[i] = line
			break
	
	return file_lines


func post_export_edit_line(line:String) -> String:
	
	if backport_target < 4:
		line = backport4_0.post_export_edit_line(line)
	if backport_target < 5:
		line = backport4_4.post_export_edit_line(line)
	
	line = misc_backport.post_export_edit_line(line)
	
	return line


static func get_required_files(_backport_target):
	var files = []
	if _backport_target == 100:
		return files
	
	files.append(MISC_BACKPORT_PATH)
	if _backport_target < 4:
		files.append(BackportContext.COMPAT_CLASS_PATH)
		files.append(BackportContext.COMPAT_SING_PATH)
	
	if _backport_target < 2:
		files.append(EI_BACKPORT_PATH)
		files.append(BackportStaticVar.BACKPORT_STATIC_PATH)
	
	var script = preload("./backport.gd") #! ignore-remote
	for i in range(files.size()):
		var file = files[i]
		file = UFile.path_from_relative(file, script.resource_path)
		files[i] = file
	
	return files

static func get_backport_file_path(calling_obj:RefCounted, preload_name:String, path:String, _export_obj:UtilsLocal.ExportObj):
	var abs_path = _export_obj.ensure_absolute_path(path, calling_obj.get_script().resource_path)
	var misc_adj_path = _export_obj.adjusted_remote_paths.get(abs_path, path)
	var proper_path = _export_obj.get_rel_or_absolute_path(misc_adj_path)
	return _construct_pre(preload_name, proper_path)

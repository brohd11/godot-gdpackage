extends "res://addons/_lib/popup_wrapper/src/context_menu.gd" #! ext PopupWrapper.ContextMenu

const SLOT = EditorContextMenuPlugin.CONTEXT_SLOT_SCRIPT_EDITOR_CODE

const Params = PopupWrapper.ContextPlugin.ItemParams

const UtilsRemote = preload("res://addons/package_exporter/src/class/utils_remote.gd")
const UFile = UtilsRemote.UFile

const DEPENDENCY_TAGS = ["#! dependency", "#! ignore-remote"]

const SINGLETON_MODULE = "Package Exporter/Singleton Module"
const DEPENDENCY = "Package Exporter/Dependency"
const EXPORTED_FLAG = "Package Exporter/Exported Flag"
const BACKPORT_FLAG = "Package Exporter/Backport Flag"
const IGNORE_REMOTE = "Package Exporter/Ignore Remote"

const STD_META = {
	Params.PRIORITY: 1020,
	Params.POSITION: Params.Position.BOTTOM,
}


func _get_menu_options(data) -> void:
	var script_editor:CodeEdit = PopupWrapper.Slots.code_edit(data)
	
	var valid_items = get_valid_items(script_editor)
	PopupWrapper.ContextPlugin.create_items(self, data, valid_items, _on_popup_pressed)


func _on_popup_pressed(data, item_name):
	var script_editor:CodeEdit = PopupWrapper.Slots.code_edit(data)
	if item_name == SINGLETON_MODULE:
		add_singleton_module(script_editor)
	elif item_name == DEPENDENCY:
		add_dep_tag(script_editor)
	elif item_name == IGNORE_REMOTE:
		add_ignore_remote(script_editor)
	elif item_name == EXPORTED_FLAG:
		add_exported_flag(script_editor)
	elif item_name == BACKPORT_FLAG:
		add_backport_flag(script_editor)


static func get_valid_items(script_editor:CodeEdit) -> Dictionary:
	var valid_items = {}
	
	var line = script_editor.get_caret_line()
	var text = script_editor.get_line(line)
	if text == "":
		valid_items[EXPORTED_FLAG] = STD_META
		valid_items[BACKPORT_FLAG] = STD_META
	
	if text.begins_with("class_name"):
		if text.find("#! singleton-module") == -1:
			valid_items[SINGLETON_MODULE] = STD_META
	
	if text.count('"') == 2:
		var valid_dep = true
		for tag in DEPENDENCY_TAGS:
			if text.find(tag) > -1:
				valid_dep = false
		var file_path = text.get_slice('"', 1)
		file_path = file_path.get_slice('"', 0)
		if not UFile.file_exists(file_path):
			valid_dep = false
		if valid_dep:
			valid_items[DEPENDENCY] = STD_META
			valid_items[IGNORE_REMOTE] = STD_META
	
	return valid_items

static func add_singleton_module(script_editor):
	var line = script_editor.get_caret_line()
	var text = script_editor.get_line(line)
	script_editor.set_caret_column(text.length())
	script_editor.insert_text_at_caret(" #! singleton-module")

static func add_dep_tag(script_editor):
	var line = script_editor.get_caret_line()
	var text = script_editor.get_line(line)
	script_editor.set_caret_column(text.length())
	script_editor.insert_text_at_caret(" #! dependency")

static func add_ignore_remote(script_editor):
	var line = script_editor.get_caret_line()
	var text = script_editor.get_line(line)
	script_editor.set_caret_column(text.length())
	script_editor.insert_text_at_caret(" #! ignore-remote")

static func add_exported_flag(script_editor):
	var line = script_editor.get_caret_line()
	var text = script_editor.get_line(line)
	script_editor.insert_text_at_caret("const PLUGIN_EXPORTED = false")

static func add_backport_flag(script_editor):
	var line = script_editor.get_caret_line()
	var text = script_editor.get_line(line)
	script_editor.insert_text_at_caret("const BACKPORTED = 100")

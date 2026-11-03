@tool
extends EditorPlugin

const PLUGIN_EXPORTED = false

const GUI = preload("res://addons/gdpackage/src/gui/gui.gd")
const COMMENT_TAGS = ["#! remote", "#! ignore-remote", "#! dependency", "#! singleton-module", "#! strip-cast"]
const SHOW_TOOL_MENU_ITEM = &"plugin/gdpackage/show_tool_menu_item"

const UtilsRemote = preload("res://addons/gdpackage/src/class/utils_remote.gd")

const ConsoleCommand = preload("res://addons/gdpackage/src/editor_plugins/console_command/console_command.gd")
const ContextMenuPlugin = preload("res://addons/gdpackage/src/editor_plugins/plugin_exporter_context_menus.gd")

static var instance


var context_plugin_inst:ContextMenuPlugin
var dm_instance_manager:DockManager.InstanceManager

func _get_plugin_name() -> String:
	return "GDPackage"

func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_base_control().get_theme_icon("ActionCopy", &"EditorIcons")

func _has_main_screen() -> bool:
	return true

func _make_visible(visible: bool) -> void:
	dm_instance_manager.on_plugin_make_visible(visible)


func _enter_tree() -> void:
	instance = self
	dm_instance_manager = DockManager.InstanceManager.new(self)
	
	FileSystemSingleton.register_node(self)
	
	context_plugin_inst = ContextMenuPlugin.new()
	add_context_menu_plugin(EditorContextMenuPlugin.CONTEXT_SLOT_SCRIPT_EDITOR_CODE, context_plugin_inst)
	
	var ed_settings = EditorInterface.get_editor_settings()
	if not ed_settings.has_setting(SHOW_TOOL_MENU_ITEM):
		ed_settings.set_setting(SHOW_TOOL_MENU_ITEM, true)
	
	if ed_settings.get_setting(SHOW_TOOL_MENU_ITEM):
		add_tool_menu_item("GDPackage", _on_tool_menu_pressed)
	
	_register_singletons.call_deferred()

func _exit_tree() -> void:
	remove_context_menu_plugin(context_plugin_inst)
	
	remove_tool_menu_item("GDPackage")
	
	FileSystemSingleton.unregister_node(self)
	
	if is_instance_valid(dm_instance_manager):
		dm_instance_manager.clean_up()
	dm_instance_manager = null
	
	instance = null

func _on_tool_menu_pressed():
	new_gui_instance()

func new_gui_instance():
	var gui = GUI.new()
	#gui.name = "GDPackage"
	#gui.name = "PE"
	var ins = dm_instance_manager.new_freeable_dock_manager(gui, DockManager.Slot.MAIN_SCREEN)
	ins.allow_scene_reload = true
	return ins


func _register_singletons():
	_register_editor_console()
	_register_code_completions()
	_register_syntax_tags()

func _register_editor_console():
	var sing_name = "EditorConsoleSingleton"
	if not Singletons.CheckInstance.check_valid(sing_name):
		return
	var singleton = Singletons.CheckInstance.get_instance(sing_name)
	singleton.register_temp_scope("gdpackage", ConsoleCommand)

func _register_code_completions():
	var sing_name = "EditorCodeCompletionSingleton"
	if not Singletons.CheckInstance.check_valid(sing_name):
		return
	var prefix = "#!"
	var singleton = Singletons.CheckInstance.get_instance(sing_name)
	singleton.register_tag(prefix, "remote", singleton.TagLocation.START)
	singleton.register_tag(prefix, "ignore-remote", singleton.TagLocation.END)
	singleton.register_tag(prefix, "dependency", singleton.TagLocation.END)
	singleton.register_tag(prefix, "singleton-module", singleton.TagLocation.END)
	singleton.register_tag(prefix, "strip-cast", singleton.TagLocation.START)


func _register_syntax_tags():
	var sing_name = "SyntaxPlusSingleton"
	if not Singletons.CheckInstance.check_valid(sing_name):
		return
	var singleton = Singletons.CheckInstance.get_instance(sing_name)
	for tag in COMMENT_TAGS:
		var prefix = tag.get_slice(" ", 0)
		var tag_name = tag.get_slice(" ", 1)
		singleton.register_comment_tag(prefix, tag_name)

func _unregister_syntax_tags():
	var sing_name = "SyntaxPlusSingleton"
	if not Singletons.CheckInstance.check_valid(sing_name):
		return
	var singleton = Singletons.CheckInstance.get_instance(sing_name)
	for tag in COMMENT_TAGS:
		var prefix = tag.get_slice(" ", 0)
		var tag_name = tag.get_slice(" ", 1)
		singleton.unregister_comment_tag(prefix, tag_name)


func _unregister_singletons():
	_unregister_syntax_tags()

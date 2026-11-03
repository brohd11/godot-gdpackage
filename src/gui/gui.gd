extends Control

const PluginExporter = preload("res://addons/gdpackage/src/class/plugin_exporter.gd")
const UtilsRemote = preload("res://addons/gdpackage/src/class/utils_remote.gd")

const TabBarContainer = UtilsRemote.TabBarContainer
const EditorIcons = UtilsRemote.EditorIcons

const Options = UtilsRemote.Options

const UControl = UtilsRemote.UControl
const UFile = UtilsRemote.UFile

const FSTreeClasses = preload("res://addons/_lib/editor_filesystem/src/components/tree/fs_tree_classes.gd")

const YAMLHighlighter = preload("uid://com2gj0t82d8f") #! resolve SyntaxHighlighters.Text.Yaml

const Summary = preload("res://addons/gdpackage/src/gui/panels/summary.gd")
const DependencyView = preload("res://addons/gdpackage/src/gui/panels/dep_view.gd")
const ExportEditor = preload("res://addons/gdpackage/src/gui/panels/export_editor.gd")
const DocViewer = preload("res://addons/gdpackage/src/components/doc_viewer/doc_viewer.gd")


#const FileSystem = UtilsRemote.FileSystem
#const PopupHelper = UtilsRemote.PopupHelper
#const UEditorTheme = UtilsRemote.UEditorTheme
#const Filter = UtilsRemote.UString.Filter

const UtilsLocal = preload("res://addons/gdpackage/src/class/utils_local.gd")
const PluginExporterStatic = UtilsLocal.PluginExporterStatic
const ExportData = UtilsLocal.ExportData
const Export = ExportData.Export

const PluginInit = UtilsLocal.PluginInit
const ExportFileUtils = UtilsLocal.ExportFileUtils
const KeysData = ExportFileUtils.KeysData
const KeysConfig = ExportFileUtils.KeysConfig

# DockManager
const BUTTON_TEXT = "PE"
var icon = EditorInterface.get_editor_theme().get_icon(&"ActionCopy", &"EditorIcons")
var dock_button:Button
# /DockManager

var right_click_handler:UtilR.Nodes.PopupMenus.Placer

var main_vbox:VBoxContainer
var header_hbox:HBoxContainer

var file_path_line:FilePathLine
var options_button:Button

var split_container:HSplitContainer

var tab_options_button:Button
var tab_container:TabBarContainer

var file_tree:ExportTree
var tree_helper:FSTreeClasses.FSTreeHelper

var summary_panel:Summary
var dep_view:DependencyView
var export_editor:ExportEditor
var doc_viewer:DocViewer

var current_export_data:ExportData

func _init() -> void:
	name = BUTTON_TEXT

func set_dock_data(dock_data:Dictionary):
	var export_path = dock_data.get("last_export_file")
	if export_path:
		_set_file_path(export_path)

func get_dock_data():
	var dock_data = {}
	if is_instance_valid(file_path_line) and FileAccess.file_exists(file_path_line.text):
		dock_data["last_export_file"] = file_path_line.text
	return dock_data

func _ready() -> void:
	right_click_handler = UtilR.Nodes.PopupMenus.Placer.new()
	add_child(right_click_handler)
	
	#set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	
	main_vbox = VBoxContainer.new()
	add_child(main_vbox)
	main_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	header_hbox = HBoxContainer.new()
	main_vbox.add_child(header_hbox)
	
	file_path_line = FilePathLine.new()
	file_path_line.path_dropped.connect(_set_file_path)
	header_hbox.add_child(file_path_line)
	file_path_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	#header_hbox.add_spacer(false)
	
	dock_button = Button.new()
	header_hbox.add_child(dock_button)
	dock_button.hide.call_deferred()
	
	options_button = Button.new()
	header_hbox.add_child(options_button)
	options_button.icon = EditorInterface.get_editor_theme().get_icon(&"TripleBar", &"EditorIcons")
	options_button.theme_type_variation = &"FlatButton"
	options_button.pressed.connect(_on_options_pressed)
	
	split_container = HSplitContainer.new()
	main_vbox.add_child(split_container)
	UControl.expand(split_container)
	
	file_tree = ExportTree.new()
	file_tree.allow_drag = false
	file_tree.allow_rmb_select = true
	split_container.add_child(file_tree)
	
	UControl.expand(file_tree)
	
	tree_helper = FSTreeClasses.FSTreeHelper.new(file_tree, null, null, null, false)
	file_tree.tree_helper = tree_helper
	
	tree_helper.mouse_left_clicked.connect(_on_tree_left_click)
	tree_helper.mouse_right_clicked.connect(_on_tree_right_click)
	tree_helper.filesystem_singleton = FileSystemSingleton.get_instance()
	
	tab_container = TabBarContainer.new()
	split_container.add_child(tab_container)
	UControl.expand(tab_container)
	
	tab_options_button = Button.new()
	tab_container.get_tab_bar_hbox().add_child(tab_options_button)
	tab_options_button.pressed.connect(_on_tab_options_pressed)
	tab_options_button.theme_type_variation = &"FlatButton"
	tab_options_button.icon = EditorInterface.get_editor_theme().get_icon(&"Tools", &"EditorIcons")
	
	summary_panel = Summary.new()
	tab_container.add_tab(summary_panel, EditorInterface.get_editor_theme().get_icon(&"ExternalLink", &"EditorIcons"))
	UControl.expand(summary_panel)
	
	dep_view = DependencyView.new()
	tab_container.add_tab(dep_view, EditorIcons.get_icon_white("GraphEdit"))
	UControl.expand(dep_view)
	
	export_editor = ExportEditor.new()
	tab_container.add_tab(export_editor, EditorIcons.get_icon_white("CodeEdit"))
	UControl.expand(tab_container)

	doc_viewer = DocViewer.new()
	tab_container.add_tab(doc_viewer, EditorIcons.get_icon_white("Help"))
	doc_viewer.clear()
	UControl.expand(doc_viewer)

func _on_options_pressed():
	var options = Options.new()
	options.add_option("Parse", _parse_export_data.bind(true), ["FileList"])
	if _export_valid_file():
		options.add_option("Export", _run_export, ["ResourcePreloader"])
		options.add_option("Open Dir", _open_folder, ["Folder"])
	options.add_option("Show All Deps", _show_all_deps)
	var valid_plugins = PluginExporter.get_addons_dirs(PluginExporter.TargetAddons.VALID)
	for p in valid_plugins:
		options.add_option("Load".path_join(p), _load_plugin.bind(p), ["Load", null])
	
	options.add_separator()
	options.add_option("DockManager", func():dock_button.pressed.emit(), ["MakeFloating"])
	right_click_handler.display_on_control(options, options_button)

func _show_all_deps():
	dep_view.current_files = current_export_data.exports[0].valid_files_for_transfer.keys()
	dep_view._create_graph()

func _on_tab_options_pressed():
	var current_tab_control = tab_container.get_current_tab_control()
	if not current_tab_control.has_method(&"get_options"):
		return
	var options = current_tab_control.call(&"get_options")
	right_click_handler.display_on_control(options, tab_options_button)

func _on_tree_left_click():
	var local = _get_tree_selected_path()
	if FileAccess.file_exists(local):
		pass
	

func _on_tree_right_click():
	var options = Options.new()
	var local = _get_tree_selected_path()
	if FileAccess.file_exists(local):
		options.add_option("Show Dependency", dep_view.set_current_file.bind(local), [EditorIcons.get_icon_white("GraphEdit")])
	right_click_handler.display_popup(options)

func _get_tree_selected_path():
	var selected_item = file_tree.get_selected()
	if selected_item == null:
		return ""
	var meta = selected_item.get_metadata(0)
	if meta == null:
		return ""
	var local = meta.get(Keys.LOCAL_PATH)
	if local == null:
		return ""
	return local

func _load_plugin(plugin_name:String):
	var path = PluginExporterStatic.get_export_config_by_name(plugin_name)
	if FileAccess.file_exists(path):
		_set_file_path(path)

func _set_file_path(file_path:String):
	file_path_line.text = file_path
	export_editor.load_file(file_path)
	_set_doc_path(file_path)
	
	dep_view.dep_graph.clear_graph()
	file_tree.clear()
	tree_helper.clear_items()
	summary_panel.clear()

func _load_file(file_path:String):
	file_path_line.text = file_path
	export_editor.load_file(file_path)
	current_export_data = ExportData.new(file_path)
	_parse_export_data()

func _run_export():
	var export_path = file_path_line.text
	PluginExporterStatic.export_by_gui(export_path)

func _open_folder():
	var export_path = file_path_line.text
	PluginExporterStatic.open_export_dir(export_path)

func _export_valid_file():
	var export_path = file_path_line.text
	if not FileAccess.file_exists(export_path):
		return false
	return export_path.get_file() in PluginExporterStatic.ExportFileUtils.VALID_FILE_NAMES

func _parse_export_data(reparse:=false):
	var export_config_path = file_path_line.text
	if reparse or not is_instance_valid(current_export_data):
		current_export_data = ExportData.new(export_config_path)
	var export_data = current_export_data
	summary_panel.set_export_data(export_data)
	_build_tree()

func _build_tree():
	file_tree.clear()
	tree_helper.clear_items()
	
	var export_data = current_export_data
	if not export_data.data_valid:
		printerr("Issue with export data.")
		_collapse_tree()
		return
	
	var fs_sing = FileSystemSingleton.get_instance()
	var file_icon = EditorInterface.get_editor_theme().get_icon(&"File", &"EditorIcons")
	var broken_icon = EditorInterface.get_editor_theme().get_icon(&"FileBroken", &"EditorIcons")
	
	var full_export_path = export_data.full_export_path
	
	var pre_script = export_data.pre_script
	if pre_script != "":
		ExportFileUtils.run_export_script(pre_script, "pre_export", export_data)
	
	# build tree
	var root_item:TreeItem
	root_item = file_tree.create_item()
	var root_name = full_export_path.get_file()
	if full_export_path.ends_with("/"):
		root_name = full_export_path.get_base_dir().get_file()
	root_item.set_text(0, root_name)
	root_item.set_tooltip_text(0, full_export_path)
	root_item.set_icon(0, tree_helper.folder_icon)
	root_item.set_icon_modulate(0, tree_helper.folder_color)
	tree_helper.parent_item = root_item
	# /build tree
	
	for export:Export in export_data.exports:
		var source = export.source
		var export_dir_path = export.export_dir_path
		
		# build tree
		var export_folder_item:TreeItem
		tree_helper.parent_item = root_item
		export_folder_item = tree_helper.new_file_path(export_dir_path, full_export_path)
		# /build tree
		
		
		var files_to_copy = export.files_to_copy.keys()
		
		files_to_copy.sort_custom(
			func(a: String, b: String) -> bool:
				a = export.files_to_copy[a].get(KeysData.TO)
				b = export.files_to_copy[b].get(KeysData.TO)
				
				var pa := a.split("/")
				var pb := b.split("/")
				var n: int = min(pa.size(), pb.size())
				for i in n:
					var a_is_file := i == pa.size() - 1
					var b_is_file := i == pb.size() - 1
					if a_is_file != b_is_file:
						return b_is_file  # the one still inside a folder wins
					if pa[i] != pb[i]:
						return pa[i].filenocasecmp_to(pb[i]) < 0
				return pa.size() < pb.size()
				
		)
		#files_to_copy.sort() # figure this out later, to sort added files
		for local_file_path in files_to_copy:
			var export_file_data = export.files_to_copy.get(local_file_path)
			var export_path = export_file_data.get(KeysData.TO)
			#print(local_file_path , " -> ", export_path)
			var replace_with = export_file_data.get(KeysData.REPLACE_WITH)
			var dependent = export_file_data.get(KeysData.DEPENDENT)
			var custom_message = export_file_data.get(KeysData.CUSTOM_TREE_MESSAGE)
			#var remote_file_data = ExportFileUtils.get_remote_file(local_file_path, export)
			# build tree
			
			#var file_data = {} # file_data_dict.get(local_file_path)
			var file_data = FSTreeClasses.Utils.get_file_data(local_file_path, fs_sing)
			var last_item = tree_helper.new_file_path(export_path, full_export_path, file_data) as TreeItem
			last_item.get_metadata(0)[Keys.LOCAL_PATH] = local_file_path
			if last_item.get_icon(0) == broken_icon:
				last_item.set_icon(0, file_icon)
			
			if not file_data:
				if FileAccess.file_exists(local_file_path):
					last_item.set_icon(0, file_icon)
					last_item.set_icon_modulate(0, Color.WHITE)
			
			var text = last_item.get_text(0)
			if custom_message != null:
				var new_text = text + custom_message
				last_item.set_text(0, new_text)
				last_item.set_tooltip_text(0, new_text)
			elif replace_with != null:
				var new_text = text + " <- (remote file: %s)" % replace_with.get_file()
				last_item.set_text(0, new_text)
			elif dependent != null:
				var new_text = text + " -> (dependency)"
				last_item.set_text(0, new_text)
			
			if last_item.get_text(0).begins_with("%s"):
				printerr("'%' in file path: ", local_file_path)
		
		for virtual_file_type in export.virtual_files.keys():
			var virtual_file_type_data = export.virtual_files[virtual_file_type]
			for local_file_path in virtual_file_type_data.keys():
				var export_file_data = virtual_file_type_data.get(local_file_path)
				var export_path = export_file_data.get(KeysData.TO)
				var custom_message = export_file_data.get(KeysData.CUSTOM_TREE_MESSAGE)
				var last_item = tree_helper.new_file_path(export_path, full_export_path) as TreeItem
				last_item.set_icon(0, file_icon)
				last_item.set_icon_modulate(0, Color.WHITE)
				var text = last_item.get_text(0)
				if custom_message != null:
					var new_text = text + custom_message
					last_item.set_text(0, new_text)
					last_item.set_tooltip_text(0, new_text)
			
		# /build tree
	
	
	#if not first_tree_build:
		#_collapse_tree()



func _collapse_tree():
	var root_item = file_tree.get_root()
	if not root_item:
		return
	root_item.set_collapsed_recursive(true)
	root_item.collapsed = false


func _set_doc_path(export_file_path:String):
	var plugin_dir = export_file_path.get_base_dir().get_base_dir()
	var docs_path = export_file_path.get_base_dir().path_join("doc")
	if DirAccess.dir_exists_absolute(docs_path):
		doc_viewer.set_docs_path(docs_path)
	elif FileAccess.file_exists(plugin_dir.path_join("README.md")) or FileAccess.file_exists(plugin_dir.path_join("readme.md")):
		doc_viewer.display(plugin_dir)
	else:
		doc_viewer.clear()

class ExportTree extends FSTreeClasses.MinTree:
	
	func _make_custom_tooltip(_for_text: String) -> Object:
		var item = get_item_at_position(get_local_mouse_position())
		if item:
			var path = get_path_from_item(item)
			if path == "":
				return null
			if not path in ["res://", FileData.FAVORITES_META]:
				return FileSystemSingleton.get_custom_tooltip(path)
		return null
	
	func get_tree_selected_path():
		var selected_item = get_selected()
		if selected_item == null:
			return ""
		return get_path_from_item(selected_item)
		
	func get_path_from_item(item:TreeItem):
		var meta = item.get_metadata(0)
		if meta == null:
			return ""
		var local = meta.get(Keys.LOCAL_PATH)
		if local == null:
			return ""
		return local


class FilePathLine extends LineEdit:
	
	signal path_dropped(path:String)
	
	func _init() -> void:
		placeholder_text = "export.yml"
		#right_icon = EditorInterface.get_editor_theme().get_icon(&"File", &"EditorIcons")
	
	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		var type = data.get("type")
		if type == "files":
			return true
		return false

	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		var files = data.get("files")
		if files.is_empty():
			return
		var file = files[0]
		text = file
		path_dropped.emit(file)


class Keys:
	const LOCAL_PATH = &"local_path"
	

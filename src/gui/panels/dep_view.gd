extends VBoxContainer

const UtilsRemote = preload("res://addons/gdpackage/src/class/utils_remote.gd")
const UtilsLocal = preload("res://addons/gdpackage/src/class/utils_local.gd")
const UControl = UtilsRemote.UControl
const Options = UtilsRemote.Options
const DepGraphUI = UtilsRemote.DepGraphUI
const DependencyTags = UtilsLocal.DependencyTags
const GraphToolbar = preload("res://addons/gdpackage/src/gui/panels/graph_toolbar.gd")

enum ViewMode { FILES_TREE, FILES_ALL }
const VIEW_LABELS = {"Tree": ViewMode.FILES_TREE, "All": ViewMode.FILES_ALL}

var dep_graph:DepGraphUI
var tools_button:Button

var view_mode:ViewMode = ViewMode.FILES_TREE
var current_files:Array = []
## Draw what the export ships: follows the plugin's reduce_access_paths, with its source as the
## place hubs are kept. show_pass_through opts back out, to see what the source itself references.
var collapse_pass_through:bool = false
var keep_dirs:Array = []
var show_pass_through:bool = false
var _pending:bool = false # a Parse asked for a build the tab hasn't shown for yet

# Children are built here, not in _ready, so the host can assign click callbacks straight
# after new().
func _init() -> void:
	name = "Dep Graph"
	dep_graph = DepGraphUI.new()
	add_child(dep_graph)
	UControl.expand(dep_graph)
	dep_graph.set_edge_mode(DepGraphUI.EdgeMode.TREE)
	dep_graph.file_clicks.left_click_double = set_current_file # that file's own deps
	tools_button = GraphToolbar.setup(dep_graph)

# Deferred: during this notification the children still read as hidden in tree, so nodes built
# here measure without their rows.
func _notification(what:int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and _pending and is_visible_in_tree():
		_build_pending.call_deferred()

## Like show_files, but never takes the tab: draws now if it shows, else on its next show.
func request_files(paths:Array):
	current_files = paths
	_pending = true
	if is_visible_in_tree():
		_build_pending.call_deferred()

func _build_pending():
	if not _pending:
		return
	_pending = false
	dep_graph.focus_paths = PackedStringArray()
	_create_graph()

func set_current_file(path:String):
	show_files([path])

## show() also switches the host's TabBarContainer to this tab, so a request from another tab lands here.
func show_files(paths:Array):
	show()
	_pending = false
	current_files = paths
	dep_graph.focus_paths = PackedStringArray() # set directly: set_focus() would rebuild the old graph
	_create_graph()

## Narrows the file view to `dir`'s files and their direct users. False when none are drawn.
func focus_package(dir:String) -> bool:
	var graph = dep_graph.get_dep_graph()
	if graph == null:
		return false
	var prefix = dir.trim_suffix("/") + "/"
	var paths = graph.nodes.keys().filter(func(p:String): return p.begins_with(prefix))
	if paths.is_empty():
		return false
	dep_graph.set_focus(paths, 1)
	return true

func clear():
	dep_graph.clear_graph()
	_pending = false

func set_view_mode(mode:ViewMode):
	view_mode = mode
	# the setter rebuilds an existing graph
	dep_graph.edge_mode = DepGraphUI.EdgeMode.TREE if view_mode == ViewMode.FILES_TREE else DepGraphUI.EdgeMode.ALL

func _create_graph():
	dep_graph.v_gap = 50 * EditorInterface.get_editor_scale()
	dep_graph.h_gap = 200 * EditorInterface.get_editor_scale()
	# same tag handling as the export crawl, so a "#! gdp-dependency" file shows up here too
	dep_graph.scan_max_depth = -1
	dep_graph.scan_tag_handlers = {DependencyTags.TAG: DependencyTags.dependency_dir()}
	dep_graph.scan_ignore_line_tags = [DependencyTags.IGNORE]
	dep_graph.scan_collapse_pass_through = collapse_pass_through and not show_pass_through
	dep_graph.scan_collapse_keep_dirs = keep_dirs
	dep_graph.set_files(current_files)

func get_graph_options() -> Options:
	var options = Options.new()
	options.add_enum_radio("View", set_view_mode, VIEW_LABELS, view_mode)
	if collapse_pass_through:
		var label = "Hide Pass-Through Files" if show_pass_through else "Show Pass-Through Files"
		options.add_option(label, _toggle_pass_through)
	GraphToolbar.add_graph_options(options, dep_graph, _reset_layout)
	return options

func _reset_layout():
	dep_graph.relayout()
	dep_graph.reset_view()

func _toggle_pass_through():
	show_pass_through = not show_pass_through
	_create_graph()

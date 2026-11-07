extends VBoxContainer

const UtilsRemote = preload("res://addons/gdpackage/src/class/utils_remote.gd")
const UtilsLocal = preload("res://addons/gdpackage/src/class/utils_local.gd")
const UControl = UtilsRemote.UControl
const Options = UtilsRemote.Options
const DepGraphUI = UtilsRemote.DepGraphUI
const DependencyTags = UtilsLocal.DependencyTags


var dep_graph:DepGraphUI

var current_files:Array = []
## Draw what the export ships: follows the plugin's reduce_access_paths, with its source as the
## place hubs are kept. show_pass_through opts back out, to see what the source itself references.
var collapse_pass_through:bool = false
var keep_dirs:Array = []
var show_pass_through:bool = false

func _init() -> void:
	name = "Dependency View"

func _ready() -> void:
	dep_graph = DepGraphUI.new()
	add_child(dep_graph)
	UControl.expand(dep_graph)
	
	# create setting?
	dep_graph.set_edge_mode(DepGraphUI.EdgeMode.TREE)

func set_current_file(path:String):
	show()
	current_files = [path]
	_create_graph()

func _create_graph():
	dep_graph.v_gap = 50 * EditorInterface.get_editor_scale()
	dep_graph.h_gap = 200 * EditorInterface.get_editor_scale()
	# same tag handling as the export crawl, so a "#! dependency" file shows up here too
	dep_graph.scan_max_depth = -1
	dep_graph.scan_tag_handlers = {DependencyTags.TAG: DependencyTags.dependency_dir()}
	dep_graph.scan_ignore_line_tags = [DependencyTags.IGNORE_REMOTE]
	dep_graph.scan_collapse_pass_through = collapse_pass_through and not show_pass_through
	dep_graph.scan_collapse_keep_dirs = keep_dirs
	dep_graph.set_files(current_files)

func get_options() -> Options:
	var options = Options.new()
	options.add_option("Change View", _change_view_mode)
	if collapse_pass_through:
		var label = "Hide Pass-Through Files" if show_pass_through else "Show Pass-Through Files"
		options.add_option(label, _toggle_pass_through)
	return options

func _toggle_pass_through():
	show_pass_through = not show_pass_through
	_create_graph()

func _change_view_mode():
	var next_mode = wrapi(dep_graph.edge_mode + 1, 0, dep_graph.EdgeMode.size())
	dep_graph.set_edge_mode(next_mode)
	dep_graph.scan_max_depth = 2
	_create_graph()

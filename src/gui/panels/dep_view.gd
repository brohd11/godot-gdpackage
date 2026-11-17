extends VBoxContainer

const UtilsRemote = preload("res://addons/gdpackage/src/class/utils_remote.gd")
const UtilsLocal = preload("res://addons/gdpackage/src/class/utils_local.gd")
const UControl = UtilsRemote.UControl
const Options = UtilsRemote.Options
const DepGraphUI = UtilsRemote.DepGraphUI
const DependencyTags = UtilsLocal.DependencyTags
const PackageGraph = preload("res://addons/gdpackage/src/class/package_graph.gd")
const PackageGraphView = preload("res://addons/gdpackage/src/gui/panels/package_graph_view.gd")
const RequireReport = preload("res://addons/gdpackage/src/class/release/require_report.gd")

enum ViewMode { FILES_TREE, FILES_ALL, PACKAGES }
const VIEW_LABELS = {"Files - Tree": ViewMode.FILES_TREE, "Files - All": ViewMode.FILES_ALL, "Packages": ViewMode.PACKAGES}

## Double-click on a package node; the host owns the export files the drill-in needs.
signal package_drill_in(dir:String)

var dep_graph:DepGraphUI
var package_graph:PackageGraphView
var status_label:Label

var view_mode:ViewMode = ViewMode.FILES_TREE
var current_files:Array = []
## Draw what the export ships: follows the plugin's reduce_access_paths, with its source as the
## place hubs are kept. show_pass_through opts back out, to see what the source itself references.
var collapse_pass_through:bool = false
var keep_dirs:Array = []
var show_pass_through:bool = false

var package_dir:String = ""
var include_test_requires:bool = false
var _package_index = null # repo_id -> dir; null until first needed, since it runs git per repo
var _package_graph_dirty:bool = true
## Files per package come from RequireReport: the export's dependency crawl over the source
## (ExportData, nothing written). Seconds long, so opt-in.
var show_package_files:bool = false
var _usage_report = null # RequireReport.build() for package_dir; null until first needed
var _crawling:bool = false

func _init() -> void:
	name = "Dependency View"

func _ready() -> void:
	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.hide()
	add_child(status_label)

	dep_graph = DepGraphUI.new()
	add_child(dep_graph)
	UControl.expand(dep_graph)
	dep_graph.set_edge_mode(DepGraphUI.EdgeMode.TREE)

	package_graph = PackageGraphView.new()
	add_child(package_graph)
	UControl.expand(package_graph)
	package_graph.package_activated.connect(package_drill_in.emit)
	package_graph.file_activated.connect(set_current_file)
	_apply_view_mode()

func set_current_file(path:String):
	show_files([path])

## Switches out of the package view, so a file request is always visible.
func show_files(paths:Array):
	show()
	current_files = paths
	dep_graph.focus_paths = PackedStringArray() # set directly: set_focus() would rebuild the old graph
	if view_mode == ViewMode.PACKAGES:
		view_mode = ViewMode.FILES_TREE
		_apply_view_mode()
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

func set_package_dir(dir:String):
	package_dir = dir
	_usage_report = null
	_package_graph_dirty = true
	if view_mode == ViewMode.PACKAGES:
		_create_package_graph()

func clear():
	dep_graph.clear_graph()
	package_graph.clear_graph()
	_usage_report = null
	_package_graph_dirty = true

func set_view_mode(mode:ViewMode):
	view_mode = mode
	_apply_view_mode()

func _apply_view_mode():
	var packages = view_mode == ViewMode.PACKAGES
	package_graph.visible = packages
	dep_graph.visible = not packages
	if packages:
		if _package_graph_dirty:
			_create_package_graph()
	else:
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

func _create_package_graph():
	_package_graph_dirty = false
	if package_dir == "":
		package_graph.clear_graph()
		return
	if _package_index == null:
		_package_index = PackageGraph.ExternalDeps.local_index()
	var data = PackageGraph.build(package_dir, {"index": _package_index, "include_tests": include_test_requires})
	for error in data.errors:
		push_warning("GDPackage: " + error)
	if show_package_files:
		if _usage_report == null:
			if _crawling:
				return # the crawl in flight rebuilds when it lands
			await _crawl_usage()
			# rebuild from current settings: the package or toggles may have changed meanwhile
			_create_package_graph()
			return
		PackageGraph.apply_usage(data, _usage_report)
	package_graph.set_graph(data)

## The crawl blocks the editor; the label gets two frames to paint first.
func _crawl_usage():
	_crawling = true
	var dir = package_dir
	status_label.text = "Crawling %s dependencies for used files..." % PackageGraph.display_name(dir)
	status_label.show()
	await get_tree().process_frame
	await get_tree().process_frame
	var report = RequireReport.build(dir)
	status_label.hide()
	_crawling = false
	if dir != package_dir:
		return
	for error in report.errors:
		push_warning("GDPackage: " + error)
	_usage_report = report

func get_options() -> Options:
	var options = Options.new()
	options.add_enum_radio("View", set_view_mode, VIEW_LABELS, view_mode)
	if view_mode == ViewMode.PACKAGES:
		options.add_radio_option("Show All Edges", _toggle_all_edges, package_graph.show_all_edges)
		options.add_radio_option("Include Test Requires", _toggle_test_requires, include_test_requires)
		options.add_radio_option("Show Used Files (slow crawl)", _toggle_package_files, show_package_files)
		options.add_option("Refresh Packages", _refresh_packages)
	elif collapse_pass_through:
		var label = "Hide Pass-Through Files" if show_pass_through else "Show Pass-Through Files"
		options.add_option(label, _toggle_pass_through)
	return options

func _toggle_pass_through():
	show_pass_through = not show_pass_through
	_create_graph()

func _toggle_all_edges():
	package_graph.show_all_edges = not package_graph.show_all_edges

func _toggle_test_requires():
	include_test_requires = not include_test_requires
	_create_package_graph()

func _toggle_package_files():
	show_package_files = not show_package_files
	_create_package_graph()

## Re-runs the repo index and the file crawl too, for a checkout added or re-pointed since the first build.
func _refresh_packages():
	_package_index = null
	_usage_report = null
	_create_package_graph()

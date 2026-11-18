extends VBoxContainer
## The package graph tab: packages from declared requires, optionally with the files each one
## contributes. Built only after a Parse, and only once the tab shows: indexing the local checkouts
## runs git per repo.

const UtilsRemote = preload("res://addons/gdpackage/src/class/utils_remote.gd")
const UControl = UtilsRemote.UControl
const Options = UtilsRemote.Options
const PackageGraph = preload("res://addons/gdpackage/src/class/package_graph.gd")
const PackageGraphView = preload("res://addons/gdpackage/src/gui/panels/package_graph_view.gd")
const RequireReport = preload("res://addons/gdpackage/src/class/release/require_report.gd")
const GraphToolbar = preload("res://addons/gdpackage/src/gui/panels/graph_toolbar.gd")

var package_graph:PackageGraphView
var tools_button:Button
var status_label:Label

var package_dir:String = ""
var include_test_requires:bool = false
var _package_index = null # repo_id -> dir; null until first needed, since it runs git per repo
var _pending:bool = false # a Parse asked for a build the tab hasn't shown for yet
## Files per package come from RequireReport: the export's dependency crawl over the source
## (ExportData, nothing written). Seconds long, so opt-in.
var show_package_files:bool = false
var _usage_report = null # RequireReport.build() for package_dir; null until first needed
var _crawling:bool = false

# Children are built here, not in _ready, so the host can assign click callbacks straight
# after new().
func _init() -> void:
	name = "Packages"
	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.hide()
	add_child(status_label)

	package_graph = PackageGraphView.new()
	add_child(package_graph)
	UControl.expand(package_graph)
	tools_button = GraphToolbar.setup(package_graph)

# Deferred: during this notification the children still read as hidden in tree, so nodes built
# here measure without their rows and the layout stacks them on top of each other.
func _notification(what:int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and _pending and is_visible_in_tree():
		_build_pending.call_deferred()

func set_package_dir(dir:String):
	package_dir = dir
	_usage_report = null

## Draws now if the tab shows, else on its next show.
func request_build():
	_pending = true
	if is_visible_in_tree():
		_build_pending.call_deferred()

func _build_pending():
	if not _pending:
		return
	_pending = false
	_create_package_graph()

func clear():
	package_graph.clear_graph()
	_usage_report = null
	_pending = false

func _create_package_graph():
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

func get_graph_options() -> Options:
	var options = Options.new()
	options.add_radio_option("Show All Edges", _toggle_all_edges, package_graph.show_all_edges)
	options.add_radio_option("Include Test Requires", _toggle_test_requires, include_test_requires)
	options.add_radio_option("Show Used Files (slow crawl)", _toggle_package_files, show_package_files)
	options.add_option("Refresh Packages", _refresh_packages)
	GraphToolbar.add_graph_options(options, package_graph, package_graph.reset_layout)
	return options

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

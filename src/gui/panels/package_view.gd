extends VBoxContainer
## The package graph tab: packages from declared requires, optionally with the files each one
## contributes. Built lazily on first show, since indexing the local checkouts runs git per repo.

const UtilsRemote = preload("res://addons/gdpackage/src/class/utils_remote.gd")
const UControl = UtilsRemote.UControl
const Options = UtilsRemote.Options
const PackageGraph = preload("res://addons/gdpackage/src/class/package_graph.gd")
const PackageGraphView = preload("res://addons/gdpackage/src/gui/panels/package_graph_view.gd")
const RequireReport = preload("res://addons/gdpackage/src/class/release/require_report.gd")

var package_graph:PackageGraphView
var status_label:Label

var package_dir:String = ""
var include_test_requires:bool = false
var _package_index = null # repo_id -> dir; null until first needed, since it runs git per repo
var _package_graph_dirty:bool = true
## Files per package come from RequireReport: the export's dependency crawl over the source
## (ExportData, nothing written). Seconds long, so opt-in.
var show_package_files:bool = false
var _usage_report = null # RequireReport.build() for package_dir; null until first needed
var _crawling:bool = false

# Children are built here, not in _ready, so the host can assign click callbacks straight
# after new().
func _init() -> void:
	name = "Package View"
	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.hide()
	add_child(status_label)

	package_graph = PackageGraphView.new()
	add_child(package_graph)
	UControl.expand(package_graph)

func _notification(what:int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_visible_in_tree() and _package_graph_dirty:
		_create_package_graph()

func set_package_dir(dir:String):
	package_dir = dir
	_usage_report = null
	_package_graph_dirty = true
	if is_visible_in_tree():
		_create_package_graph()

func clear():
	package_graph.clear_graph()
	_usage_report = null
	_package_graph_dirty = true

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
	options.add_radio_option("Show All Edges", _toggle_all_edges, package_graph.show_all_edges)
	options.add_radio_option("Include Test Requires", _toggle_test_requires, include_test_requires)
	options.add_radio_option("Show Used Files (slow crawl)", _toggle_package_files, show_package_files)
	options.add_option("Refresh Packages", _refresh_packages)
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

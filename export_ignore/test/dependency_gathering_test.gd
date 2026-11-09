@tool
extends EditorScript
## Exercises the real export crawl and rewrites. The exporter requires editor services, so this runs
## in the editor console or test CI's headless editor, not run_headless.gd.

const DIR = "user://pe_gathering_tests/"
const UtilsLocal = preload("res://addons/gdpackage/src/class/utils_local.gd")
const FileUtils = UtilsLocal.ExportFileUtils
const Keys = FileUtils.KeysData

static var _failures:Array[String] = []
static var _passed:int = 0


static func run_tests() -> Dictionary:
	if not Engine.is_editor_hint():
		return {"result": 0, "output": ["dependency_gathering: skipped (editor only)"]}
	_failures = []
	_passed = 0
	_clear_fixtures(DIR)
	_test_roots_and_recursion()
	_test_ignores_and_rewrites()
	_test_classes_and_reduction()
	_test_replacement()
	_test_uid_sidecars()
	_test_scan_consumers()
	_test_destinations()
	_test_destination_provenance()
	_test_relocated_declarations()
	_test_destination_chains()
	_test_invalid_destinations()
	_test_other_transfers()
	_test_adjacent_tests()
	_clear_fixtures(DIR)
	var output:Array = ["dependency_gathering: %d passed, %d failed" % [_passed, _failures.size()]]
	output.append_array(_failures)
	return {"result": _failures.size(), "output": output}


func _run() -> void:
	print("\n".join(run_tests().output))


static func _test_roots_and_recursion() -> void:
	var leaf = _w("external/leaf.gd", "extends RefCounted\n")
	var branch = _w("external/branch.gd", 'const Leaf = preload("./leaf.gd")\n')
	var optional = _w("external/optional.gd", "extends RefCounted\n")
	var root = _w("plugin/plain.gd", 'const Branch = preload("%s")\nvar optional = load("%s")\n' % [branch, optional])
	var export = _crawl([root])
	_check("untagged script seeded", export.files_to_scan_for_deps.has(root), true)
	_check("direct dependency copied", export.files_to_copy.has(branch), true)
	_check("transitive dependency copied", export.files_to_copy.has(leaf), true)
	_check("load stays opt-in", export.files_to_copy.has(optional), false)
	_w("plugin/plain.gd", 'var optional = load("%s") #! dependency current\n' % optional)
	export = _crawl([root])
	_check("tagged load copied", export.files_to_copy.has(optional), true)
	_check("tag placement retained", export.adjusted_remote_paths.get(optional), DIR + "plugin/optional.gd")
	_w("external/branch.gd", 'const Leaf = preload("./leaf.gd")\nconst Root = preload("%s")\n' % root)
	_w("plugin/plain.gd", 'const Branch = preload("%s")\nconst Leaf = preload("%s")\n' % [branch, leaf])
	export = _crawl([root])
	_check("cycle terminates with shared leaf", export.files_to_copy.size(), 3)
	var scene = _w("plugin/plain.tscn", '[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="%s" id="1"]\n' % leaf)
	_check("scene gathers scripts", _crawl([scene]).files_to_copy.has(leaf), true)


static func _test_ignores_and_rewrites() -> void:
	var leaf = _w("external/ignored.gd", "extends RefCounted\n")
	var root = _w("plugin/ignored.gd", 'const Leaf = preload("%s") #! ignore-remote\n' % leaf)
	var export = _crawl([root])
	_check("ignored preload absent", export.files_to_copy.has(leaf), false)
	var ignored_line = 'const Leaf = preload("%s") #! ignore-remote' % leaf
	_w("plugin/ignored.gd", ignored_line + '\nconst Other = preload("%s")\n' % leaf)
	export = _crawl([root])
	_check("unignored occurrence still copies", export.files_to_copy.has(leaf), true)
	var parser = export.file_parser.default_parsers.gd
	export.file_parser.current_file_path_parsing = root
	export.file_parser.current_adjusted_file_path = "res://addons/test/ignored.gd"
	export.adjusted_remote_paths[leaf] = "res://addons/test/remote/ignored.gd"
	for relative in [false, true]:
		export.use_relative_paths = relative
		_check("ignored path untouched relative=%s" % relative, parser._update_paths(ignored_line), ignored_line)
		_check("unignored path rewritten relative=%s" % relative,
			parser._update_paths('const Other = preload("%s")' % leaf).contains(leaf), false)
	export.use_relative_paths = true
	var target = export.adjusted_remote_paths[leaf]
	var mixed = 'const P = preload("%s"); var a = load("%s"); var b = ResourceLoader.load("%s")' % [leaf, leaf, leaf]
	_check("runtime loads stay absolute beside a relative preload", parser._update_paths(mixed),
		'const P = preload("%s"); var a = load("%s"); var b = ResourceLoader.load("%s")' % [export.get_rel_or_absolute_path(target), target, target])
	_w("plugin/ignored.gd", '#! ignore-remote\nconst Leaf = preload("%s")\n' % leaf)
	_check("header does not disable file", _crawl([root]).files_to_copy.has(leaf), true)


static func _test_classes_and_reduction() -> void:
	var leaf = _w("external/class_leaf.gd", "extends RefCounted\n")
	var hub = _w("external/hub.gd", 'const Leaf = preload("./class_leaf.gd")\n')
	var root = _w("plugin/classes.gd", "var optional = Hub.Leaf #! ignore-remote\n")
	var classes = {"Hub": hub}
	var export = _crawl([root], classes, true)
	_check("ignored class absent", export.global_classes_used.has("Hub"), false)
	_check("ignored access target absent", export.files_to_copy.has(leaf), false)
	_check("ignored reduction absent", export.access_reductions.get(root, {}).is_empty(), true)
	_w("plugin/classes.gd", "var optional = Hub.Leaf #! ignore-remote\nvar included = Hub.Leaf\n")
	export = _crawl([root], classes, true)
	_check("unignored reduction copied", export.files_to_copy.has(leaf), true)
	_check("ignored use does not retain hub", export.files_to_copy.has(hub), false)
	_check("unignored reduction recorded", export.access_reductions.get(root, {}).has("Hub.Leaf"), true)
	_w("plugin/classes.gd", "var included = Hub\nvar optional = Hub #! ignore-remote\n")
	export = _crawl([root], classes)
	_check("unignored global copied", export.files_to_copy.has(hub), true)
	var data = FileUtils._get_global_classes_in_text(
		"class_name Own extends Hub #! ignore-remote\n", {"Own": root, "Hub": hub})
	_check("ignored header preserves declaration", data, {"global_class_definition": "Own"})
	var ignored_binding = 'const Hub = preload("%s") #! ignore-remote' % hub
	var lines = [ignored_binding, "var included = Hub"]
	_w("plugin/classes.gd", "\n".join(lines))
	export = _crawl([root], classes)
	export.class_renames = classes.duplicate()
	export.file_parser.current_file_path_parsing = root
	var rendered = export.file_parser.default_parsers.gd.post_export_edit_file(root, lines)
	_check("ignored binding not injected twice", "\n".join(rendered).count("const Hub ="), 1)
	_check("ignored binding text preserved", rendered[0], ignored_binding)
	_w("plugin/classes.gd", "var ignored = Hub #! ignore-remote\n")
	export = _crawl([root], classes)
	export.class_renames = classes.duplicate()
	export.file_parser.current_file_path_parsing = root
	rendered = export.file_parser.default_parsers.gd.post_export_edit_file(root)
	_check("ignored global does not inject preload", "\n".join(rendered).contains("preload("), false)


static func _test_replacement() -> void:
	var leaf = _w("external/replacement_leaf.gd", "extends RefCounted\n")
	var base = _w("external/base.gd", 'const Leaf = preload("./replacement_leaf.gd")\n')
	var stub = _w("plugin/stub.gd", '#! remote\nextends "%s"\n' % base)
	var export = _crawl([stub])
	_check("remote stub replacement retained", export.files_to_copy[stub].get(Keys.REPLACE_WITH), base)
	_check("replacement base not copied twice", export.files_to_copy.has(base), false)
	_check("replacement dependency copied", export.files_to_copy.has(leaf), true)
	_check("base references redirected to stub", export.adjusted_remote_paths.get(base), stub)
	_w("plugin/stub.gd", '#! remote\nextends "%s" #! ignore-remote\n' % base)
	export = _crawl([stub])
	_check("ignored extends does not replace", export.files_to_copy[stub].has(Keys.REPLACE_WITH), false)
	_check("ignored extends does not gather", export.files_to_copy.has(base), false)
	_w("plugin/stub.gd", 'extends "%s"\n' % base)
	export = _crawl([stub])
	_check("ordinary extends keeps original script", export.files_to_copy[stub].has(Keys.REPLACE_WITH), false)
	_check("ordinary extends gathers base", export.files_to_copy.has(base), true)


static func _test_uid_sidecars() -> void:
	var local = _w("plugin/uid_local.gd", "extends RefCounted\n")
	var global = _w("plugin/uid_global.gd", "class_name PEUIDGlobal extends RefCounted\n")
	var external = ProjectSettings.globalize_path(_w("external/uid_external.gd", "extends RefCounted\n"))
	var base = ProjectSettings.globalize_path(_w("external/uid_base.gd", "extends RefCounted\n"))
	var stub = _w("plugin/uid_stub.gd", '#! remote\nextends "%s"\n' % base)
	var backport = _w("external/uid_backport.gd", "extends RefCounted\n")
	var root = _w("plugin/uid_root.gd", 'const Local = preload("./uid_local.gd")\nconst External = preload("%s")\nvar type = PEUIDGlobal\n' % external)
	var originals = {}
	for path in [root, local, global, external, base, stub, backport]:
		var uid = ResourceUID.id_to_text(ResourceUID.create_id()) + "\n"
		var file = FileAccess.open(path + ".uid", FileAccess.WRITE)
		file.store_string(uid)
		file.close()
		originals[path] = uid
	for include_uid in [true, false]:
		_clear_fixtures(DIR + "out/")
		var export = _crawl([root, local, global, stub], {"PEUIDGlobal": global})
		export.export_data.include_uid = include_uid
		export.unique_files.append(backport)
		export.files_to_copy[backport] = {Keys.TO: DIR + "out/uid_backport.gd"}
		export.file_parser.set_parser_settings({})
		export.file_parser.pre_export()
		export.export_files()
		var label = "uid include=%s: " % include_uid
		_check(label + "export valid", export.export_valid, true)
		for path in [root, local, global]:
			var target:String = export.files_to_copy[path][Keys.TO] + ".uid"
			_check(label + "source sidecar " + path.get_file(), FileAccess.file_exists(target), include_uid)
			if include_uid:
				_check(label + "source UID preserved " + path.get_file(), FileAccess.get_file_as_string(target), originals[path])
		for path in [external, stub, backport]:
			var target:String = export.files_to_copy[path][Keys.TO] + ".uid"
			_check(label + "bundled sidecar " + path.get_file(), FileAccess.file_exists(target), true)
			var uid = FileAccess.get_file_as_string(target).strip_edges()
			_check(label + "bundled UID valid " + path.get_file(), ResourceUID.text_to_id(uid) != ResourceUID.INVALID_ID, true)
			_check(label + "bundled UID replaced " + path.get_file(), uid != originals[path].strip_edges(), true)
			if path == stub:
				_check(label + "replacement base UID replaced", uid != originals[base].strip_edges(), true)


static func _test_scan_consumers() -> void:
	var leaf = _w("external/consumer_leaf.gd", "extends RefCounted\n")
	var root = _w("plugin/consumer.gd", 'const Leaf = preload("%s") #! ignore-remote\n' % leaf)
	var report = load("res://addons/gdpackage/src/class/release/require_report.gd")
	_check("require ignores tagged edge", report._scan_files([root], {}).has(leaf), false)
	var view = load("res://addons/gdpackage/src/gui/panels/dep_view.gd").new()
	Engine.get_main_loop().root.add_child(view)
	view.set_current_file(root)
	_check("dependency view ignores tagged edge", view.dep_graph.get_dep_graph().has(leaf), false)
	_w("plugin/consumer.gd", 'const Leaf = preload("%s") #! ignore-remote\nconst Other = preload("%s")\n' % [leaf, leaf])
	_check("require retains other reference", report._scan_files([root], {}).has(leaf), true)
	view.set_current_file(root)
	_check("dependency view retains other reference", view.dep_graph.get_dep_graph().has(leaf), true)
	view.queue_free()


static func _test_destinations() -> void:
	var asset = _w("external/source_font.LICENSE.txt", "font license\n")
	# Remote paths embed the original path; user:// is not a project resource prefix.
	var branch = ProjectSettings.globalize_path(_w("external/console.gd", ""))
	var root = _w("plugin/main.gd", 'const Console = preload("%s")\n' % branch)
	for renamed in [false, true]:
		for destination in ["licenses/font/LICENSE", "./licenses/font/LICENSE", "../licenses/font/LICENSE", "current", ".", "<package>/licenses/font/LICENSE", DIR + "plugin/licenses/font/LICENSE"]:
			var line = 'const LICENSE = "%s" #! dependency %s' % [asset, destination]
			_w("external/console.gd", line + "\n")
			var export = _crawl([root], {}, false, renamed)
			var declaring_dest:String = export.get_remote_file_local_path(branch)
			var expected:String
			if destination == "current" or destination == ".":
				expected = declaring_dest.get_base_dir().path_join(asset.get_file())
			elif destination.begins_with("<package>") or destination.is_absolute_path():
				expected = export.source.path_join("licenses/font/LICENSE")
			else:
				expected = declaring_dest.get_base_dir().path_join(destination).simplify_path()
			var label = "%s renamed=%s" % [destination, renamed]
			_check(label + " valid", export.export_valid, true)
			_check(label + " copy destination", export.files_to_copy.get(asset, {}).get(Keys.TO), export.get_export_path(expected))
			_check(label + " installed reference", export.adjusted_remote_paths.get(asset), export.get_renamed_path(expected))
			export.file_parser.current_file_path_parsing = branch
			var parser = export.file_parser.default_parsers.gd
			_check(label + " rewritten constant", parser._update_paths(line), line.replace(asset, export.get_renamed_path(expected)))
			export.use_relative_paths = true
			var relative_line:String = parser._update_paths(line)
			var reference = relative_line.get_slice('"', 1)
			var installed_branch:String = export.adjusted_remote_paths[branch]
			_check(label + " relative reference resolves", installed_branch.get_base_dir().path_join(reference).simplify_path(), export.get_renamed_path(expected))
			if destination == "<package>/licenses/font/LICENSE":
				var copy_path:String = export.files_to_copy[asset][Keys.TO]
				export._simple_export(asset, copy_path, false, false)
				_check(label + " renamed file contents", FileAccess.get_file_as_string(copy_path), "font license\n")
				_check(label + " old filename not copied", FileAccess.file_exists(copy_path.get_base_dir().path_join(asset.get_file())), false)


static func _test_destination_provenance() -> void:
	var asset = _w("external/shared.txt", "shared\n")
	var tagged = _w("plugin/nested/tagged.gd", 'const Asset = "%s" #! dependency nearby/shared.txt\n' % asset)
	var plain = _w("plugin/plain_reference.gd", 'const Asset = "%s" #! dependency\n' % asset)
	for roots in [[tagged, plain], [plain, tagged]]:
		var export = _crawl(roots)
		_check("tag provenance survives plain reference", export.file_dependencies[asset].get(Keys.DEPENDENCY_SOURCE), tagged)
		_check("placement independent of plain reference order", export.adjusted_remote_paths.get(asset), DIR + "plugin/nested/nearby/shared.txt")
	var second = _w("plugin/second.gd", 'const Asset = "%s" #! dependency last/shared.txt\n' % asset)
	_check("last explicit destination wins", _crawl([tagged, second]).adjusted_remote_paths.get(asset), DIR + "plugin/last/shared.txt")


static func _test_relocated_declarations() -> void:
	var asset = _w("external/relocated.txt", "relocated\n")
	var base = _w("external/declaring_base.gd", 'const Asset = "%s" #! dependency current\n' % asset)
	var stub = _w("plugin/sub/stub.gd", '#! remote\nextends "%s"\n' % base)
	var export = _crawl([stub], {}, false, true)
	_check("current follows replacement stub", export.adjusted_remote_paths.get(asset), "res://addons/pe_renamed/sub/relocated.txt")
	var root = _w("plugin/global_user.gd", "var moved = Moved\n")
	export = _crawl([root], {"Moved": base})
	_check("declaration relocated as global", export.adjusted_remote_paths.get(base), DIR + "plugin/global/declaring_base.gd")
	_check("relative follows global relocation", export.adjusted_remote_paths.get(asset), DIR + "plugin/global/relocated.txt")


static func _test_destination_chains() -> void:
	var asset = _w("external/chained.txt", "chained\n")
	var child = _w("external/child.gd", 'const Asset = "%s" #! dependency current\n' % asset)
	var parent = _w("external/parent.gd", 'const Child = preload("%s") #! dependency children/renamed_child.gd\n' % child)
	var root = _w("plugin/chain.gd", 'const Parent = preload("%s") #! dependency <package>/placed/renamed_parent.gd\n' % parent)
	var plain = _w("plugin/early.gd", 'const Child = preload("%s")\n' % child)
	for roots in [[root, plain], [plain, root]]:
		var export = _crawl(roots, {}, false, true)
		_check("chained destination valid", export.export_valid, true)
		_check("chained parent renamed", export.adjusted_remote_paths.get(parent), "res://addons/pe_renamed/placed/renamed_parent.gd")
		_check("chained child renamed", export.adjusted_remote_paths.get(child), "res://addons/pe_renamed/placed/children/renamed_child.gd")
		_check("chained destination follows parent", export.adjusted_remote_paths.get(asset), "res://addons/pe_renamed/placed/children/chained.txt")
		_check("chained copy inside package", export.files_to_copy.get(asset, {}).get(Keys.TO), DIR + "out/placed/children/chained.txt")


static func _test_invalid_destinations() -> void:
	var asset = _w("external/invalid.txt", "invalid\n")
	for destination in ["<package>/../escape", "../escape", "res://addons/gdpackage/licenses/source_font/LICENSE", "<package>/licenses/"]:
		var root = _w("plugin/invalid.gd", 'const Asset = "%s" #! dependency %s\n' % [asset, destination])
		var export = _crawl([root])
		_check("invalid destination aborts: " + destination, export.export_valid, false)
		_check("invalid destination not copied: " + destination, export.files_to_copy.has(asset), false)
		_check("invalid destination not rewritten: " + destination, export.adjusted_remote_paths.has(asset), false)
	var a = _w("external/cycle_a.gd", "")
	var b = _w("external/cycle_b.gd", 'const A = preload("%s") #! dependency current\n' % a)
	_w("external/cycle_a.gd", 'const B = preload("%s") #! dependency current\n' % b)
	var root = _w("plugin/cycle.gd", 'const A = preload("%s")\n' % a)
	var export = _crawl([root])
	_check("placement cycle aborts", export.export_valid, false)
	_check("cycle a not copied", export.files_to_copy.has(a), false)
	_check("cycle b not copied", export.files_to_copy.has(b), false)


static func _test_other_transfers() -> void:
	var leaf = _w("external/transfer_leaf.gd", "extends RefCounted\n")
	var klass = _w("external/transfer_class.gd", "extends RefCounted\n")
	var top = _w("bundle/top.gd", 'const Leaf = preload("%s")\nvar used = TransferClass\n' % leaf)
	var nested = _w("bundle/sub/nested.gd", "extends RefCounted\n")
	var classes = {"TransferClass": klass}
	var row = {Keys.FROM: DIR + "bundle", Keys.TO: "bundled", Keys.RECURSIVE: true, Keys.IGNORE_DEPS: true}
	var export = _transfer([row], classes)
	_check("transfer valid", export.export_valid, true)
	_check("recursive keeps subpath", export.valid_files_for_transfer.get(nested, {}).get(Keys.TO), DIR + "out/bundled/sub/nested.gd")
	_check("recursive installed path", export.adjusted_remote_paths.get(nested), DIR + "plugin/bundled/sub/nested.gd")
	_check("ignore_deps flagged", export.file_deps_ignored(top), true)
	_check("ignore_deps file still copied", export.files_to_copy.has(top), true)
	_check("ignore_deps skips preloads", export.files_to_copy.has(leaf), false)
	_check("ignore_deps skips global classes", export.global_classes_used.has("TransferClass"), false)
	export = _transfer([{Keys.FROM: DIR + "bundle", Keys.TO: "bundled"}], classes)
	_check("non-recursive skips subdirs", export.valid_files_for_transfer.has(nested), false)
	_check("non-recursive top file", export.valid_files_for_transfer.get(top, {}).get(Keys.TO), DIR + "out/bundled/top.gd")
	_check("scanned transfer gathers preload", export.files_to_copy.has(leaf), true)
	_check("scanned transfer gathers class", export.global_classes_used.has("TransferClass"), true)
	export = _transfer([{Keys.FROM: top, Keys.TO: "same.gd"}, {Keys.FROM: nested, Keys.TO: "same.gd"}])
	_check("shared destination aborts", export.export_valid, false)
	_check("shared destination not copied", export.valid_files_for_transfer.is_empty(), true)
	_check("shared destination reported", export.reporter.count(UtilsLocal.Reporter.Level.ERROR), 1)


static func _test_adjacent_tests() -> void:
	var leaf = _w("external/test_only.gd", "extends RefCounted\n")
	var root = _w("plugin/adjacent/main.gd", "extends RefCounted\n")
	var test = _w("plugin/adjacent/helper_test.gd", 'const Leaf = preload("%s")\n' % leaf)
	var gut = _w("plugin/adjacent/test_gut.gd", "extends GutTest\n")
	var gdunit = _w("plugin/adjacent/checks.gd", "extends GdUnitTestSuite\n")
	var base = _w("plugin/adjacent/base.gd", "class_name AdjacentBase extends GutTest\n")
	var derived = _w("plugin/adjacent/derived.gd", 'extends "base.gd"\n')
	var source_files = [root, test, gut, gdunit, base, derived, _w("plugin/adjacent/helper_test.gd.uid", "uid://c7sn8pjof4g7x")]
	var export = _select(source_files, {"AdjacentBase": base})
	_check("ignore_tests defaults true", export.export_data.ignore_tests, true)
	_check("adjacent tests excluded", export.files_to_copy.keys(), [root])
	_check("custom bases detected without registered classes", _select(source_files).files_to_copy.keys(), [root])
	_check("excluded tests never seed dependency crawl", export.file_dependencies.has(leaf), false)
	_check("test sidecar excluded", export.files_to_copy.has(test + ".uid"), false)
	export = _select([root, test], {}, {"ignore_tests": false})
	_check("explicit false keeps tests", export.files_to_copy.has(test), true)
	_check("kept tests gather their dependencies", export.files_to_copy.has(leaf), true)
	export = _select([root, test], {}, {"ignore_tests": true})
	_check("explicit true excludes tests", export.files_to_copy.has(test), false)
	_w("plugin/adjacent/main.gd", 'const Required = preload("./helper_test.gd")\n')
	export = _select([root, test])
	_check("required local test restored", export.files_to_copy.has(test), true)
	_check("required test keeps local destination", export.files_to_copy[test][Keys.TO], export.get_export_path(test))
	_check("required test dependency restored", export.files_to_copy.has(leaf), true)
	var id = ResourceUID.create_id()
	ResourceUID.add_id(id, test)
	_w("plugin/adjacent/main.gd", 'const Required = preload("%s")\n' % ResourceUID.id_to_text(id))
	export = _select([root, test])
	_check("UID dependency restores test", export.files_to_copy.has(test), true)
	ResourceUID.remove_id(id)
	var scene = _w("plugin/adjacent/root.tscn", '[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="%s" id="1"]\n' % test)
	_check("scene reference restores test", _select([scene, test]).files_to_copy.has(test), true)
	var hub = _w("external/test_hub.gd", 'const Subject = preload("%s")\n' % test)
	_w("plugin/adjacent/main.gd", "var required = AdjacentHub.Subject\n")
	export = _select([root, test], {"AdjacentHub": hub}, {}, [], [], true)
	_check("access reduction restores local test", export.files_to_copy.has(test), true)
	_check("access reduction excludes unused hub", export.files_to_copy.has(hub), false)
	var bridge = _w("plugin/adjacent/bridge.gd", 'const Required = preload("helper_test.gd")\n')
	_w("plugin/adjacent/main.gd", 'const Bridge = preload("bridge.gd")\n')
	export = _select([root, bridge, test])
	_check("transitive local test restored", export.files_to_copy.has(test), true)
	var global_test = _w("plugin/adjacent/global_test.gd", "class_name AdjacentGlobal\nextends RefCounted\n")
	_w("plugin/adjacent/main.gd", "var required = AdjacentGlobal\n")
	export = _select([root, global_test], {"AdjacentGlobal": global_test})
	_check("global-class dependency restores test", export.files_to_copy.has(global_test), true)
	export = _select([root, test], {}, {}, [test])
	_check("explicit excludes retain existing semantics", export.ignored_tests.has(test), false)
	export = _select([root, test], {}, {}, [], [{"from": test, "to": "explicit_test.gd"}])
	_check("explicit transfer retains a test", export.files_to_copy.has(test), true)


static func _select(files:Array, classes:Dictionary = {}, options:Dictionary = {}, excluded:Array = [], transfers:Array = [], reduce:bool = false):
	var export = _crawl([], classes, reduce)
	export.export_data.ignore_tests = options.get("ignore_tests", true)
	export.source_files = files
	export.exclude_directories = []
	export.exclude_file_extensions = []
	export.exclude_files = excluded
	export.other_transfers = transfers
	export.get_valid_files_for_transfer()
	export.sort_valid_files()
	export.get_global_classes_used_in_valid_files()
	export.get_file_dependencies()
	export.get_global_class_export_paths()
	export.resolve_dependency_placements()
	return export


static func _transfer(transfers:Array, classes:Dictionary = {}):
	var export = _crawl([], classes)
	export.other_transfers = transfers
	export.get_valid_files_for_transfer()
	export.sort_valid_files()
	export.get_global_classes_used_in_valid_files()
	export.get_file_dependencies()
	export.get_global_class_export_paths()
	export.resolve_dependency_placements()
	return export


static func _crawl(roots:Array, classes:Dictionary = {}, reduce:bool = false, renamed:bool = false):
	var config = _w("config.json", JSON.stringify({
		"export_root": DIR + "out", "plugin_folder": "test", "options": {}, "exports": []}))
	var data = UtilsLocal.ExportData.new(config)
	data.class_list = classes
	data.class_list_array = classes.keys()
	var export = UtilsLocal.ExportObj.new()
	export.export_data = data
	export.source = DIR + "plugin/"
	export.plugin_name = export.source
	export.rename_plugin = renamed
	export.new_plugin_name = "res://addons/pe_renamed/"
	export.remote_dir = export.source + "remote"
	export.export_dir_path = DIR + "out/"
	export.reduce_access_paths = reduce
	export.file_parser = UtilsLocal.FileParser.new()
	export.file_parser.set_export_obj(export)
	for root in roots:
		export.valid_files_for_transfer[root] = {Keys.TO: DIR + "out/" + root.trim_prefix(export.source)}
	export.sort_valid_files()
	export.get_global_classes_used_in_valid_files()
	export.get_file_dependencies()
	export.get_global_class_export_paths()
	export.resolve_dependency_placements()
	return export


static func _w(relative:String, text:String) -> String:
	var path = DIR + relative
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	return path


static func _check(label:String, actual, expected) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failures.append("FAIL %s: expected %s, got %s" % [label, expected, actual])


static func _clear_fixtures(dir:String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for name in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(name))
	for name in DirAccess.get_directories_at(dir):
		_clear_fixtures(dir.path_join(name))
	DirAccess.remove_absolute(dir)

@tool
extends EditorScript
## require consumers: every package declaring a repo, through cfg require=, compile_require or
## test_require, matched by repo_id whatever spelling the target uses.

const RequireConsumers = preload("res://addons/package_exporter/src/class/release/require_consumers.gd")
const ROOT = "user://pe_require_consumers_tests"

static var _failures:Array[String] = []
static var _passed:int = 0


static func run_tests() -> Dictionary:
	_failures = []
	_passed = 0
	_test_find()
	var output:Array[String] = ["require_consumers: %d passed, %d failed" % [_passed, _failures.size()]]
	for failure in _failures:
		output.append("  FAIL  " + failure)
	return {"result": _failures.size(), "output": output}


func _run() -> void: # EditorScript entry, for running this from the editor
	print("\n".join(run_tests().output))


static func _test_find() -> void:
	var root = ProjectSettings.globalize_path(ROOT)
	_remove(root)
	_write(root.path_join("cfg_only/plugin.cfg"), '[plugin]\nrequire=[\n"a/lib@v1.0.0",\n"a/other@v1",\n]\n')
	_write(root.path_join("group/compiled/version.cfg"), '[plugin]\nrequire=[]\n')
	_write(root.path_join("group/compiled/_export_ignore/plugin_export.yml"), 'compile_require: ["a/lib@v2"]\nbuild_require: []\ntest_require: []\n')
	_write(root.path_join("tested/addon.cfg"), '[addon]\nrequire=["a/other@v1"]\n')
	_write(root.path_join("tested/export_ignore/plugin_export.yml"), 'test_require:\n  - "@require"\n  - "a/lib/release@v1:*.zip"\n')
	_write(root.path_join("none/plugin.cfg"), '[plugin]\nrequire=["a/other@v1"]\n')
	_write(root.path_join("broken/plugin.cfg"), '[plugin]\nrequire=["a/lib@v1"]\n')
	_write(root.path_join("broken/export_ignore/plugin_export.json"), '{"build_require": [')
	RequireConsumers.PackageDiscovery.clear_cache()

	var result = RequireConsumers.find("a/lib", ROOT)
	_check("no error", result.error, "")
	_check("id", result.id, "github.com/a/lib")
	_check("consumers sorted, keys merged, non-consumers left out", result.rows.map(func(r): return [r.package, r.spec, r.keys]), [
		["cfg_only", "a/lib@v1.0.0", ["build", "test"]],
		["group/compiled", "a/lib@v2", ["compile"]],
		["tested", "a/lib/release@v1:*.zip", ["test"]]])
	_check("a bad config warns and is skipped", result.warnings.size() == 1 and result.warnings[0].begins_with("broken: "), true)
	var same = func(t): return RequireConsumers.find(t, ROOT).rows.map(func(r): return r.package)
	_check("host, kind, clone: and tag spellings match the same repo", [same.call("github.com/a/lib/release@v9"), same.call("clone:a/lib")],
		[["cfg_only", "group/compiled", "tested"], ["cfg_only", "group/compiled", "tested"]])
	_check("a bad target is an error", RequireConsumers.find("nope", ROOT).error != "", true)
	_check("no consumers says so", RequireConsumers.format(RequireConsumers.find("a/unused", ROOT)), "No package requires a/unused.")
	var text = RequireConsumers.format(result)
	_check("format aligns columns", text.split("\n")[1], "group/compiled  a/lib@v2                compile")
	_check("required_ids", RequireConsumers.required_ids(ROOT), ["a/lib", "a/other"])
	_remove(root)
	RequireConsumers.PackageDiscovery.clear_cache()


static func _write(path:String, content:String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(content)


static func _remove(dir:String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for d in DirAccess.get_directories_at(dir):
		_remove(dir.path_join(d))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


static func _check(label:String, got, expected) -> void:
	if got == expected:
		_passed += 1
		return
	_failures.append("%s (expected %s, got %s)" % [label, expected, got])

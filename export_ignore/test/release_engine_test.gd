@tool
extends EditorScript
## Release exports refuse an engine older than the sources need, before the import can drop classes.

const ReleaseExport = preload("res://addons/gdpackage/src/class/release/release_export.gd")
const TestCI = preload("res://addons/gdpackage/src/class/release/test_ci.gd")
const Reporter = ReleaseExport.Reporter
const MISSING = "res://addons/__pe_missing_package"

const ENGINE_46 = {"major": 4, "minor": 6, "patch": 3, "string": "4.6.3.stable.mono.official"}
const FINDINGS = [
	{"feature": "Node.old_api", "version": "4.5", "location": "addons/lib/a.gd:3"},
	{"feature": "Foo.new_api", "version": "4.7", "location": "addons/lib/b.gd:9"},
]


static func run_tests() -> Dictionary:
	var failures:Array[String] = []
	_expect(failures, "same minor", ReleaseExport.engine_check("4.6", FINDINGS, ENGINE_46) == "")
	_expect(failures, "older minor", ReleaseExport.engine_check("4.5", FINDINGS, ENGINE_46) == "")
	_expect(failures, "unparseable", ReleaseExport.engine_check("", FINDINGS, ENGINE_46) == "")
	var err = ReleaseExport.engine_check("4.7", FINDINGS, ENGINE_46)
	_expect(failures, "newer minor errors: " + err, err.contains("need Godot 4.7") and err.contains("Foo.new_api at addons/lib/b.gd:9") and err.contains("4.6.3"))
	var major = ReleaseExport.engine_check("5.0", [], ENGINE_46)
	_expect(failures, "newer major errors: " + major, major.contains("need Godot 5.0"))
	_expect(failures, "4.10 above 4.9", ReleaseExport.engine_check("4.10", [], {"major": 4, "minor": 9}) != "")
	var stored = ReleaseExport.engine_check("4.7", FINDINGS, ENGINE_46, "addons/lib")
	_expect(failures, "stored value cited over findings: " + stored, stored.contains("minimum_engine_version in addons/lib") and not stored.contains("Foo.new_api"))
	_test_reporting(failures)
	_test_excluded_sources(failures)
	_test_stored_version(failures)
	_test_expected_errors(failures)

	var output:Array[String] = ["release_engine: %d failed" % failures.size()]
	output.append_array(failures)
	return {"result": failures.size(), "output": output}


## Both fail before any fetch on a missing package, so this runs offline. The caller's reporter gets
## the failure live and the result line after it.
static func _test_reporting(failures:Array[String]) -> void:
	var cases = {
		"release": func(r): return ReleaseExport.export_release(MISSING, false, false, r),
		"test ci": func(r): return TestCI.test_package(MISSING, false, false, "", r),
	}
	for label in cases:
		var reporter = Reporter.new()
		var sent = []
		reporter.sink = func(text:String, level:int): sent.append(level)
		var ok = cases[label].call(reporter)
		_expect(failures, label + " fails", ok == false)
		_expect(failures, label + " error reported", reporter.count(Reporter.Level.ERROR) == 1)
		_expect(failures, label + " sink gets error then result", sent == [Reporter.Level.ERROR, Reporter.Level.NOTE])


## Fixtures with expected_error in their path fail on purpose, on the error line or its "at:" line.
static func _test_expected_errors(failures:Array[String]) -> void:
	var output = "\n".join([
		"  SCRIPT ERROR: Invalid call. Nonexistent function 'a' in base 'Nil'.",
		"     at: _execute (user://x_expected_error/crash.gd:5)",
		"SCRIPT ERROR: user://y_expected_error.gd failed",
		"SCRIPT ERROR: Invalid call. Nonexistent function 'b' in base 'Nil'.",
		"   at: _run (res://addons/lib/real.gd:9)",
	])
	var errors = TestCI.runtime_errors(output)
	_expect(failures, "only the unexpected runtime error counts: %s" % errors, errors.size() == 1 and errors[0].contains("real.gd:9"))


static func _test_excluded_sources(failures:Array[String]) -> void:
	var runner = ReleaseExport.ReleaseRunner
	var root = ProjectSettings.globalize_path("user://pe_engine_test_sources")
	runner.remove_dir(root)
	DirAccess.make_dir_recursive_absolute(root)
	FileAccess.open(root.path_join("main.gd"), FileAccess.WRITE).store_string("extends RefCounted\n")
	FileAccess.open(root.path_join("adjacent_test.gd"), FileAccess.WRITE).store_string("extends RefCounted\nvar server = AccessibilityServer\n")
	FileAccess.open(root.path_join("test_framework.gd"), FileAccess.WRITE).store_string("extends GutTest\nvar server = AccessibilityServer\n")
	var reporter = Reporter.new()
	reporter.sink = func(_text:String, _level:int): pass
	_expect(failures, "release preflight excludes test-only APIs", ReleaseExport.engine_error(root, reporter, true) == "")
	var err = ReleaseExport.engine_error(root, reporter)
	_expect(failures, "test CI retains test-only API requirements", (err != "") == (Engine.get_version_info().minor < 7))
	runner.remove_dir(root)


## A cfg-stored minimum_engine_version above the scan fails the check even with clean sources.
static func _test_stored_version(failures:Array[String]) -> void:
	var runner = ReleaseExport.ReleaseRunner
	var root = ProjectSettings.globalize_path("user://pe_engine_test_stored")
	runner.remove_dir(root)
	var lib = root.path_join("addons/lib")
	DirAccess.make_dir_recursive_absolute(lib)
	FileAccess.open(lib.path_join("a.gd"), FileAccess.WRITE).store_string("extends RefCounted\n")
	FileAccess.open(lib.path_join("package.cfg"), FileAccess.WRITE).store_string('[package]\nversion="1"\nminimum_engine_version="99.0"\n')
	var reporter = Reporter.new()
	reporter.sink = func(_text:String, _level:int): pass
	var err = ReleaseExport.engine_error(root, reporter)
	_expect(failures, "stored cfg value fails the check: " + err, err.contains("need Godot 99.0") and err.contains("minimum_engine_version in addons/lib"))
	FileAccess.open(lib.path_join("package.cfg"), FileAccess.WRITE).store_string('[package]\nversion="1"\nminimum_engine_version="4.0"\n')
	_expect(failures, "a low stored value passes", ReleaseExport.engine_error(root, reporter) == "")
	runner.remove_dir(root)


static func _expect(failures:Array[String], label:String, ok:bool) -> void:
	if not ok:
		failures.append("FAIL " + label)

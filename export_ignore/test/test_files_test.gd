@tool
extends RefCounted
## Static test classification must work without frameworks, and native discovery must keep
## fixtures and framework suites out of the adjacent-suite search.

const TestFiles = preload("res://addons/gdpackage/src/class/export/test_files.gd")
const TestJob = preload("res://addons/gdpackage/src/class/release/test_job.gd")
const Runner = preload("res://addons/gdpackage/src/class/release/release_runner.gd")
const ExportData = preload("res://addons/gdpackage/src/class/export/export_data.gd")
const CommandLoader = preload("uid://c8so1oy2s8c5o") #! resolve GDSh.Load
const ROOT = "user://gdpackage_test_files"


static func run_tests() -> Dictionary:
	Runner.remove_dir(ROOT)
	var failures:Array[String] = []
	var cases = {
		"utility_test.gd": ["extends RefCounted\n", true],
		"test_gut.gd": ["extends GutTest\n", true],
		"unit.gd": ["class_name Unit extends GdUnitTestSuite\n", true],
		"path.gd": ['extends "res://addons/gut/test.gd"\n', true],
		"gdunit_path.gd": ["extends 'res://addons/gdUnit4/src/GdUnitTestSuite.gd'\n", true],
		"custom_base.gd": ["class_name SharedTests extends GutTest\n", true],
		"child.gd": ["extends SharedTests\n", true],
		"relative.gd": ['extends "./custom_base.gd"\n', true],
		"plain.gd": ["extends RefCounted\n", false],
		"nested.gd": ["extends RefCounted\nclass Inner:\n\textends GutTest\n", false],
		"comment.gd": ["# extends GutTest\nextends RefCounted # GdUnitTestSuite\n", false],
		"string.gd": ['const TEXT = """\nextends GutTest\nclass_name FalseBase extends GdUnitTestSuite\n"""\n', false],
		"cycle_a.gd": ['extends "cycle_b.gd"\n', false],
		"cycle_b.gd": ['extends "cycle_a.gd"\n', false],
		"not_test.gd.txt": ["extends GutTest\n", false],
	}
	var paths = []
	for name:String in cases:
		paths.append(_write(name, cases[name][0]))
	var classifier = TestFiles.new()
	classifier.index_classes(paths)
	for name:String in cases:
		_expect(failures, "classification " + name, classifier.is_test(ROOT.path_join(name)) == cases[name][1])
	var id = ResourceUID.create_id()
	ResourceUID.add_id(id, ROOT.path_join("custom_base.gd"))
	var uid_path = _write("uid_base.gd", 'extends "%s"\n' % ResourceUID.id_to_text(id))
	_expect(failures, "UID base", classifier.is_test(uid_path))
	ResourceUID.remove_id(id)
	for options in [{}, {"ignore_tests": true}, {"ignore_tests": false}]:
		var config = _write("config.json", JSON.stringify({"export_root": ROOT, "plugin_folder": "out", "exports": [], "options": options}))
		var data = ExportData.new(config)
		_expect(failures, "config default and opt-out " + str(options), data.ignore_tests == options.get("ignore_tests", true))
	_test_discovery(failures)
	var commands = CommandLoader.load_directory("res://addons/gdpackage/cmd/gdpackage/ci", true)
	_expect(failures, "run_test command remains discoverable", commands.has("run_test"))
	if commands.has("run_test"):
		var script = commands.run_test[CommandLoader.Types.ScopeDataKeys.SCRIPT]
		_expect(failures, "production run_test command is not excluded", not classifier.is_test(script.resource_path))
	Runner.remove_dir(ROOT)
	var output:Array[String] = ["test_files: %d failed" % failures.size()]
	output.append_array(failures)
	return {"result": failures.size(), "output": output}


static func _test_discovery(failures:Array[String]) -> void:
	var native = "extends RefCounted\nstatic func run_tests(): return {\"result\": 0, \"output\": []}\n"
	var adjacent = _write("pkg/src/util_test.gd", native)
	var legacy = _write("pkg/_export_ignore/test/legacy_test.gd", native)
	_write("pkg/export_ignore/test/secondary_test.gd", native)
	_write("pkg/_export_ignore/fixtures/fixture_test.gd", native)
	_write("pkg/_export_ignore/exports/export_test.gd", native)
	_write("pkg/.hidden/hidden_test.gd", native)
	_write("pkg/src/ignored/.gdignore", "")
	_write("pkg/src/ignored/ignored_test.gd", native)
	_write("pkg/src/framework_test.gd", "extends GdUnitTestSuite\n")
	_write("pkg/src/shared.gd", "class_name SharedSuite extends GutTest\n")
	_write("pkg/src/derived_test.gd", "extends SharedSuite\n")
	var found = TestJob.find_suites(ROOT.path_join("pkg"))
	var expected = [adjacent, legacy]
	expected.sort()
	_expect(failures, "adjacent + canonical legacy, sorted and deduplicated: " + str(found), found == expected)
	var only = _write("adjacent_only/src/only_test.gd", native)
	_expect(failures, "no dev test directory required", TestJob.find_suites(ROOT.path_join("adjacent_only")) == [only])


static func _write(relative:String, text:String) -> String:
	var path = ROOT.path_join(relative)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	FileAccess.open(path, FileAccess.WRITE).store_string(text)
	return path


static func _expect(failures:Array[String], label:String, passed:bool) -> void:
	if not passed:
		failures.append("FAIL " + label)

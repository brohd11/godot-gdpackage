@tool
extends EditorScript

## The edit-pass guard: a script error inside a parser fails the export instead of shipping the
## file unedited. The guard case raises one SCRIPT ERROR on purpose, from an expected_error path.
##
##     load("res://addons/gdpackage/export_ignore/test/parse_guard_test.gd").run_tests()

const UtilsLocal = preload("res://addons/gdpackage/src/class/utils_local.gd")
const UtilsRemote = preload("res://addons/gdpackage/src/class/utils_remote.gd")
const FileParser = UtilsLocal.FileParser
const Reporter = UtilsLocal.Reporter

const DIR = "user://pe_parse_guard/"

static var _failures:Array[String] = []
static var _passed:int = 0


static func run_tests() -> Dictionary:
	_failures = []
	_passed = 0

	_test_classifier()
	if UtilsRemote.ErrorCapture.supported():
		_test_guard()

	var output:Array = ["parse_guard: %d passed, %d failed" % [_passed, _failures.size()]]
	output.append_array(_failures)
	return {"result": _failures.size(), "output": output}


func _run() -> void:
	print("\n".join(run_tests().output))


static func _test_classifier() -> void:
	var kept = FileParser.script_errors(PackedStringArray([
		"res://a.gd:5: Invalid operands 'PackedStringArray' and 'Array' in operator '+'.",
		"user://x.gd:1: Parse Error",
		"core/io/file_access.cpp:120: Can't open file",
		"scene/main/node.cpp:9: mentions res://a.gd: in text",
	]))
	_check("classifier keeps script errors only", kept, [
		"res://a.gd:5: Invalid operands 'PackedStringArray' and 'Array' in operator '+'.",
		"user://x.gd:1: Parse Error",
	])


static func _test_guard() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var target = DIR.path_join("sample.gd")

	# `[] + PackedStringArray()` is the runtime error that once shipped 102 files unedited.
	var crashing = _run_parser(target, "crash", "var a = []\n\treturn a + PackedStringArray()")
	_check("guard: script error invalidates the export", crashing.export_valid, false)
	var errors = crashing.reporter.entries.filter(func(e): return e.level == Reporter.Level.ERROR)
	_check("guard: one error reported", errors.size(), 1)
	_check("guard: error names the file", errors.size() == 1 and target in errors[0].text, true)

	var clean = _run_parser(target, "clean", "return [\"extends RefCounted\"]")
	_check("guard: clean parser leaves the export valid", clean.export_valid, true)
	_check("guard: clean parser reports nothing", clean.reporter.entries.size(), 0)

	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR.path_join(f))
	DirAccess.remove_absolute(DIR)


## Runs the edit pass on `target` with one gd parser whose post_export_edit_file body is `body`.
static func _run_parser(target:String, label:String, body:String) -> StubExport:
	var file = FileAccess.open(target, FileAccess.WRITE)
	file.store_string("extends RefCounted\n")
	file.close()

	var parser_script = GDScript.new()
	parser_script.source_code = "extends RefCounted\nvar export_obj\n" \
		+ "func post_export_edit_file(_path, _lines = null):\n\t%s\n" % body \
		+ "func post_export_edit_line(line):\n\treturn line\n"
	# test_ci skips SCRIPT ERRORs from paths naming expected_error
	parser_script.set_path_cache(DIR.path_join("%s_expected_error_parser.gd" % label))
	parser_script.reload()

	var export_obj = StubExport.new()
	var parser = parser_script.new()
	parser.export_obj = export_obj

	var file_parser = FileParser.new()
	file_parser.export_obj = export_obj
	file_parser.default_parsers = {"gd": parser}
	file_parser.custom_text_types = []
	file_parser.custom_parse_data = {}
	file_parser.current_file_path_parsing = target
	file_parser.post_export_edit_file(target)
	return export_obj


class StubExport extends RefCounted:
	var export_valid := true
	var reporter := Reporter.new()

	func _init() -> void:
		reporter.sink = func(_text:String, _level:int): pass # keeps the expected error out of Output

	func invalidate() -> void:
		export_valid = false


static func _check(label:String, actual, expected) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failures.append("  FAIL  %s (expected %s, got %s)" % [label, expected, actual])

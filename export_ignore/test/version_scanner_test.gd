@tool
extends EditorScript
## VersionScanner string safety: string literals (triple-quoted ones across lines too) and comments
## are never dated, while code around them still is, on the right line. Temp files, no-load mode.
##
##     load("res://addons/gdpackage/export_ignore/test/version_scanner_test.gd").run_tests()

const VersionScanner = preload("res://addons/gdpackage/src/editor_plugins/console_command/min_version/version_scanner.gd")
const ROOT = "user://gdpackage_version_scanner_tests"

static var _failures:Array[String] = []
static var _passed:int = 0


static func run_tests() -> Dictionary:
	_failures = []
	_passed = 0
	DirAccess.make_dir_recursive_absolute(ROOT)
	var scanner = VersionScanner.new()
	scanner.load_scripts = false
	_test_multiline_strings(scanner)
	_test_code_around_strings(scanner)
	_test_single_line_and_comments(scanner)
	_test_raw_string(scanner)
	_test_unterminated(scanner)
	_test_base_resolution(scanner)
	var output:Array[String] = ["version_scanner: %d passed, %d failed" % [_passed, _failures.size()]]
	for failure in _failures:
		output.append("  FAIL  " + failure)
	return {"result": _failures.size(), "output": output}


func _run() -> void: # EditorScript entry, for running this from the editor
	print("\n".join(run_tests().output))


static func _test_multiline_strings(scanner) -> void:
	var r = _scan(scanner, "multi.gd",
		'extends RefCounted\nconst A = """\nextends EditorDock\nvar d: Dictionary[int, int]\n"""\n'
		+ "const B = '''\nEditorDock\n'''\n")
	_check("triple quotes: nothing dated", r.findings, [])
	_check("triple quotes: baseline", r.min_version, scanner.api.baseline)


static func _test_code_around_strings(scanner) -> void:
	var r = _scan(scanner, "around.gd",
		'extends RefCounted\nconst C = """\nEditorDock\n"""; var d: Dictionary[int, int] = {}\nvar e = EditorDock\n')
	_check("code after closing quotes is scanned", _lines_of(r, "typed Dictionary"), [4])
	_check("code on later lines keeps its line number", _lines_of(r, "class EditorDock"), [5])


static func _test_single_line_and_comments(scanner) -> void:
	var r = _scan(scanner, "single.gd",
		"extends RefCounted\nvar s = \"EditorDock\"\nvar t = 1 # EditorDock\n# var d: Dictionary[int, int]\n")
	_check("single-line string and comments: nothing dated", r.findings, [])


static func _test_raw_string(scanner) -> void:
	var r = _scan(scanner, "raw.gd", 'extends RefCounted\nvar r = r"abc"\n')
	_check("raw string still flagged", _lines_of(r, "raw string literal"), [2])


static func _test_unterminated(scanner) -> void:
	var r = _scan(scanner, "unterminated.gd", 'extends RefCounted\nvar s = "abc\nvar e = EditorDock\n')
	_check("unterminated string falls back per line", _lines_of(r, "class EditorDock"), [3])


static func _test_base_resolution(scanner) -> void:
	var stringed = 'const S = """\nextends Node\n"""\n'
	_check("extends inside a string sets no base",
		scanner._resolve_base_type("", "\n".join(scanner._sanitize_gd(stringed))), "")
	_check("real extends still resolves",
		scanner._resolve_base_type("", "\n".join(scanner._sanitize_gd("extends Node # c\n" + stringed))), "Node")


static func _scan(scanner, file_name:String, source:String) -> Dictionary:
	var path = ROOT.path_join(file_name)
	FileAccess.open(path, FileAccess.WRITE).store_string(source)
	var result = scanner.scan_file(path)
	DirAccess.remove_absolute(path)
	return result


static func _lines_of(result:Dictionary, feature:String) -> Array:
	var lines = []
	for f in result.findings:
		if f.feature == feature:
			lines.append(f.line)
	return lines


static func _check(label:String, got, expected) -> void:
	if got == expected:
		_passed += 1
	else:
		_failures.append("%s (expected %s, got %s)" % [label, expected, got])

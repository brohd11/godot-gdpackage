@tool
extends EditorScript

## The PLUGIN_EXPORTED flip: only real declarations change. The released toolchain is a self-export,
## so a flip that matched string literals rewrote its own needle and stopped flipping anything.
##
##     load("res://addons/gdpackage/export_ignore/test/exported_flag_test.gd").run_tests()

const ParseGd = preload("res://addons/gdpackage/src/class/export/parse/parse_gd.gd")

# Files holding the declaration text as a literal; a self-export must leave them as they are.
const SELF_EXPORT_FILES = [
	"res://addons/gdpackage/src/class/export/parse/parse_gd.gd",
	"res://addons/gdpackage/src/editor_plugins/plugin_exporter_context_menus.gd",
]

static var _failures:Array[String] = []
static var _passed:int = 0


static func run_tests() -> Dictionary:
	_failures = []
	_passed = 0

	var parser = ParseGd.new()
	_test_flips(parser)
	_test_self_export(parser)

	var output:Array = ["exported_flag: %d passed, %d failed" % [_passed, _failures.size()]]
	output.append_array(_failures)
	return {"result": _failures.size(), "output": output}


func _run() -> void:
	print("\n".join(run_tests().output))


static func _test_flips(parser) -> void:
	var cases = {
		"const PLUGIN_EXPORTED = false": "const PLUGIN_EXPORTED = true",
		"\tconst PLUGIN_EXPORTED = false # note": "\tconst PLUGIN_EXPORTED = true # note",
		"const PLUGIN_EXPORTED: bool = false": "const PLUGIN_EXPORTED: bool = true",
		"const PLUGIN_EXPORTED := false": "const PLUGIN_EXPORTED := true",
		"const PLUGIN_EXPORTED = true": "const PLUGIN_EXPORTED = true",
		"const PLUGIN_EXPORTED = falsey": "const PLUGIN_EXPORTED = falsey",
		"const PLUGIN_EXPORTED_STRING = false": "const PLUGIN_EXPORTED_STRING = false",
		'var s = "const PLUGIN_EXPORTED = false"': 'var s = "const PLUGIN_EXPORTED = false"',
	}
	for line in cases:
		_check("flip: %s" % line.strip_edges(), parser.post_export_edit_line(line), cases[line])


static func _test_self_export(parser) -> void:
	for path in SELF_EXPORT_FILES:
		var changed = []
		for line in FileAccess.get_file_as_string(path).split("\n"):
			if parser.post_export_edit_line(line) != line:
				changed.append(line.strip_edges())
		_check("self-export unchanged: %s" % path.get_file(), changed, [])


static func _check(label:String, actual, expected) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failures.append("  FAIL  %s (expected %s, got %s)" % [label, expected, actual])

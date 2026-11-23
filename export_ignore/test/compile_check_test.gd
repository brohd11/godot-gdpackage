@tool
extends EditorScript
## The release compile check skips .gdignore'd dirs, which Godot never loads in an install, e.g. a
## plugin's gdsh cmd/ whose extends names a gdsh the release doesn't carry. The same script
## outside an ignored dir must still fail, so the skip can't hide real errors.

const CompileCheck = preload("res://addons/gdpackage/src/class/release/compile_check.gd")
const Runner = preload("res://addons/gdpackage/src/class/release/release_runner.gd")
const ROOT = "user://pe_compile_check_test"
const INSTALL = "res://addons/cc_fixture"

const OK_SCRIPT = "extends RefCounted\nfunc hello(): return 1\n"
const MISSING_BASE = 'extends "res://addons/_lib/not_shipped/command_base.gd" #! gdp-ignore\n'


static func run_tests() -> Dictionary:
	var root = ProjectSettings.globalize_path(ROOT)
	var failures:Array[String] = []

	var ignored = _fixture(root.path_join("ignored"), true)
	var errors = CompileCheck.compile_errors(ignored, INSTALL, root.path_join("work_ignored"))
	if not errors.is_empty():
		failures.append("a .gdignore'd cmd/ was loaded: %s" % [errors])

	var plain = _fixture(root.path_join("plain"), false)
	errors = CompileCheck.compile_errors(plain, INSTALL, root.path_join("work_plain"))
	if not errors.any(func(e): return "cmd/bad/bad.gd" in e):
		failures.append("an unignored broken script wasn't reported: %s" % [errors])

	Runner.remove_dir(root)
	var output:Array[String] = []
	if failures.is_empty():
		output.append("PASS  compile_check_test")
	else:
		output.append("FAIL  compile_check_test")
		for f in failures:
			output.append("  " + f)
	return {"result": failures.size(), "output": output}


## A plugin dir with one good script and a cmd/ script whose base is missing.
static func _fixture(dir:String, ignore_cmd:bool) -> String:
	_write(dir.path_join("plugin.cfg"), '[plugin]\nname="cc"\nscript="ok.gd"\n')
	_write(dir.path_join("ok.gd"), OK_SCRIPT)
	_write(dir.path_join("cmd/bad/bad.gd"), MISSING_BASE)
	if ignore_cmd:
		_write(dir.path_join("cmd/.gdignore"), "")
	return dir


static func _write(path:String, text:String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _run() -> void:
	var res = run_tests()
	print("\n".join(res.output))

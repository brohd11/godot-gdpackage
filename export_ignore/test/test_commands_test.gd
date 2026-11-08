@tool
extends RefCounted
## CLI runners must preserve arguments and failures, drain logs, and terminate stalled children.

const Commands = preload("res://addons/gdpackage/src/class/release/test_commands.gd")
const Runner = Commands.Runner
const ROOT = "user://gdpackage_test_commands"


static func run_tests() -> Dictionary:
	var errors:Array[String] = []
	if Commands.parse({}).get("custom", true):
		errors.append("absent configuration must select native suites")
	for value in [null, {}, {"commands": []}, {"commands": [null]}, {"commands": [{"script": "../x"}]},
		{"commands": [{"script": "res://ok.gd", "args": [1]}]}, {"commands": [{"script": "res://ok.gd", "timeout": 0}]},
		{"commands": [{"script": "res://ok.gd", "name": ""}]}]:
		if Commands.parse({"test": value}).get("error", "") == "":
			errors.append("invalid test configuration accepted: " + str(value))
	var root = ProjectSettings.globalize_path(ROOT)
	Runner.remove_dir(root)
	DirAccess.make_dir_recursive_absolute(root)
	_write(root.path_join("project.godot"), Runner.project_godot("CLI runner tests", []))
	_write(root.path_join("args.gd"), 'extends SceneTree\nfunc _initialize():\n\tprint("ARGS=" + JSON.stringify(OS.get_cmdline_user_args()))\n\tprinterr("stderr captured")\n\tprint(String.chr(27) + "[31mcoloured output" + String.chr(27) + "[0m")\n\tfor i in 100: print("large output " + "x".repeat(1024))\n\tquit(0)\n')
	_write(root.path_join("fail.gd"), 'extends SceneTree\nfunc _initialize():\n\tprint("expected failure")\n\tquit(100)\n')
	_write(root.path_join("hang.gd"), 'extends SceneTree\nfunc _initialize():\n\tprint("HANG_PID=" + str(OS.get_process_id()))\n')
	var args = ["two words", "a=b", "$(literal)", "quoted\"value", "café"]
	var parsed = Commands.parse({"test": {"commands": [
		{"name": "failure", "script": "res://fail.gd"},
		{"name": "arguments", "script": "res://args.gd", "args": ["--"] + args},
		{"name": "missing", "script": "res://missing.gd"},
		{"name": "timeout", "script": "res://hang.gd", "timeout": 1},
	]}})
	var report = Commands.run(root, parsed.commands)
	if report.suites.size() != 4 or report.failed != 3:
		errors.append("commands did not all run with expected failures: " + str(report))
	else:
		if report.suites[0].exit != 100:
			errors.append("framework exit code lost")
		var output = "\n".join(report.suites[1].output)
		var found_args = false
		for line in report.suites[1].output:
			if line.begins_with("ARGS="):
				found_args = JSON.parse_string(line.trim_prefix("ARGS=")) == args
		if not report.suites[1].passed or not found_args or "stderr captured" not in output or output.count("large output") != 100:
			errors.append("arguments or large stdout/stderr were lost: " + output.left(1000))
		if "coloured output" not in output or String.chr(27) in output:
			errors.append("framework colour codes were not normalized for JSON reporting")
		if not report.suites[3].timed_out:
			errors.append("stalled script did not time out")
		for line in report.suites[3].output:
			if line.begins_with("HANG_PID="):
				var check = []
				if OS.execute("/bin/kill", ["-0", line.trim_prefix("HANG_PID=")], check, true) == 0:
					errors.append("timed out child is still running")
	var failed_launch = Commands.process([], 1, root.path_join("no-executable"))
	if failed_launch.exit == 0:
		errors.append("launch failure reported as success")
	Runner.write_plugin(root, "broken", '@tool\nextends EditorPlugin\nfunc broken(:\n')
	_write(root.path_join("project.godot"), Runner.project_godot("Broken import", ["res://addons/broken/plugin.cfg"]))
	var broken = Commands.run(root, parsed.commands)
	if broken.failed != 1 or broken.suites[0].path != "import":
		errors.append("import errors did not stop command execution")
	Runner.remove_dir(root)
	var output:Array[String] = ["test_commands: %d failed" % errors.size()]
	output.append_array(errors)
	return {"result": errors.size(), "output": output}


static func _write(path:String, content:String) -> void:
	FileAccess.open(path, FileAccess.WRITE).store_string(content)

@tool
extends RefCounted
## Runs package-supplied Godot CLI scripts after dependencies have been imported. Frameworks own
## discovery and assertion results; only exit zero means success here.

const Runner = preload("res://addons/gdpackage/src/class/release/release_runner.gd")


## An absent test block selects native suites; an explicit empty command list is an error.
static func parse(config:Dictionary) -> Dictionary:
	if not config.has("test"):
		return {"commands": [], "custom": false, "error": ""}
	var test = config.test
	if not test is Dictionary or not test.get("commands") is Array or test.commands.is_empty():
		return {"error": "test.commands must be a nonempty array"}
	var commands = []
	for i in test.commands.size():
		var command = test.commands[i]
		var label = "test.commands[%d]" % i
		if not command is Dictionary:
			return {"error": label + " must be a mapping"}
		var script = command.get("script", "")
		if not script is String or not script.begins_with("res://") or script.trim_prefix("res://") == "" or ".." in script.split("/"):
			return {"error": label + ".script must be a res:// path inside the workspace"}
		var args = command.get("args", [])
		if not args is Array or not args.all(func(arg): return arg is String):
			return {"error": label + ".args must be an array of strings"}
		var timeout = command.get("timeout", Runner.TEST_TIMEOUT_SEC)
		if not (timeout is int or timeout is float) or not is_finite(float(timeout)) or timeout <= 0:
			return {"error": label + ".timeout must be a positive number of seconds"}
		var name = command.get("name", script)
		if not name is String or name.strip_edges() == "":
			return {"error": label + ".name must be a nonempty string"}
		commands.append({"name": name, "script": script, "args": args, "timeout": timeout})
	return {"commands": commands, "custom": true, "error": ""}


static func run(project_dir:String, commands:Array) -> Dictionary:
	var report = {"suites": [], "failed": 0, "invalid": []}
	var imported = process(["--headless", "--path", project_dir, "--import"], Runner.TEST_TIMEOUT_SEC)
	if imported.exit != 0 or "SCRIPT ERROR:" in imported.output or not Runner.script_errors(imported.output).is_empty():
		_add(report, "import", imported, false)
		return report
	for command in commands:
		var script = project_dir.path_join(String(command.script).trim_prefix("res://"))
		if not FileAccess.file_exists(script):
			_add(report, command.name, {"exit": -1, "output": "Missing test script: " + command.script}, false)
			continue
		var args = ["--headless", "--path", project_dir, "--script", command.script]
		args.append_array(command.args)
		var result = process(args, command.timeout)
		_add(report, command.name, result, result.exit == 0)
	return report


## Drain both nonblocking pipes while polling, so large logs cannot block the child or its deadline.
static func process(args:Array, timeout:float, executable:String = "") -> Dictionary:
	var child = OS.execute_with_pipe(OS.get_executable_path() if executable == "" else executable, args, false)
	if child.is_empty():
		return {"exit": -1, "output": "Could not launch Godot", "timed_out": false}
	var stdout = PackedByteArray()
	var stderr = PackedByteArray()
	var deadline = Time.get_ticks_msec() + int(timeout * 1000)
	var timed_out = false
	while true:
		_drain(child.stdio, stdout)
		_drain(child.stderr, stderr)
		if not OS.is_process_running(child.pid):
			break
		if Time.get_ticks_msec() >= deadline:
			timed_out = true
			OS.kill(child.pid)
			break
		OS.delay_msec(10)
	_drain(child.stdio, stdout)
	_drain(child.stderr, stderr)
	child.stdio.close()
	child.stderr.close()
	var output = stdout.get_string_from_utf8() + stderr.get_string_from_utf8()
	if timed_out:
		output += "\nTest command timed out after %s seconds (pid %d terminated)" % [timeout, child.pid]
	return {"exit": -1 if timed_out else OS.get_process_exit_code(child.pid), "output": output, "timed_out": timed_out, "pid": child.pid}


static func _drain(pipe:FileAccess, bytes:PackedByteArray) -> void:
	# Bound each drain so a continuously writing process cannot starve the deadline check.
	for _i in 16:
		var chunk = pipe.get_buffer(4096)
		bytes.append_array(chunk)
		if chunk.size() < 4096:
			break


static func _add(report:Dictionary, name:String, result:Dictionary, passed:bool) -> void:
	# Framework colour codes contain ESC, which Godot's JSON writer does not escape.
	var ansi = RegEx.new()
	ansi.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
	var output = Array(ansi.sub(result.output, "", true).split("\n"))
	output.append("exit: %d" % result.exit)
	report.suites.append({"path": name, "passed": passed, "output": output, "exit": result.exit, "timed_out": result.get("timed_out", false)})
	if not passed:
		report.failed += 1

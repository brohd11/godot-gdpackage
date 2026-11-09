@tool
extends EditorScript
## A command-only export must bring GDSh's lazy loader along. Run actual commands in an empty
## project: compile-only checks cannot catch missing runtime load() dependencies.

const UtilsLocal = preload("res://addons/gdpackage/src/class/utils_local.gd")
const Runner = preload("res://addons/gdpackage/src/class/release/release_runner.gd")
const Commands = preload("res://addons/gdpackage/src/class/release/test_commands.gd")
const ROOT = "user://gdpackage_gdsh_export_test"
const INSTALL = "addons/gdsh_loader_fixture"
const PROBE_PREFIX = "GDSH_EXPORT_PROBE "

const COMMAND = '''extends "res://addons/_lib/gdsh/src/core/command_base.gd"
static func get_command_name(): return "%s"
static func get_self_command_data(): return _command_data({&"help": "Exported command fixture"})
'''

const PROBE = '''extends SceneTree
var _started = false
var _done = false
var _failures = []

func _initialize():
	_run.call_deferred()

func _process(_delta):
	if _started and not _done:
		printerr("GDSh export probe stopped on a script error")
		quit(1)
	return false

func _run():
	_started = true
	var entry = load("res://addons/gdsh_loader_fixture/commands/root/root.gd")
	var base = entry.get_base_script()
	var children = entry.new().get_commands()
	_check(children.has("child"), "child command discovered")
	if children.has("child"):
		var child = children.child.get_command.call()
		_check(child.get_command_name() == "child", "option callback instantiates child")
	var ctx = base.Context.new()
	_check(ctx.scopes_hidden.has("echo"), "context loads builtins")
	var loaded = ctx.load("res://addons/gdsh_loader_fixture/commands/root/root.gd")
	_check(loaded.has("root"), "context loads an exported command")
	var result = await base.Execution.execute_command_multiline("root child", ctx)
	_check(result.exit_code == 0 and result.stdout.strip_edges() == "relocated child", "exported child executes")
	var choices = base.Completion.new("root ch", ctx).get_completions()
	_check(choices.has("child"), "exported child completion")
	_done = true
	print("GDSH_EXPORT_PROBE " + JSON.stringify({"failures": _failures}))
	quit(0 if _failures.is_empty() else 1)

func _check(ok, label):
	if not ok:
		_failures.append(label)
'''


static func run_tests() -> Dictionary:
	if not Engine.is_editor_hint():
		return {"result": 0, "output": ["gdsh_export: skipped (editor only)"]}
	var failures:Array[String] = []
	var root = ProjectSettings.globalize_path(ROOT)
	Runner.remove_dir(root)
	var source = ROOT.path_join("source")
	_write(source.path_join("plugin.cfg"), '[plugin]\nname="GDSh Loader Fixture"\nversion="0.1.0"\nscript="plugin.gd"\n')
	_write(source.path_join("plugin.gd"), "@tool\nextends EditorPlugin\n")
	# Only CommandBase is referenced: a Host or Load preload would mask the original bug.
	_write(source.path_join("commands/root/root.gd"), COMMAND % "root")
	_write(source.path_join("commands/root/child/child.gd"), (COMMAND % "child") + 'func _execute(ctx): ctx.append_output("relocated child")\n')
	var exports = []
	for relative in [false, true]:
		exports.append({
			"source": source, "export_name": "relative" if relative else "absolute", "export_folder": INSTALL,
			"remote_dir": source.path_join("remote"), "other_transfers": [],
			"exclude": {"directories": [], "file_extensions": [], "files": []},
			"parser_overide_settings": {"parse_gd": {"use_relative_paths": relative}},
		})
	var config_path = source.path_join("_export_ignore/config.json")
	_write(config_path, JSON.stringify({
		"export_root": ROOT.path_join("exports"), "plugin_folder": "fixture", "exports": exports,
		"options": {"overwrite": true, "include_uid": true, "include_import": false, "include_docs": false,
			"parser_settings": {"parse_gd": {"class_rename_ignore": []}}},
	}))
	if not UtilsLocal.PluginExporterStatic.export_plugin(config_path):
		failures.append("fixture export failed")
	else:
		for variant in ["absolute", "relative"]:
			_test_export(root, variant, failures)
	Runner.remove_dir(root)
	var output:Array[String] = ["gdsh_export: %d failed" % failures.size()]
	output.append_array(failures)
	return {"result": failures.size(), "output": output}


static func _test_export(root:String, variant:String, failures:Array[String]) -> void:
	var package = root.path_join("exports/fixture").path_join(variant).path_join(INSTALL)
	var project = root.path_join("probe_" + variant)
	if not Runner.copy_dir(package, project.path_join(INSTALL)):
		failures.append(variant + ": could not install exported fixture")
		return
	_write(project.path_join("project.godot"), Runner.project_godot("GDSh export " + variant, []))
	_write(project.path_join("probe.gd"), PROBE)
	if DirAccess.dir_exists_absolute(project.path_join("addons/_lib/gdsh")):
		failures.append(variant + ": original GDSh path would hide relocation failures")
		return
	var imported = Commands.process(["--headless", "--path", project, "--import"], 60)
	if imported.exit != 0 or "SCRIPT ERROR:" in imported.output or not Runner.script_errors(imported.output).is_empty():
		failures.append(variant + ": import failed: " + imported.output.right(4000))
		return
	var run = Commands.process(["--headless", "--path", project, "--script", "res://probe.gd"], 30)
	var report = {}
	for line in run.output.split("\n"):
		if line.begins_with(PROBE_PREFIX):
			var parsed = JSON.parse_string(line.trim_prefix(PROBE_PREFIX))
			if parsed is Dictionary:
				report = parsed
	if run.exit != 0 or not report.has("failures") or not report.get("failures", []).is_empty() or "SCRIPT ERROR:" in run.output:
		failures.append(variant + ": runtime probe failed: " + run.output.right(6000))


static func _write(path:String, text:String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	FileAccess.open(path, FileAccess.WRITE).store_string(text)

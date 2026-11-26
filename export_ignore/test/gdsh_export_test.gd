@tool
extends EditorScript
## Relocated GDSh exports, run in an empty project: compile-only checks miss runtime load()s.
## A command-only export must discover its subcommands without shipping the shell (execute.gd,
## builtins); one that references GDSh.Host must carry a working shell.

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
# Not `Host`: CommandBase declares that (the $GDSH_HOST names), and a redeclaration won't parse.
const HOST_LINE = 'const ShellHost = preload("res://addons/_lib/gdsh/src/core/host.gd")\n'

const PROBE = '''extends SceneTree
const WITH_HOST = %s
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
	if WITH_HOST:
		var host = entry.ShellHost
		var ctx = host.Context.new()
		_check(ctx.scopes_hidden.has("echo"), "context loads builtins")
		var loaded = ctx.load("res://addons/gdsh_loader_fixture/commands/root/root.gd")
		_check(loaded.has("root"), "context loads an exported command")
		var result = await host.Execute.execute_command_multiline("root child", ctx)
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
	for fixture in ["commands", "host"]:
		var with_host = fixture == "host"
		if not _export_fixture(fixture, with_host):
			failures.append(fixture + ": fixture export failed")
			continue
		for variant in ["absolute", "relative"]:
			var package = root.path_join("exports").path_join(fixture).path_join(variant).path_join(INSTALL)
			_test_shipped(package, fixture + "/" + variant, with_host, failures)
			_test_export(root, package, fixture + "_" + variant, with_host, failures)
	Runner.remove_dir(root)
	var output:Array[String] = ["gdsh_export: %d failed" % failures.size()]
	output.append_array(failures)
	return {"result": failures.size(), "output": output}


static func _export_fixture(fixture:String, with_host:bool) -> bool:
	var source = ROOT.path_join("source_" + fixture)
	_write(source.path_join("plugin.cfg"), '[plugin]\nname="GDSh Loader Fixture"\nversion="0.1.0"\nscript="plugin.gd"\n')
	_write(source.path_join("plugin.gd"), "@tool\nextends EditorPlugin\n")
	# The command-only root references nothing but CommandBase: a ShellHost or Load preload would mask
	# a missing loader, and is exactly what the host fixture adds.
	_write(source.path_join("commands/root/root.gd"), (COMMAND % "root") + (HOST_LINE if with_host else ""))
	_write(source.path_join("commands/root/child/child.gd"), (COMMAND % "child") + 'func _execute(ctx): ctx.append_output("relocated child"); return ExitCode.OK\n')
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
		"export_root": ROOT.path_join("exports"), "plugin_folder": fixture, "exports": exports,
		"options": {"overwrite": true, "include_uid": true, "include_import": false, "include_docs": false,
			"parser_settings": {"parse_gd": {"class_rename_ignore": []}}},
	}))
	return UtilsLocal.PluginExporterStatic.export_plugin(config_path)


## What GDSh brought with it: the shell only when Host asked for it, and never the namespace hub.
static func _test_shipped(package:String, label:String, with_host:bool, failures:Array[String]) -> void:
	var files = _walk(package)
	var has = func(suffix:String) -> bool: return files.any(func(f:String): return f.ends_with(suffix))
	var builtins = files.any(func(f:String): return f.contains("/gdsh/src/core/builtins/"))
	if not has.call("/gdsh/src/core/load.gd"):
		failures.append(label + ": loader missing")
	if has.call("/gdsh/_ns/gd_sh.gd"):
		failures.append(label + ": namespace hub shipped")
	if has.call("/gdsh/src/core/execute.gd") != with_host:
		failures.append(label + ": execute.gd shipped = %s" % (not with_host))
	if builtins != with_host:
		failures.append(label + ": builtins shipped = %s" % builtins)


static func _test_export(root:String, package:String, name:String, with_host:bool, failures:Array[String]) -> void:
	var project = root.path_join("probe_" + name)
	if not Runner.copy_dir(package, project.path_join(INSTALL)):
		failures.append(name + ": could not install exported fixture")
		return
	_write(project.path_join("project.godot"), Runner.project_godot("GDSh export " + name, []))
	_write(project.path_join("probe.gd"), PROBE % ("true" if with_host else "false"))
	if DirAccess.dir_exists_absolute(project.path_join("addons/_lib/gdsh")):
		failures.append(name + ": original GDSh path would hide relocation failures")
		return
	var imported = Commands.process(["--headless", "--path", project, "--import"], 60)
	if imported.exit != 0 or "SCRIPT ERROR:" in imported.output or not Runner.script_errors(imported.output).is_empty():
		failures.append(name + ": import failed: " + imported.output.right(4000))
		return
	var run = Commands.process(["--headless", "--path", project, "--script", "res://probe.gd"], 30)
	var report = {}
	for line in run.output.split("\n"):
		if line.begins_with(PROBE_PREFIX):
			var parsed = JSON.parse_string(line.trim_prefix(PROBE_PREFIX))
			if parsed is Dictionary:
				report = parsed
	if run.exit != 0 or not report.has("failures") or not report.get("failures", []).is_empty() or "SCRIPT ERROR:" in run.output:
		failures.append(name + ": runtime probe failed: " + run.output.right(6000))


static func _walk(dir:String) -> Array[String]:
	var out:Array[String] = []
	for f in DirAccess.get_files_at(dir):
		out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_walk(dir.path_join(d)))
	return out


static func _write(path:String, text:String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	FileAccess.open(path, FileAccess.WRITE).store_string(text)

extends "res://addons/_lib/gdsh/src/core/command_base.gd" #! gdp-ignore

const PluginExporter = preload("res://addons/gdpackage/src/class/plugin_exporter.gd")
const PECommandUtils = preload("res://addons/gdpackage/src/class/command_utils.gd")
const PluginInit = PluginExporter.PluginInit

const _HELP = \
"create a new plugin from template and initialize
Usage: gdpackage new_plugin <plugin_name>"

static func get_command_name() -> String:
	return "new_plugin"

static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP,
		&"positional_count": 1
	})

func _get_completions(ctx:Completion):
	return {}

func _execute(ctx:Context):
	var notes:Array[String] = []
	var plugin_dir = PluginInit.write_new_plugin(positional_args[0], notes)
	if plugin_dir == "":
		PECommandUtils.report_notes(ctx, notes, true)
		return ExitCode.FAIL
	ctx.append_output("Created plugin: " + plugin_dir)
	var config = PluginInit.write_plugin_init(plugin_dir, notes)
	PECommandUtils.report_notes(ctx, notes, config == "")
	if config == "":
		return ExitCode.FAIL
	ctx.append_output("Plugin init complete: " + config)
	return ExitCode.OK

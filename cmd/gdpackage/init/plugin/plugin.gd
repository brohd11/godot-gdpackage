extends "res://addons/_lib/gdsh/src/core/command_base.gd" #! gdp-ignore

const PluginExporter = preload("res://addons/gdpackage/src/class/plugin_exporter.gd")
const PECommandUtils = preload("res://addons/gdpackage/src/class/command_utils.gd")
const PluginInit = PluginExporter.PluginInit

const _HELP = \
"Initialize plugin folder with required files
Usage: gdpackage init plugin [--force] <plugin_name>"

var force_flag := false

static func get_command_name() -> String:
	return "plugin"

static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP + PECommandUtils.TARGET_HELP,
		&"positional_count": 1
	})

func _get_flags() -> Dictionary:
	var options = Options.new()
	options.add_option("--force", {
		&"help": "Overwrite an existing export config.",
	})
	return options.get_options()

func _process_flag(flag:String):
	if flag == "--force":
		force_flag = true

func _get_completions(ctx:Completion):
	if _completion_last_is_flag(ctx):
		return _get_completion_std_w_context(ctx, false)
	return PECommandUtils.plugin_name_completion(self, ctx, PECommandUtils.TargetAddons.NOT_VALID)

func _execute(ctx:Context):
	var notes:Array[String] = []
	var config = PluginInit.write_plugin_init(positional_args[0], notes, force_flag)
	PECommandUtils.report_notes(ctx, notes, config == "")
	if config == "":
		return ExitCode.FAIL
	ctx.append_output("Plugin init complete: " + config)
	return ExitCode.OK

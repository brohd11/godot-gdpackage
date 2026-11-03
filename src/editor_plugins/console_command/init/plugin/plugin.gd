extends GDSh.CommandBase

const PluginExporter = preload("res://addons/gdpackage/src/class/plugin_exporter.gd")
const PECommandUtils = preload("res://addons/gdpackage/src/editor_plugins/console_command/command_utils.gd")

const _HELP = \
"Initialize plugin folder with required files
Usage: gdpackage init plugin <plugin_name>"

static func get_command_name() -> String:
	return "plugin"

static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP + PECommandUtils.TARGET_HELP,
		&"positional_count": 1
	})

func _get_completions(ctx:Completion):
	return PECommandUtils.plugin_name_completion(self, ctx, PECommandUtils.TargetAddons.NOT_VALID)

func _execute(ctx:Context):
	var plugin_name = positional_args[0]
	PluginExporter.plugin_init(plugin_name)
	return ExitCode.OK

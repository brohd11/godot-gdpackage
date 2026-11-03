extends GDSh.CommandBase

const PluginExporter = preload("res://addons/gdpackage/src/class/plugin_exporter.gd")

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
	var plugin_name = positional_args[0]
	PluginExporter.new_plugin(plugin_name)
	return ExitCode.OK

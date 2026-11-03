extends GDSh.CommandBase

const PluginExporter = preload("res://addons/gdpackage/src/class/plugin_exporter.gd")

const _HELP = \
"Execute GDPackage commands"

static func get_command_name() -> String:
	return "gdpackage"

static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP,
	})

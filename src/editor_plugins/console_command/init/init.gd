extends GDSh.CommandBase

const _HELP = \
"Initialize a package or add files to it.
  package  make a folder a library package: a package cfg, git init, src/, then init plugin
  plugin   initialize a plugin folder with the required files
  license  generate a LICENSE file
Usage: gdpackage init <package|plugin|license> ..."

static func get_command_name() -> String:
	return "init"

static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP,
	})

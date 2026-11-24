extends "res://addons/_lib/gdsh/src/core/command_base.gd" #! gdp-ignore

const _HELP = \
"Open a package in GDPackage or its export folder.
  gui         open a GDPackage gui instance with the package
  export_dir  open the package's export folder
Usage: gdpackage open <gui|export_dir> <plugin_name>"

static func get_command_name() -> String:
	return "open"

static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP,
	})

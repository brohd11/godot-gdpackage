extends "res://addons/_lib/gdsh/src/core/command_base.gd" #! gdp-ignore
## Found by gdsh hosts in the plugin's cmd/ (GDSh.Load.plugin_dirs); subcommands are the sibling
## name/name.gd dirs. The extends line's gdp-ignore keeps its path literal for the rebase: a
## release's cmd/ is .gdignore'd and built against the host's gdsh. Helpers belong in src/.

const _HELP = \
"Execute GDPackage commands"

static func get_command_name() -> String:
	return "gdpackage"

static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP,
	})

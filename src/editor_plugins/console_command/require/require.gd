extends GDSh.CommandBase

const _HELP = \
"Work with a package's requires, the cfg's require= list (build_require and test_require default to it).
  check      list the package's own requires; --tags checks they can be fetched, --all walks every dependency
  update     write the requires the export crawl finds into the cfg (or --export-config)
  consumers  list every package that declares a given repo among its requires
Usage: gdpackage require <check|update|consumers> ..."

static func get_command_name() -> String:
	return "require"

static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP,
	})

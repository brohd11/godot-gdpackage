extends GDSh.CommandBase

const _HELP = \
"Continuous integration for a package: opt it into CI workflows, or run its tests as CI does.
  release_workflow  write .github/workflows/release.yml, building a release on version tags
  test_workflow     write .github/workflows/test.yml, running its suites on every push
  run_test          run its tests against its requires at their tags, as test CI does
Usage: gdpackage ci <release_workflow|test_workflow|run_test> ..."

static func get_command_name() -> String:
	return "ci"

static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP,
	})

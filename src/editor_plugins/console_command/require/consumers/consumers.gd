extends GDSh.CommandBase

const RequireConsumers = preload("res://addons/package_exporter/src/class/release/require_consumers.gd")
const PECommandUtils = preload("res://addons/package_exporter/src/editor_plugins/console_command/command_utils.gd")

const _HELP = \
"List every package under res://addons that declares a repo among its requires: the cfg's require=,
or its export config's build/compile/test_require. One line per package: its path, the spec as it
pins the repo, and the keys it is under. Any spelling of the repo matches (host, /release, a tag).
Usage: package_exporter require consumers <owner/repo>"

static func get_command_name() -> String:
	return "consumers"

static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP,
		&"positional_count": 1
	})

func _get_completions(ctx:Completion):
	if _completion_last_is_flag(ctx):
		return _get_completion_std_w_context(ctx, false)
	var ids = {}
	for id in RequireConsumers.required_ids():
		ids[id] = true
	return PECommandUtils.dir_completion(self, ctx, ids)

func _execute(ctx:Context):
	var result = RequireConsumers.find(positional_args[0])
	if result.error != "":
		ctx.append_error(result.error)
		return ExitCode.FAIL
	for w in result.warnings:
		ctx.append_error("[color=#fedd66]Warning: %s[/color]" % w)
	ctx.append_output(RequireConsumers.format(result))
	return ExitCode.OK

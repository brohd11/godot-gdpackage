extends GDSh.CommandBase

const RequireReport = preload("res://addons/gdpackage/src/class/release/require_report.gd")
const RequireUpdate = preload("res://addons/gdpackage/src/class/release/require_update.gd")
const RequireCheck = preload("res://addons/gdpackage/src/class/release/require_check.gd")
const PECommandUtils = preload("res://addons/gdpackage/src/editor_plugins/console_command/command_utils.gd")

const _HELP = \
"List the packages a plugin's export pulls in, as its own require list: one require@tag per line,
the tag being each package's cfg version=. Runs the export crawl only.
  --tags     check the requires it declares (cfg require, compile_require, test_require) can be
             fetched at their tags, as a release or test CI build would - an unpushed tag fails here
  --all      the full walk: every package referenced, grouped by the package whose require list it
             belongs in, marked declared or MISSING
  --verbose  with the list or --all: every reference behind each package, as file:line, kind,
             the text as written and the file it lands on
Usage: gdpackage require check [--tags] [--all] [--verbose] <plugin_name>"

var tags_flag := false
var all_flag := false
var verbose_flag := false

static func get_command_name() -> String:
	return "check"

static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP + PECommandUtils.TARGET_HELP,
		&"positional_count": 1
	})

func _get_flags() -> Dictionary:
	var options = Options.new()
	options.add_option("--tags", {&"help": "Check the declared requires can be fetched at their tags."})
	options.add_option("--all", {&"help": "Walk every dependency, grouped, with MISSING markers."})
	options.add_option("--verbose", {&"help": "List where each package is referenced (file:line)."})
	return options.get_options()

func _get_completions(ctx:Completion):
	if _completion_last_is_flag(ctx):
		return _get_completion_std_w_context(ctx, false)
	return PECommandUtils.plugin_name_completion(self, ctx, PECommandUtils.TargetAddons.VALID)

func _execute(ctx:Context):
	var sections:Array[String] = []
	if all_flag or not tags_flag:
		var report = RequireReport.build(positional_args[0])
		if not report.errors.is_empty():
			for e in report.errors:
				ctx.append_error(e)
			return ExitCode.FAIL
		sections.append(RequireReport.format(report, verbose_flag) if all_flag else "\n".join(RequireUpdate.self_list(report, verbose_flag)))
	if not tags_flag:
		ctx.append_output("\n\n".join(sections))
		return ExitCode.OK

	var result = RequireCheck.check_tags(_package_dir(positional_args[0]))
	sections.append(RequireCheck.format(result))
	ctx.append_output("\n\n".join(sections))
	for e in result.errors:
		ctx.append_error(e)
	if not result.errors.is_empty() or result.rows.any(func(r): return not r.ok):
		return ExitCode.FAIL
	return ExitCode.OK

static func _package_dir(target:String) -> String:
	return RequireReport.ExportFileUtils.ExportPaths.resolve_target(target)

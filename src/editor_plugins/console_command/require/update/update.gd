extends GDSh.CommandBase

const RequireReport = preload("res://addons/gdpackage/src/class/release/require_report.gd")
const RequireUpdate = preload("res://addons/gdpackage/src/class/release/require_update.gd")
const PECommandUtils = preload("res://addons/gdpackage/src/editor_plugins/console_command/command_utils.gd")
const PackageCfg = preload("uid://ddo8w07hts45v") #! resolve GDPackageSpec.Cfg
const MinVersionStamp = preload("res://addons/gdpackage/src/editor_plugins/console_command/min_version/min_version_stamp.gd")

const _HELP = \
"Write the packages the export crawl found into the target's own require list: its cfg require= by
default, which build_require and test_require read through their @require default. Each tag is the
required package's cfg version=, and a version not tagged in its checkout yet only warns. Packages
under compile_require are left out - they install beside the package, not inside it.
  --export-config  write the export config's build_require instead (an explicit list, @require dropped)
  --min-version    also stamp the cfg's minimum_engine_version: the crawl's scan or any touched
                   package's stored value, whichever is higher. Never lowers - see min_version --update
Usage: gdpackage require update [--overwrite] [--prune] [--export-config] [--min-version] <plugin_name>"

var overwrite_flag := false
var prune_flag := false
var export_config_flag := false
var min_version_flag := false

static func get_command_name() -> String:
	return "update"

static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP + PECommandUtils.TARGET_HELP,
		&"positional_count": 1
	})

func _get_flags() -> Dictionary:
	var options = Options.new()
	options.add_option("--overwrite", {&"help": "Re-pin entries the config already lists to their current tag."})
	options.add_option("--prune", {&"help": "Drop entries the crawl did not find."})
	options.add_option("--export-config", {&"help": "Write the export config's build_require instead of the cfg's require=."})
	options.add_option("--min-version", {&"help": "Also raise the cfg's minimum_engine_version to what the crawl needs."})
	return options.get_options()

func _get_completions(ctx:Completion):
	if _completion_last_is_flag(ctx):
		return _get_completion_std_w_context(ctx, false)
	return PECommandUtils.plugin_name_completion(self, ctx, PECommandUtils.TargetAddons.VALID)

func _execute(ctx:Context):
	var report = RequireReport.build(positional_args[0])
	if not report.errors.is_empty():
		for e in report.errors:
			ctx.append_error(e)
		return ExitCode.FAIL

	var result = RequireUpdate.apply(report, overwrite_flag, prune_flag, export_config_flag)
	var lines:Array[String] = []
	for w in result.warnings:
		lines.append("warning: " + w)
	for dir in report.loose:
		lines.append("warning: %s is in no %s package, so it can't be required" % [dir, "/".join(PackageCfg.NAMES)])
	if not result.errors.is_empty():
		ctx.append_output("\n".join(lines))
		for e in result.errors:
			ctx.append_error(e)
		ctx.append_error("nothing was written")
		return ExitCode.FAIL

	for spec in result.added:
		lines.append("added      " + spec)
	for spec in result.repinned:
		lines.append("re-pinned  " + spec)
	for spec in result.pruned:
		lines.append("pruned     " + spec)
	if not result.kept.is_empty():
		lines.append("kept       %d" % result.kept.size())
	lines.append(("wrote " if result.changed else "already up to date: ") + result.path)
	if min_version_flag:
		var stamped = MinVersionStamp.stamp(report.target, report.files, _touched_dirs(report))
		if not stamped.ok:
			ctx.append_output("\n".join(lines))
			ctx.append_error(stamped.error)
			return ExitCode.FAIL
		lines.append(stamped.line)
	ctx.append_output("\n".join(lines))
	return ExitCode.OK

## Every package the crawl reached or left out as external; the stamp drops the target itself.
static func _touched_dirs(report:Dictionary) -> Array:
	var dirs = {}
	for from in report.groups:
		dirs[from] = true
		for row in report.groups[from].rows:
			dirs[row.dir] = true
	for dir in report.external_dirs:
		dirs[dir] = true
	return dirs.keys()

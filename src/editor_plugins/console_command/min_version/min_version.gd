extends GDSh.CommandBase


const PluginExporter = preload("res://addons/gdpackage/src/class/plugin_exporter.gd")
const PECommandUtils = preload("res://addons/gdpackage/src/editor_plugins/console_command/command_utils.gd")
const ExportData = PluginExporter.PluginExporterStatic.ExportData
const Export = ExportData.Export

const VersionScanner = preload("res://addons/gdpackage/src/editor_plugins/console_command/min_version/version_scanner.gd")
const VersionApi = preload("res://addons/gdpackage/src/editor_plugins/console_command/min_version/version_api.gd")
const MinVersionStamp = preload("res://addons/gdpackage/src/editor_plugins/console_command/min_version/min_version_stamp.gd")

const UString = PluginExporter.UtilsRemote.UString

const _HELP = \
"Report the minimum Godot version a plugin's exports can run on.
Scans every file in each export package for version-gated syntax and API usage. The scan can miss
things, so the minimum_engine_version stored in any touched package's cfg (bundled or external)
counts too, and the result is the higher of the two.
Usage: min_version [--min=4.4] <addon_name> [--verbose] [--full] [--update [--allow-lower]]
  --update       Write the result to the package cfg's minimum_engine_version. Only raises it.
  --allow-lower  With --update, also lower a stored value the scan no longer reaches.
  --verbose  List every occurrence with its file:line location.
  --full     Future GDScript-parser deep scan (variable type inference); not yet
             implemented — currently runs the standard scan.
  --min=VER  Only show findings introduced above VER (e.g. --min=4.4). Does not
             change the scan or the reported minimum, only what is listed.
             Can set $GDPACKAGE_MIN_VERSION for persistence, flag overides variable."

var verbose_flag := false
var full_flag := false
var min_flag := ""
var update_flag := false
var allow_lower_flag := false
var _min_provided := false

static func get_command_name():
	return "min_version"

static func get_self_command_data():
	return _command_data({
		&"help": _HELP + PECommandUtils.TARGET_HELP,
		&"positional_count": 1,
	})


func _get_flags() -> Dictionary:
	var options = Options.new()
	options.add_option("--verbose", {&"help": "List every occurrence with its file:line location."})
	options.add_option("--full", {&"help": "Future parser-based deep scan (not yet implemented)."})
	options.add_option("--update", {&"help": "Write the result to the package cfg's minimum_engine_version (raise only)."})
	options.add_option("--allow-lower", {&"help": "With --update, allow lowering the stored value."})
	options.add_option("--min=", {
		&"help": "Only show findings introduced above this Godot version (e.g. 4.4).",
		&"trailing_char": "",
	})
	return options.get_options()

func _process_flag(flag:String):
	if flag == "--verbose":
		verbose_flag = true
	elif flag == "--full":
		full_flag = true
	elif flag == "--update":
		update_flag = true
	elif flag == "--allow-lower":
		allow_lower_flag = true
	elif flag.begins_with("--min="):
		min_flag = _get_flag_value(flag)
		_min_provided = true

func _get_completions(ctx:Completion):
	if _completion_last_is_flag(ctx):
		return _get_completion_std_w_context(ctx, false)
	return PECommandUtils.plugin_name_completion(self, ctx, PECommandUtils.TargetAddons.VALID)

func _execute(ctx:Context):
	if min_flag == "":
		var min_var = ctx.get_variable("$GDPACKAGE_MIN_VERSION")
		min_flag = UString.unquote(min_var)
		if not min_flag.is_empty():
			_min_provided = true
	
	var addon_name = positional_args[0]
	var export_data = PluginExporter.PluginExporterStatic.get_export_data_by_name(addon_name)

	if not is_instance_valid(export_data) or not export_data.data_valid:
		ctx.append_output("Could not get export data for: " + addon_name)
		return ExitCode.FAIL

	var scanner = VersionScanner.new()
	if not scanner.api.has_index():
		ctx.append_error("No extension_api/api_min_version.json index found — run extract_api.gd (build) first.")
		return ExitCode.FAIL

	if full_flag:
		ctx.append_output("(--full parser-based deep scan not yet implemented; running standard scan)")

	# Display filter: only list findings introduced strictly above --min. -1 = no filter.
	var min_code := -1
	if _min_provided:
		if min_flag == "":
			ctx.append_error("--min needs a version and must appear before the addon name, e.g. `min_version --min=4.4 %s`." % addon_name)
		else:
			min_code = VersionApi.version_code(min_flag)
			if min_code == -1:
				ctx.append_error("Unrecognized --min version '%s'; showing all findings." % min_flag)

	var overall: String = scanner.api.baseline
	var all_files = {}
	var external_dirs = {}

	for export:Export in export_data.exports:
		all_files.merge(export.files_to_copy)
		for dir in export.external_dirs:
			external_dirs[dir] = true
		var r = scanner.scan_files(export.files_to_copy.keys())
		var export_min: String = r["min_version"]
		var all_findings: Array = r["findings"]    # every occurrence: {feature, version, location}

		overall = VersionApi.max_version(overall, export_min)

		var label = export.export_folder if export.export_folder != "" else export.source
		ctx.append_output("")
		ctx.append_output("Export: %s  ->  %s" % [label, export_min])

		if verbose_flag:
			all_findings.sort_custom(func(a, b):
				var ca = VersionApi.version_code(a["version"])
				var cb = VersionApi.version_code(b["version"])
				if ca != cb:
					return ca > cb
				return a["feature"] < b["feature"])
			for data in all_findings:
				if VersionApi.version_code(data["version"]) <= min_code:
					continue
				ctx.append_output("  %s  %s  ([url=%s]%s[/url])" % [data["version"], data["feature"], data["location"], data["location"].get_file()])
		else:
			var reasons := {}
			for data in all_findings:
				if VersionApi.version_code(data["version"]) <= min_code:
					continue
				reasons[data["feature"]] = data["version"]
			var features := reasons.keys()
			features.sort_custom(func(a, b):
				var ca = VersionApi.version_code(reasons[a])
				var cb = VersionApi.version_code(reasons[b])
				if ca != cb:
					return ca > cb
				return a < b)
			for feature in features:
				ctx.append_output("  %s  %s" % [reasons[feature], feature])

	var cache = {}
	var target = MinVersionStamp.package_dir(PluginExporter.UtilsLocal.ExportFileUtils.ExportPaths.resolve_target(addon_name).path_join("plugin.cfg"), cache)
	var dirs = MinVersionStamp.package_dirs_for(all_files.keys(), cache) + external_dirs.keys()
	dirs = dirs.filter(func(d): return d != target)
	var result = MinVersionStamp.compute(all_files.keys(), dirs)
	if not result.stored.is_empty():
		ctx.append_output("")
		ctx.append_output("Stored in package cfgs:")
		for dir in result.stored:
			ctx.append_output("  %s  %s" % [result.stored[dir], dir])
	var stored = MinVersionStamp.stored_value(target)
	var decision = MinVersionStamp.decide(stored, result.version, allow_lower_flag)

	ctx.append_output("")
	ctx.append_output("Minimum Godot version: %s" % VersionApi.max_version(overall, result.version))
	if stored != "":
		ctx.append_output("%s cfg: %s" % [target, stored])
	if update_flag:
		var stamped = MinVersionStamp.stamp(target, all_files.keys(), dirs, allow_lower_flag)
		if not stamped.ok:
			ctx.append_error(stamped.error)
			return ExitCode.FAIL
		ctx.append_output(stamped.line)
	elif decision.write:
		ctx.append_output("(--update writes %s=\"%s\")" % [MinVersionStamp.KEY, decision.value])
	return ExitCode.OK

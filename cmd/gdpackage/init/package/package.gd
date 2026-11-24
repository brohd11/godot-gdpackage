extends "res://addons/_lib/gdsh/src/core/command_base.gd" #! gdp-ignore

const PluginExporter = preload("res://addons/gdpackage/src/class/plugin_exporter.gd")
const PECommandUtils = preload("res://addons/gdpackage/src/class/command_utils.gd")
const PackageCfg = PluginExporter.UtilsLocal.ExportFileUtils.PackageCfg
const PluginInit = PluginExporter.PluginInit
const UString = PluginExporter.UtilsRemote.UString

const _HELP = \
"Initialize a folder as a library package: a package cfg, git init, src/, then plugin_init
Usage: gdpackage init package [--name=package|plugin|addon|version] [--force] <folder>
  --name=NAME  Cfg file to write, NAME.cfg (default: package; addon and version are legacy).
  --force      Overwrite an existing export config."

var name_flag := "package"
var force_flag := false

static func get_command_name() -> String:
	return "package"

static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP + PECommandUtils.TARGET_HELP,
		&"positional_count": 1
	})

func _get_flags() -> Dictionary:
	var options = Options.new()
	options.add_option("--name=", {
		&"help": "Cfg file to write: package, plugin, or legacy addon/version (default: package).",
		&"trailing_char": "",
	})
	options.add_option("--force", {
		&"help": "Overwrite an existing export config.",
	})
	return options.get_options()

func _process_flag(flag:String):
	if flag.begins_with("--name="):
		name_flag = UString.unquote(_get_flag_value(flag))
	elif flag == "--force":
		force_flag = true

func _get_completions(ctx:Completion):
	if _completion_last_is_flag(ctx):
		return _get_completion_std_w_context(ctx, false)
	return PECommandUtils.dir_completion(self, ctx, PluginExporter.get_unpackaged_dirs())

func _execute(ctx:Context):
	var cfg_name = name_flag if name_flag.ends_with(".cfg") else name_flag + ".cfg"
	if not cfg_name in PackageCfg.NAMES:
		ctx.append_error("Invalid --name=%s, expected one of: %s" % [name_flag, ", ".join(PackageCfg.NAMES.map(func(n): return n.get_basename()))])
		return ExitCode.FAIL
	var notes:Array[String] = []
	var config = PluginInit.write_package_init(positional_args[0], cfg_name, notes, force_flag)
	PECommandUtils.report_notes(ctx, notes, config == "")
	if config == "":
		return ExitCode.FAIL
	ctx.append_output("Package init complete: " + config.get_base_dir().get_base_dir())
	return ExitCode.OK

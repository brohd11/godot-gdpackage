extends GDSh.CommandBase

const PluginExporter = preload("res://addons/gdpackage/src/class/plugin_exporter.gd")
const PECommandUtils = preload("res://addons/gdpackage/src/editor_plugins/console_command/command_utils.gd")
const LicenseGenerator = preload("res://addons/gdpackage/src/editor_plugins/console_command/init/license/license_generator.gd")

# flag -> license id. Single source of truth shared by _get_flags/_process_flag and LicenseText.
const LICENSES = {
	"--mit": "mit",
	"--apache-2": "apache-2",
	"--gpl-3": "gpl-3",
	"--bsd-3": "bsd-3",
	"--isc": "isc",
}

const _HELP = \
"Generate a LICENSE file for a plugin
Usage: gdpackage init license <--type> <plugin_name> <name> <year>
  Exactly one license type flag is required:"

var _license_id := ""
var _flag_conflict := false

static func get_command_name() -> String:
	return "license"

static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP + PECommandUtils.TARGET_HELP,
		&"positional_count": 3,
	})

func _get_flags() -> Dictionary:
	var options = Options.new()
	options.add_option("--mit", {&"help": "MIT License"})
	options.add_option("--apache-2", {&"help": "Apache License 2.0"})
	options.add_option("--gpl-3", {&"help": "GNU General Public License v3.0"})
	options.add_option("--bsd-3", {&"help": "BSD 3-Clause License"})
	options.add_option("--isc", {&"help": "ISC License"})
	return options.get_options()

func _process_flag(flag:String):
	if LICENSES.has(flag):
		if _license_id != "":
			_flag_conflict = true
		_license_id = LICENSES[flag]

func _get_completions(ctx:Completion):
	if _completion_last_is_flag(ctx):
		return _get_completion_std_w_context(ctx, false)
	return PECommandUtils.plugin_name_completion(self, ctx, PECommandUtils.TargetAddons.ALL)

func _execute(ctx:Context):
	if _flag_conflict:
		ctx.append_error("Choose only one license type flag (%s)." % ", ".join(LICENSES.keys()))
		return ExitCode.FAIL
	if _license_id == "":
		ctx.append_error("A license type flag is required: %s" % ", ".join(LICENSES.keys()))
		return ExitCode.FAIL

	var plugin_name = positional_args[0]
	var name = positional_args[1]
	var year = positional_args[2]
	var success = LicenseGenerator.generate(plugin_name, name, year, _license_id, ctx)
	return ExitCode.OK if success else ExitCode.FAIL

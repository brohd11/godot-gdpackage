extends GDSh.CommandBase

## Rebuilds the trimmed min-version index (api_min_version.json) from the full
## extension_api dumps in gdpackage/_export_ignore/extension_api/ (or export_ignore/).
## The version list is baked from whatever dumps are present, so supporting a new
## Godot release is just: drop its extension_api_<major><minor>.json in that dir
## and re-run this command — no code changes.

const ExtractApi = preload("res://addons/gdpackage/src/editor_plugins/console_command/min_version/extract_api.gd")

const _HELP = \
"Rebuild the min_version API index from the extension_api dumps in
gdpackage/_export_ignore/extension_api/ (or export_ignore/).
Usage: gdpackage min_version generate_api"

static func get_command_name() -> String:
	return "generate_api"

static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP,
	})

func _execute(ctx:Context):
	var out_path = ExtractApi.build()
	if out_path == "":
		ctx.append_error("Failed to build API index — no extension_api dumps found (see output log).")
		return ExitCode.FAIL
	ctx.append_output("Wrote API index: " + out_path)
	return ExitCode.OK

@tool
extends RefCounted
## Drives a second Godot process against a throwaway project. Work runs as an autorun EditorPlugin
## in `--headless --editor` rather than `--script`, because both the export pipeline and exported
## plugins reach for EditorInterface; results come back as one sentinel line on stdout.

const PackageLayout = preload("res://addons/gdpackage/src/class/release/package_layout.gd")

const RESULT_PREFIX = "PE_RELEASE_RESULT "
const EXPORT_AUTORUN_DIR = "pe_release_autorun"

const _ERROR_PATTERNS = [
	r"SCRIPT ERROR: (?:Parse|Compile) Error.*",
	r"ERROR: Failed to load script.*",
	r"ERROR: .*[Pp]arse [Ee]rror.*",
]

const TEST_JOB = "res://addons/gdpackage/src/class/release/test_job.gd"
const TEST_TIMEOUT_SEC = 600

const _EXPORT_AUTORUN = """@tool
extends EditorPlugin
# Written by GDPackage's release export and test CI: runs one job (an export, or a package's
# test suites) once the editor has scanned, prints the result for the parent process, then quits.
# Loaded lazily so a pinned exporter can resolve its global classes first.

var _started := false
var _done := false
var _deadline := 0 # msec; 0 = the job runs within one frame

func _enter_tree() -> void:
	set_process(true)
	_run.call_deferred()

# A script error stops _run without quitting, and the parent editor would wait on this process
# forever. An export runs within one frame, so unfinished by the next it died; tests may await
# frames, so they get a deadline instead.
func _process(_delta:float) -> void:
	if not _started or _done:
		return
	if _deadline == 0:
		_finish({"ok": false, "error": "export aborted by a script error"}, 3)
	elif Time.get_ticks_msec() > _deadline:
		_finish({"ok": false, "error": "tests timed out, or a suite stopped on a script error mid-await"}, 3)

func _run() -> void:
	var fs = EditorInterface.get_resource_filesystem()
	await get_tree().process_frame
	while fs.is_scanning():
		await get_tree().process_frame
	_started = true

	var job = JSON.parse_string(FileAccess.get_file_as_string("res://addons/%s/job.json"))
	if job is Dictionary and job.get("kind", "") == "test":
		_deadline = Time.get_ticks_msec() + int(job.timeout) * 1000
		var runner = load(job.runner)
		if not _compiled(runner):
			_finish({"ok": false, "error": "test runner failed to compile (missing dependency?)"}, 3)
			return
		var report = await runner.run(job.dir)
		_finish({"ok": report.failed == 0, "report": report}, 0 if report.failed == 0 else 1)
		return
	var file_utils = load("res://addons/gdpackage/src/class/export/plugin_exporter_file_utils.gd")
	var exporter = load("res://addons/gdpackage/src/class/export/plugin_exporter_static.gd")
	if not job is Dictionary or not _compiled(file_utils) or not _compiled(exporter):
		_finish({"ok": false, "error": "exporter scripts failed to compile (missing dependency?)"}, 3)
		return

	# export_plugin, not export_by_name: only the former returns its result in older releases.
	var config = job.config
	var ok = FileAccess.file_exists(config) and exporter.export_plugin(config) == true
	var data = file_utils.get_export_data(config)
	var full = ""
	var exports = []
	if data:
		full = file_utils.get_full_export_path(data.export_root, data.plugin_folder, config)
		for e in data.exports:
			var folder = file_utils.get_export_folder(e, config)
			var package = full.path_join(file_utils.get_export_name(e, data.plugin_folder, config))
			exports.append({"dir": package.path_join(folder), "install_path": "res://" + folder.trim_suffix("/")})
	_finish({"ok": ok, "full_export_path": full, "exports": exports}, 0 if ok else 1)

# Not can_instantiate(): scripting is off in the editor, so that is false for any non-@tool script
# however cleanly it compiled. A script that failed to compile has no members at all.
func _compiled(script) -> bool:
	return script is GDScript and not script.get_script_method_list().is_empty()

func _finish(result:Dictionary, code:int) -> void:
	if _done:
		return
	_done = true
	print("%s" + JSON.stringify(result))
	get_tree().quit(code)
"""


static func godot(project_dir:String, args:Array) -> Dictionary:
	var full_args = ["--headless", "--path", project_dir]
	full_args.append_array(args)
	var output = []
	var code = OS.execute(OS.get_executable_path(), full_args, output, true)
	return {"exit": code, "output": "".join(output)}


## Imports first: without it every class_name reads as undeclared on the editor run.
static func run_export(project_dir:String, config_path:String) -> Dictionary:
	return _run_job(project_dir, {"config": config_path})


## Runs every suite under `test_dir` (res://) through the toolchain's TEST_JOB. The result's
## `report` is TestRunner's: {suites: [{path, passed, output}], failed, invalid}.
static func run_tests(project_dir:String, test_dir:String, timeout_sec:int = TEST_TIMEOUT_SEC) -> Dictionary:
	return _run_job(project_dir, {"kind": "test", "dir": test_dir, "runner": TEST_JOB, "timeout": timeout_sec})


static func _run_job(project_dir:String, job:Dictionary) -> Dictionary:
	var job_path = project_dir.path_join("addons").path_join(EXPORT_AUTORUN_DIR).path_join("job.json")
	var file = FileAccess.open(job_path, FileAccess.WRITE)
	if file == null:
		return {"exit": -1, "output": "could not write " + job_path, "result": {}}
	file.store_string(JSON.stringify(job))
	file.close()

	var imported = godot(project_dir, ["--import"])
	var res = godot(project_dir, ["--editor"])
	res.output = imported.output + res.output
	res.result = result_of(res.output)
	return res


static func write_export_autorun(project_dir:String) -> bool:
	return write_plugin(project_dir, EXPORT_AUTORUN_DIR, _EXPORT_AUTORUN % [EXPORT_AUTORUN_DIR, RESULT_PREFIX])


static func write_plugin(project_dir:String, dir_name:String, script_text:String) -> bool:
	var dir = project_dir.path_join("addons").path_join(dir_name)
	DirAccess.make_dir_recursive_absolute(dir)
	var cfg = '[plugin]\n\nname="%s"\ndescription=""\nauthor=""\nversion="1.0"\nscript="plugin.gd"\n' % dir_name
	return _write(dir.path_join("plugin.cfg"), cfg) and _write(dir.path_join("plugin.gd"), script_text)


## Minimal project.godot. Features only carry the running engine version: the dev project's "C#"
## would make a mono editor go looking for a solution the workspace doesn't have.
static func project_godot(project_name:String, enabled_plugins:Array, extra_sections:String = "") -> String:
	var info = Engine.get_version_info()
	var plugins = ", ".join(enabled_plugins.map(func(p): return '"%s"' % p))
	var text = 'config_version=5\n\n[application]\n\nconfig/name="%s"\nconfig/features=PackedStringArray("%d.%d")\n' % [
		project_name, info.major, info.minor]
	if extra_sections != "":
		text += "\n" + extra_sections.strip_edges() + "\n"
	text += "\n[editor_plugins]\n\nenabled=PackedStringArray(%s)\n" % plugins
	return text


## A raw section (header included) from a project.godot, or "".
static func project_section(project_text:String, section:String) -> String:
	var lines = []
	var inside = false
	for line in project_text.split("\n"):
		if line.begins_with("["):
			inside = line.strip_edges() == "[%s]" % section
		if inside:
			lines.append(line)
	return "\n".join(lines).strip_edges()


static func result_of(output:String) -> Dictionary:
	for line in Array(output.split("\n")).filter(func(l): return l.begins_with(RESULT_PREFIX)):
		var parsed = JSON.parse_string(line.trim_prefix(RESULT_PREFIX))
		if parsed is Dictionary:
			return parsed
	return {}


## Parse/compile/load errors in a Godot run's output, each with its "at:" line when present.
static func script_errors(output:String) -> Array[String]:
	var regexes = _ERROR_PATTERNS.map(func(p):
		var r = RegEx.new()
		r.compile(p)
		return r)
	var lines = output.split("\n")
	var out:Array[String] = []
	for i in lines.size():
		var line = lines[i].strip_edges()
		if not regexes.any(func(r): return r.search(line) != null):
			continue
		if i + 1 < lines.size() and lines[i + 1].strip_edges().begins_with("at:"):
			line += "  " + lines[i + 1].strip_edges()
		if not line in out:
			out.append(line)
	return out


## `skip`: file or dir names left out at any depth, e.g. ".git".
static func copy_dir(from_dir:String, to_dir:String, skip:Array = []) -> bool:
	DirAccess.make_dir_recursive_absolute(to_dir)
	var dir = DirAccess.open(from_dir)
	if dir == null:
		return false
	dir.include_hidden = true
	for f in dir.get_files():
		if f in skip:
			continue
		if DirAccess.copy_absolute(from_dir.path_join(f), to_dir.path_join(f)) != OK:
			return false
	for d in dir.get_directories():
		if d in skip:
			continue
		if not copy_dir(from_dir.path_join(d), to_dir.path_join(d), skip):
			return false
	return true


## Extracts every entry of zip_path under dest_dir. Returns an error message, or "" on success.
static func unzip(zip_path:String, dest_dir:String) -> String:
	var reader = ZIPReader.new()
	if reader.open(zip_path) != OK:
		return "could not open archive " + zip_path
	for entry in reader.get_files():
		if PackageLayout.is_junk(entry):
			continue
		if entry.simplify_path().begins_with(".."):
			reader.close()
			return "archive entry escapes its directory: " + entry
		var target = dest_dir.path_join(entry)
		if entry.ends_with("/"):
			DirAccess.make_dir_recursive_absolute(target)
			continue
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		var file = FileAccess.open(target, FileAccess.WRITE)
		if file == null:
			reader.close()
			return "could not write " + target
		file.store_buffer(reader.read_file(entry))
		file.close()
	reader.close()
	return ""


static func remove_dir(path:String) -> void:
	var dir = DirAccess.open(path)
	if dir == null:
		return
	dir.include_hidden = true
	for f in dir.get_files():
		DirAccess.remove_absolute(path.path_join(f))
	for d in dir.get_directories():
		remove_dir(path.path_join(d))
	DirAccess.remove_absolute(path)


static func _write(path:String, text:String) -> bool:
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.close()
	return true

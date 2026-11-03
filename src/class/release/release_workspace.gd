@tool
extends RefCounted
## The throwaway project a release export runs in: every lock entry's addon folder copied out of
## its staged package into its install path, the standalone exporter as toolchain, and a minimal
## project.godot. Keyed by lock hash and reused, so an unchanged lock keeps its .godot import cache.

const DepResolver = preload("res://addons/gdpackage/src/class/release/dep_resolver.gd")
const ReleaseRunner = preload("res://addons/gdpackage/src/class/release/release_runner.gd")
const ExportIgnore = preload("uid://c4pt5djyuf8c") #! resolve GDPackageSpec.ExportIgnore
const ExportPaths = preload("res://addons/gdpackage/src/class/export/export_paths.gd")

const READY_MARKER = ".pe_release_ready"
const TOOLCHAIN_PATH = "res://addons/gdpackage"

var fetcher # PackageFetcher
var errors:Array[String] = []


func _init(package_fetcher) -> void:
	fetcher = package_fetcher


const WORKSPACES = "workspaces"
const TEST_WORKSPACES = "test_workspaces" # apart from WORKSPACES: each prunes its own


func workspace_dir(target_name:String, lock:Dictionary, kind:String = WORKSPACES) -> String:
	var key = ExportPaths.workspace_key(target_name)
	if key == "":
		return ""
	return fetcher.root.path_join(kind).path_join("%s-%s" % [key, DepResolver.lock_hash(lock)])


## Builds (or reuses) the workspace and points its export at export_root_abs. `toolchain_dir` may be
## "" only when the target is gdpackage itself, whose pinned checkout is then the toolchain.
## Returns the absolute workspace dir, or "" with `errors` filled.
func build(lock:Dictionary, target_name:String, toolchain_dir:String, export_root_abs:String, debug_section:String) -> String:
	errors.clear()
	var ws = _prepare(lock, target_name, toolchain_dir, debug_section, WORKSPACES)
	if ws == "" or not _point_export_root(ws.path_join(lock.target.path.trim_prefix("res://")), export_root_abs):
		return ""
	return ws


## The workspace test CI runs in: deps from the lock as in build(), the target copied from
## `tree_dir` (resolve_tree's lock) on every run, since the tree changes without the lock noticing.
func build_tests(lock:Dictionary, target_name:String, toolchain_dir:String, tree_dir:String, debug_section:String) -> String:
	errors.clear()
	var ws = _prepare(lock, target_name, toolchain_dir, debug_section, TEST_WORKSPACES)
	if ws == "":
		return ""
	var target_dir = ws.path_join(lock.target.path.trim_prefix("res://"))
	ReleaseRunner.remove_dir(target_dir)
	if not _copy_tree(ProjectSettings.globalize_path(tree_dir), target_dir):
		errors.append("could not copy %s into the workspace" % tree_dir)
		return ""
	return ws


## Tracked and untracked files minus ignored ones (old exports, caches), so a local run sees what
## a CI checkout would. Not a repo: everything but .git. Newline-separated, not -z: OS.execute
## decodes output as UTF-8, and a NUL there (or a char(0) the analyzer folds) logs parse errors.
static func _copy_tree(from_dir:String, to_dir:String) -> bool:
	var output = []
	if OS.execute("git", ["-c", "core.quotePath=false", "-C", from_dir, "ls-files", "-co", "--exclude-standard"], output) != 0:
		return ReleaseRunner.copy_dir(from_dir, to_dir, [".git"])
	for rel in "".join(output).split("\n", false):
		if rel.begins_with("\""):
			push_warning("test workspace: skipped %s (quotes, backslashes or control characters in its path)" % rel)
			continue
		var dest = to_dir.path_join(rel)
		if not FileAccess.file_exists(from_dir.path_join(rel)):
			continue # deleted, not yet staged
		DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
		if DirAccess.copy_absolute(from_dir.path_join(rel), dest) != OK:
			return false
	return true


func _prepare(lock:Dictionary, target_name:String, toolchain_dir:String, debug_section:String, kind:String) -> String:
	var ws = workspace_dir(target_name, lock, kind)
	if ws == "":
		errors.append("invalid workspace target: " + target_name)
		return ""
	_prune_other_workspaces(target_name, ws)
	if not FileAccess.file_exists(ws.path_join(READY_MARKER)):
		if DirAccess.dir_exists_absolute(ws):
			ReleaseRunner.remove_dir(ws) # a half-built one from an interrupted run
		if not _populate(ws, lock, toolchain_dir):
			return ""
		FileAccess.open(ws.path_join(READY_MARKER), FileAccess.WRITE).close()

	# Redone on reuse too: all cheap, and the export root is the one input not in the lock.
	if not _write_project(ws, target_name, debug_section):
		return ""
	if not ReleaseRunner.write_export_autorun(ws):
		errors.append("could not write the autorun plugin into " + ws)
		return ""
	return ws


func _populate(ws:String, lock:Dictionary, toolchain_dir:String) -> bool:
	var installed = {} # res:// path -> repo_id
	for entry in [lock.target] + lock.deps:
		if entry == lock.target and entry.get("source") == "tree":
			continue # copied by build_tests
		if entry != lock.target and entry.path == TOOLCHAIN_PATH:
			errors.append("%s installs at %s, where the toolchain has to live" % [entry.repo_id, TOOLCHAIN_PATH])
			return false
		if installed.has(entry.path):
			errors.append("%s and %s both install at %s" % [installed[entry.path], entry.repo_id, entry.path])
			return false
		installed[entry.path] = entry.repo_id

		var staged = fetcher.stage(entry)
		if staged == "":
			errors.append("%s@%s: %s" % [entry.repo_id, entry.tag, fetcher.last_error])
			return false
		var package = entry.get("package", "")
		var src = staged.path_join(package) if package != "" else staged
		if not ReleaseRunner.copy_dir(src, ws.path_join(entry.path.trim_prefix("res://"))):
			errors.append("%s@%s: could not copy %s into the workspace" % [entry.repo_id, entry.tag, src])
			return false

	if lock.target.path != TOOLCHAIN_PATH:
		if toolchain_dir == "" or not ReleaseRunner.copy_dir(toolchain_dir, ws.path_join("addons/gdpackage")):
			errors.append("could not copy the standalone exporter from '%s'" % toolchain_dir)
			return false
	return true


## Only the autorun is enabled. The exporter is loaded as plain scripts, so its EditorPlugin (and
## the singleton modules it registers with) never has to start up in the workspace.
func _write_project(ws:String, target_name:String, debug_section:String) -> bool:
	var project = ReleaseRunner.project_godot("PE Release %s" % target_name, [
		"res://addons/%s/plugin.cfg" % ReleaseRunner.EXPORT_AUTORUN_DIR,
	], debug_section)
	var file = FileAccess.open(ws.path_join("project.godot"), FileAccess.WRITE)
	if file == null:
		errors.append("could not write project.godot in " + ws)
		return false
	file.store_string(project)
	file.close()
	return true


## Rewrites the target config's export_root in place so output lands where a workspace export puts
## it. A line edit rather than a parse/dump, which would drop the config's comments.
func _point_export_root(target_dir:String, export_root_abs:String) -> bool:
	var config_path = ExportIgnore.config_path(target_dir)
	if not FileAccess.file_exists(config_path):
		errors.append("no export config in _export_ignore/ or export_ignore/ of the tagged checkout at " + target_dir)
		return false

	var text = FileAccess.get_file_as_string(config_path)
	# Checked here so an unmigrated tagged config fails before a Godot process is spent on it.
	var folder_regex = RegEx.new()
	folder_regex.compile(r'(?m)^\s*"?export_folder"?\s*:\s*"([^"]*)"')
	for m in folder_regex.search_all(text):
		var reason = ExportPaths.export_folder_error(m.get_string(1))
		if reason != "":
			errors.append('%s in the tagged checkout: export_folder "%s" %s; commit the fixed config and re-tag' % [
				config_path, m.get_string(1), reason])
			return false

	var regex = RegEx.new()
	regex.compile(r'(?m)^(\s*"?export_root"?\s*:\s*)"[^"]*"')
	if regex.search(text) == null:
		errors.append("no export_root in " + config_path)
		return false
	var file = FileAccess.open(config_path, FileAccess.WRITE)
	file.store_string(regex.sub(text, '$1"%s"' % export_root_abs))
	file.close()
	return true


## One workspace per target: re-tagging under --local changes the lock hash on every attempt.
## Matches the canonical target key and lock hash, so packages sharing a basename stay separate.
func _prune_other_workspaces(target_name:String, keep:String) -> void:
	var dir = keep.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		return
	var prefix = ExportPaths.workspace_key(target_name) + "-"
	for d in DirAccess.get_directories_at(dir):
		var suffix = d.trim_prefix(prefix)
		if not d.begins_with(prefix) or suffix.length() != 16 or not suffix.is_valid_hex_number():
			continue
		if dir.path_join(d) != keep:
			ReleaseRunner.remove_dir(dir.path_join(d))

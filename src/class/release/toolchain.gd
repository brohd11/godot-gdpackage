@tool
extends RefCounted
## The released gdpackage a release export runs in its workspace - Go's toolchain, in effect.
## Its version is `toolchain` in the export config's options, or the dev exporter's version when
## unset. Normally the GitHub release zip, downloaded once and cached. `local` (--local-toolchain)
## instead exports this project's gdpackage on demand, to test unreleased exporter changes.

const UtilsLocal = preload("res://addons/gdpackage/src/class/utils_local.gd")
const UtilsRemote = preload("res://addons/gdpackage/src/class/utils_remote.gd")
const ExportFileUtils = UtilsLocal.ExportFileUtils
const KeysConfig = ExportFileUtils.KeysConfig
const DepResolver = preload("res://addons/gdpackage/src/class/release/dep_resolver.gd")
const ReleaseRunner = preload("res://addons/gdpackage/src/class/release/release_runner.gd")

const NAME = "gdpackage"
const CONFIG_KEY = "toolchain"
const DEV_DIR = "res://addons/gdpackage"
const FALLBACK_REPO = "https://github.com/brohd11/godot-gdpackage"
const ASSET = "gdpackage-%s.zip"

var errors:Array[String] = []


## {dir, version, source: "remote"|"local", id}, or {} with `errors` filled. `local` ignores the
## `toolchain` pin: the dev copy is whatever version it is.
func resolve(options:Dictionary, cache_root:String, refresh:bool, local:bool = false, reporter = null) -> Dictionary:
	errors.clear()
	if local:
		return _resolve_local(reporter)
	var version = pick_version(options, _cfg_version(DEV_DIR)).trim_prefix("v")
	if version == "":
		errors.append("no toolchain version: set options.%s or give %s a version=" % [CONFIG_KEY, DEV_DIR])
		return {}
	return _resolve_remote(version, cache_root, refresh)


static func pick_version(options:Dictionary, dev_version:String) -> String:
	var pinned = str(options.get(CONFIG_KEY, "")).strip_edges()
	return pinned if pinned != "" else dev_version


## Release asset urls to try, `v<ver>` tag first. Keeps the repo's own casing - only `www.` and
## `.git` go, and an scp-style remote becomes https.
static func asset_urls(repo_url:String, version:String) -> Array[String]:
	var base = repo_url.strip_edges().trim_suffix("/").trim_suffix(".git").replace("://www.", "://")
	if not "://" in base and "@" in base:
		base = "https://" + base.get_slice("@", 1).replace(":", "/")
	var bare = version.trim_prefix("v")
	var out:Array[String] = []
	for tag in ["v" + bare, bare]:
		out.append("%s/releases/download/%s/%s" % [base, tag, ASSET % bare])
	return out


func _resolve_remote(version:String, cache_root:String, refresh:bool) -> Dictionary:
	var dir = cache_root.path_join("toolchains").path_join("%s-%s" % [NAME, version])
	var zip_path = dir.path_join(ASSET % version)
	var plugin_dir = dir.path_join(DEV_DIR.trim_prefix("res://")) # release zips carry the install layout
	var cached = FileAccess.file_exists(zip_path) and FileAccess.file_exists(plugin_dir.path_join("plugin.cfg"))

	if refresh or not cached:
		if DirAccess.dir_exists_absolute(dir):
			ReleaseRunner.remove_dir(dir)
		DirAccess.make_dir_recursive_absolute(dir)
		if not _download(_repo_url(), version, zip_path):
			ReleaseRunner.remove_dir(dir)
			return {}
		var err = ReleaseRunner.unzip(zip_path, dir)
		if err != "":
			errors.append(err)
			ReleaseRunner.remove_dir(dir)
			return {}

	return _checked(plugin_dir, version, "remote", FileAccess.get_sha256(zip_path))


## Exporting needs EditorInterface, so this only works inside the editor (the console, not the CLIs).
func _resolve_local(reporter) -> Dictionary:
	if not Engine.is_editor_hint():
		errors.append("--local-toolchain exports the dev %s in-process, which needs the editor" % NAME)
		return {}
	var version = _cfg_version(DEV_DIR).trim_prefix("v")
	var config_path = ExportFileUtils.get_export_config_path(DEV_DIR, reporter)
	var config = ExportFileUtils.get_export_data(config_path, reporter) if config_path != "" else null
	if not config is Dictionary or config.get(KeysConfig.EXPORTS, []).is_empty():
		errors.append("no usable export config for %s at '%s'" % [DEV_DIR, config_path])
		return {}
	if not UtilsLocal.PluginExporterStatic.export_plugin(config_path, null, null, reporter):
		errors.append("exporting the dev %s failed" % NAME)
		return {}

	var plugin_folder = config.get(KeysConfig.PLUGIN_FOLDER)
	var root = ExportFileUtils.get_full_export_path(config.get(KeysConfig.EXPORT_ROOT), plugin_folder, config_path, reporter)
	var entry = config.get(KeysConfig.EXPORTS)[0]
	var dir = root.path_join(ExportFileUtils.get_export_name(entry, plugin_folder, config_path, reporter)) \
		.path_join(ExportFileUtils.get_export_folder(entry, config_path))
	return _checked(dir, version, "local", _dir_id(dir))


## Content hash of an exported tree: the workspace is keyed on it, so an unchanged exporter reuses one.
static func _dir_id(dir:String) -> String:
	var lines = []
	for f:String in UtilsRemote.GetFiles.scan(dir):
		var path = dir.path_join(f) if f.is_relative_path() else f
		lines.append("%s:%s" % [path.trim_prefix(dir), FileAccess.get_sha256(path)])
	lines.sort()
	return "local-" + "\n".join(lines).sha256_text()


func _checked(plugin_dir:String, version:String, source:String, id:String) -> Dictionary:
	var found = _cfg_version(plugin_dir).trim_prefix("v")
	if found != version:
		errors.append("%s toolchain at %s is %s, expected %s" % [source, plugin_dir, found if found != "" else "unversioned", version])
		return {}
	return {"dir": plugin_dir, "version": version, "source": source, "id": id}


func _download(repo_url:String, version:String, zip_path:String) -> bool:
	var failures:Array[String] = []
	for url in asset_urls(repo_url, version):
		var result = _run_curl(["-fsSL", "--retry", "2", "--retry-delay", "1",
			"--connect-timeout", "10", "--max-time", "30", "-o", zip_path, url])
		if result.exit_code == 0:
			return true
		var detail:String = result.output.strip_edges()
		failures.append("%s (curl exit %d)%s" % [url, result.exit_code, ": " + detail if detail != "" else ""])
	DirAccess.remove_absolute(zip_path)
	errors.append("could not download %s for toolchain %s:\n  %s" % [ASSET % version, version, "\n  ".join(failures)])
	return false


func _run_curl(args:Array) -> Dictionary:
	var output = []
	var code = OS.execute("curl", args, output, true)
	return {"exit_code": code, "output": "".join(output)}


static func _repo_url() -> String:
	var url = DepResolver.origin_url(DEV_DIR) if DirAccess.dir_exists_absolute(DEV_DIR) else ""
	return url if url != "" else FALLBACK_REPO


static func _cfg_version(dir:String) -> String:
	return str(DepResolver.PackageCfg.dir_value(dir, "version", ""))

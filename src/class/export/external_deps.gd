@tool
extends RefCounted
## Resolves export config `external:` entries: packages a release references but never bundles.
## A res:// entry names a dir as-is. Anything else is a require spec, matched to a local package by
## the release workspace's install map, then its cfg url=, then a checkout's git origin. Specs also
## go into the released cfg's require, and DepResolver installs them for build and compile.

const DepResolver = preload("res://addons/gdpackage/src/class/release/dep_resolver.gd")
const PackageDiscovery = preload("res://addons/gdpackage/src/class/export/package_discovery.gd")
const PackageCfg = preload("uid://ddo8w07hts45v") #! resolve GDPackageSpec.Cfg
const ReleaseRunner = preload("res://addons/gdpackage/src/class/release/release_runner.gd")

## Written by ReleaseWorkspace from the lock; absent in the dev project.
const INSTALLED_MAP = "res://addons/" + ReleaseRunner.EXPORT_AUTORUN_DIR + "/installed.json"


## Config value -> list of entries; accepts a list or a single string, like exported_require.
static func entries(value) -> Array:
	if value is Array:
		return value.filter(func(e): return e is String and e.strip_edges() != "").map(func(e): return e.strip_edges())
	if value is String and value.strip_edges() != "":
		return [value.strip_edges()]
	return []


## {dirs: Array[String] (trailing "/"), specs: Array[String], errors: Array[String]}.
## `dev_repos` (repo_id -> res:// dir) is scanned on demand when null; tests pass their own, and
## an `installed_map` path of their own.
static func resolve(items:Array, root:String = "res://addons", dev_repos = null, installed_map:String = INSTALLED_MAP) -> Dictionary:
	var out = {"dirs": [], "specs": [], "errors": []}
	var installed = _read_map(installed_map)
	var url_index = null
	for item:String in items:
		if item.begins_with("res://"):
			if not DirAccess.dir_exists_absolute(item):
				out.errors.append("external dir does not exist: " + item)
				continue
			_add_dir(out.dirs, item)
			continue
		var dep = DepResolver.parse_dep(item)
		if dep == null:
			out.errors.append("external entry is neither a res:// dir nor a require spec: " + item)
			continue
		var dir = String(installed.get(dep.repo_id, ""))
		if dir == "":
			if url_index == null:
				url_index = cfg_url_index(root)
			dir = url_index.get(dep.repo_id, "")
		if dir == "":
			if dev_repos == null:
				dev_repos = DepResolver.scan_dev_repos()
			dir = dev_repos.get(dep.repo_id, "")
		if dir == "":
			out.errors.append("external %s: no local package found; add url= to its package cfg or list its res:// dir" % item)
			continue
		_add_dir(out.dirs, dir)
		out.specs.append(item)
	return out


## repo_id of the package cfg url= in `dir`, or "".
static func dir_repo_id(dir:String) -> String:
	var path = PackageCfg.find(dir)
	if path == "":
		return ""
	var url = DepResolver.unquote(String(PackageCfg.section(FileAccess.get_file_as_string(path)).get("url", "")))
	return DepResolver.repo_id_from_url(url)


## Set of repo_ids the parseable `specs` name.
static func repo_ids(specs:Array) -> Dictionary:
	var ids = {}
	for spec in specs:
		var dep = DepResolver.parse_dep(String(spec))
		if dep != null:
			ids[dep.repo_id] = true
	return ids


## repo_id -> res:// dir for every package under `root` whose cfg carries url=.
static func cfg_url_index(root:String = "res://addons") -> Dictionary:
	var out = {}
	for rel:String in PackageDiscovery.discover(root, PackageDiscovery.Filter.ALL):
		var dir = root.path_join(rel)
		var id = dir_repo_id(dir)
		if id != "" and not out.has(id):
			out[id] = dir
	return out


## `specs` merged into `require` without repeating a repo already listed in any spelling.
static func merge_require(require:Array, specs:Array) -> Array:
	var out = require.duplicate()
	var ids = repo_ids(out)
	for spec:String in specs:
		var dep = DepResolver.parse_dep(spec)
		if dep == null or ids.has(dep.repo_id):
			continue
		ids[dep.repo_id] = true
		out.append(spec)
	return out


static func _read_map(path:String) -> Dictionary:
	if path == "" or not FileAccess.file_exists(path):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}


static func _add_dir(dirs:Array, dir:String) -> void:
	dir = dir.simplify_path().trim_suffix("/") + "/"
	if not dir in dirs:
		dirs.append(dir)

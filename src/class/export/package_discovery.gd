@tool
extends RefCounted
## Package snapshots are rebuilt on demand after editor filesystem changes.

const ExportIgnore = preload("uid://c4pt5djyuf8c") #! resolve GDPackageSpec.ExportIgnore
const PackageCfg = preload("uid://ddo8w07hts45v") #! resolve GDPackageSpec.Cfg

enum Filter { ALL, VALID, NOT_VALID }

static var _cache:Dictionary = {} # absolute root -> {relative package path: configured}
static var _filesystem_connected := false


static func discover(root:String = "res://addons", filter:int = Filter.VALID) -> Dictionary:
	if filter not in [Filter.ALL, Filter.VALID, Filter.NOT_VALID]:
		return {}
	_connect_filesystem()
	var key = ProjectSettings.globalize_path(root).simplify_path().trim_suffix("/")
	if not _cache.has(key):
		var paths:Array[String] = []
		_scan(key, "", paths)
		paths.sort()
		var packages = {}
		for path in paths:
			packages[path] = FileAccess.file_exists(ExportIgnore.config_path(key.path_join(path)))
		_cache[key] = packages
	var result = {}
	for path in _cache[key]:
		var configured:bool = _cache[key][path]
		if filter == Filter.VALID and not configured:
			continue
		if filter == Filter.NOT_VALID and configured:
			continue
		result[path] = {}
	return result


## Dirs with no package cfg (PackageCfg.NAMES) and no package anywhere below them - package_init
## candidates, so no package ends up inside another. Uncached so a freshly initialized dir and its
## parents drop off at once.
static func discover_unpackaged(root:String = "res://addons", max_depth:int = 2) -> Dictionary:
	var paths:Array[String] = []
	_scan_unpackaged(ProjectSettings.globalize_path(root).simplify_path().trim_suffix("/"), "", max_depth, paths)
	paths.sort()
	var result = {}
	for path in paths:
		result[path] = {}
	return result


static func clear_cache() -> void:
	_cache.clear()


static func _connect_filesystem() -> void:
	if _filesystem_connected or not Engine.is_editor_hint():
		return
	var editor_interface = Engine.get_singleton("EditorInterface")
	if not is_instance_valid(editor_interface):
		return # Retry on the next lookup if the editor is still starting.
	var fs = editor_interface.get_resource_filesystem()
	if not is_instance_valid(fs):
		return
	if not fs.filesystem_changed.is_connected(clear_cache):
		fs.filesystem_changed.connect(clear_cache)
	clear_cache() # Discard any snapshot taken before filesystem notifications were available.
	_filesystem_connected = true


static func _scan(root:String, relative:String, paths:Array[String]) -> void:
	var dir = root.path_join(relative)
	var access = DirAccess.open(dir)
	if access == null:
		return
	if relative != "" and PackageCfg.NAMES.any(access.file_exists):
		paths.append(relative)
		var cfgs = PackageCfg.find_all(dir)
		if cfgs.size() > 1: # only the first is read; gdaddon does the same
			push_warning("GDPackage: %s has several package cfgs, only %s is read: %s" % [
				dir, cfgs[0].get_file(), ", ".join(cfgs.map(func(c): return c.get_file()))])
	for child in access.get_directories():
		if child.begins_with(".") or ExportIgnore.is_name(child) or access.is_link(child):
			continue
		_scan(root, relative.path_join(child), paths)


## Returns whether a package sits below [param relative]. Walks past max_depth for that answer alone,
## so a deep package still rules out its ancestors; it never enters a package, which keeps it cheap.
static func _scan_unpackaged(root:String, relative:String, depth_left:int, paths:Array[String]) -> bool:
	var access = DirAccess.open(root.path_join(relative))
	if access == null:
		return false
	var has_package := false
	for child in access.get_directories():
		if child.begins_with(".") or ExportIgnore.is_name(child) or access.is_link(child):
			continue
		var child_relative = relative.path_join(child)
		if PackageCfg.has_cfg(root.path_join(child_relative)):
			has_package = true
			continue
		if _scan_unpackaged(root, child_relative, depth_left - 1, paths):
			has_package = true
		elif depth_left > 0:
			paths.append(child_relative)
	return has_package

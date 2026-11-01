@tool
extends RefCounted
## The reverse of require check: every package under a root that declares a repo among its
## requires, read as RequireCheck reads them (cfg require=, or the export config's
## build/compile/test_require with @require expanded). Matched by repo_id, so any spelling of the
## repo - host, /release, clone:, a tag - finds the same consumers.

const DepResolver = preload("res://addons/package_exporter/src/class/release/dep_resolver.gd")
const RequireCheck = preload("res://addons/package_exporter/src/class/release/require_check.gd")
const RequireUpdate = preload("res://addons/package_exporter/src/class/release/require_update.gd")
const PackageDiscovery = preload("res://addons/package_exporter/src/class/export/package_discovery.gd")

const KEYS = ["build", "compile", "test"] # display order


## {id, rows: [{package, spec, keys}], warnings, error}. `package` is relative to `root`; a package
## pinning the repo two ways gets a row per spec, each with the keys it appears under.
static func find(target:String, root:String = "res://addons") -> Dictionary:
	var out = {"id": "", "rows": [], "warnings": [], "error": ""}
	var target_dep = DepResolver.parse_dep(target)
	if target_dep == null:
		out.error = "not a require spec (owner/repo): " + target
		return out
	out.id = target_dep.repo_id
	for package in PackageDiscovery.discover(root, PackageDiscovery.Filter.ALL):
		var declared = _declared(root.path_join(package))
		if declared.error != "":
			out.warnings.append("%s: %s" % [package, declared.error])
		var by_spec = {} # spec -> {key: true}
		for req in declared.requires:
			if req.dep.repo_id != out.id:
				continue
			var spec = RequireCheck._spec(req.dep)
			if not by_spec.has(spec):
				by_spec[spec] = {}
			by_spec[spec]["compile" if req.compile else ("test" if req.test else "build")] = true
		for spec in by_spec:
			out.rows.append({"package": package, "spec": spec,
				"keys": KEYS.filter(func(k): return by_spec[spec].has(k))})
	out.rows.sort_custom(func(a, b): return a.package < b.package if a.package != b.package else a.spec < b.spec)
	return out


static func format(result:Dictionary) -> String:
	if result.rows.is_empty():
		return "No package requires %s." % RequireUpdate.short_id(result.id)
	var package_width = 0
	var spec_width = 0
	for row in result.rows:
		package_width = maxi(package_width, row.package.length())
		spec_width = maxi(spec_width, row.spec.length())
	var lines:Array[String] = []
	for row in result.rows:
		lines.append("%s  %s  %s" % [row.package.rpad(package_width), row.spec.rpad(spec_width), ", ".join(row.keys)])
	return "\n".join(lines)


## Short ids of every repo any package declares, sorted - completion candidates. File reads only.
static func required_ids(root:String = "res://addons") -> Array:
	var ids = {}
	for package in PackageDiscovery.discover(root, PackageDiscovery.Filter.ALL):
		for req in _declared(root.path_join(package)).requires:
			ids[RequireUpdate.short_id(req.dep.repo_id)] = true
	var out = ids.keys()
	out.sort()
	return out


## {requires: [{dep, compile, test}], error}, the same sources RequireCheck.check_tags reads.
static func _declared(dir:String) -> Dictionary:
	var cfg_path = DepResolver.PackageCfg.find(dir)
	var cfg_text = FileAccess.get_file_as_string(cfg_path) if cfg_path != "" else ""
	for path in DepResolver.ExportIgnore.candidates(dir, DepResolver.CONFIG_NAMES):
		if FileAccess.file_exists(path):
			return DepResolver.requires_in_export_config(FileAccess.get_file_as_string(path), path.get_extension(), cfg_text, true)
	return DepResolver.requires_in_data({}, cfg_text, true)

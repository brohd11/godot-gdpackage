@tool
extends RefCounted
## Checks a package's declared requires the way a build fetches them: the cfg's require plus its
## export config's build/compile/test_require, each looked up at its tag through PackageFetcher, so
## an unpushed tag or a /release without one matching asset fails here instead of in CI.

const DepResolver = preload("res://addons/gdpackage/src/class/release/dep_resolver.gd")
const RepoCache = preload("res://addons/gdpackage/src/class/release/repo_cache.gd")
const ReleaseCache = preload("res://addons/gdpackage/src/class/release/release_cache.gd")
const PackageFetcher = preload("res://addons/gdpackage/src/class/release/package_fetcher.gd")


## {rows: [{spec, key, tag, ok, reason, note}], errors}. `key` is where the spec came from (build,
## compile, test); `tag` the one that resolved; `note` says when a checkout in this project is past
## the declared tag. `fetcher` is a PackageFetcher (or a test's fake); a real one when null.
static func check_tags(package_dir:String, fetcher = null, dev_repos = null) -> Dictionary:
	var out = {"rows": [], "errors": []}
	var cfg_path = DepResolver.PackageCfg.find(package_dir)
	if cfg_path == "":
		out.errors.append("%s has no package cfg (%s)" % [package_dir, "/".join(DepResolver.CFG_NAMES)])
		return out
	var cfg_text = FileAccess.get_file_as_string(cfg_path)
	var declared = DepResolver.requires_in_data({}, cfg_text, true)
	for path in DepResolver.ExportIgnore.candidates(package_dir, DepResolver.CONFIG_NAMES):
		if FileAccess.file_exists(path):
			declared = DepResolver.requires_in_export_config(FileAccess.get_file_as_string(path), path.get_extension(), cfg_text, true)
			break
	if declared.error != "":
		out.errors.append(declared.error)

	if fetcher == null:
		var cache = RepoCache.new()
		fetcher = PackageFetcher.new(cache, ReleaseCache.new(cache.root))
	if dev_repos == null:
		dev_repos = DepResolver.scan_dev_repos()
	var resolver = DepResolver.new(fetcher)
	var seen = {}
	for req in declared.requires:
		var dep = req.dep
		var key = "compile" if req.compile else ("test" if req.test else "build")
		var spec = _spec(dep)
		if seen.has(spec):
			continue # @require in both build_require and test_require
		seen[spec] = true
		var row = {"spec": spec, "key": key, "tag": "", "ok": false, "reason": "", "note": ""}
		if dep.tag == "":
			row.reason = "no tag"
		else:
			row.tag = resolver.find_tag(dep)
			row.ok = row.tag != ""
			if not row.ok:
				var err = fetcher.get("last_error")
				row.reason = err if err is String and err != "" else "not found"
		var checkout = dev_repos.get(dep.repo_id, "")
		if checkout != "" and dep.tag != "":
			var version = str(DepResolver.PackageCfg.dir_value(checkout, "version", ""))
			if version != "" and DepResolver.compare_tags("v" + version.trim_prefix("v"), dep.tag) > 0:
				row.note = "checkout is at v" + version.trim_prefix("v")
		out.rows.append(row)
	return out


static func format(result:Dictionary) -> String:
	var lines:Array[String] = []
	for row in result.rows:
		var state = "ok" if row.ok else "FAIL"
		var line = "%-4s %-7s %s" % [state, row.key, row.spec]
		if not row.ok:
			line += "  - " + row.reason
		if row.note != "":
			line += "  (%s)" % row.note
		lines.append(line)
	if lines.is_empty():
		lines.append("No requires declared.")
	return "\n".join(lines)


static func _spec(dep) -> String:
	var spec = "%s/%s" % [dep.owner, dep.repo]
	if dep.host != DepResolver.DEFAULT_HOST:
		spec = dep.host + "/" + spec
	if dep.kind == DepResolver.KIND_RELEASE:
		spec += "/" + DepResolver.KIND_RELEASE
	spec += ("@" + dep.tag) if dep.tag != "" else ""
	return spec + ((":" + dep.asset) if dep.asset != "" else "")

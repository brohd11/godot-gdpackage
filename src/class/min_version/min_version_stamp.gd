extends RefCounted
## The package cfg's minimum_engine_version, shared by `min_version --update`, `require update
## --min-version` and the export. The scan is a lower bound - it can miss things - so a value already
## stored in any touched package's cfg counts too, and a stored value is only lowered on request.

const VersionScanner = preload("res://addons/gdpackage/src/class/min_version/version_scanner.gd")
const VersionApi = preload("res://addons/gdpackage/src/class/min_version/version_api.gd")
const PackageCfg = preload("uid://ddo8w07hts45v") #! resolve GDPackageSpec.Cfg

const KEY = "minimum_engine_version"
const LEGACY_KEY = "minimum_version" # what exports wrote before the rename


## {has_index, version, scanned, findings, stored: {dir: version}, via}. `version` is the max of
## the scan and the stored values of `package_dirs`, `via` the dir that set it ("" when the scan
## did). Leave the target itself out - its own value goes through decide().
static func compute(files:Array, package_dirs:Array) -> Dictionary:
	var out = {"has_index": false, "version": "", "scanned": "", "findings": [], "stored": {}, "via": ""}
	var scanner = VersionScanner.new()
	if not scanner.api.has_index():
		return out
	var scan = scanner.scan_files(files)
	out.has_index = true
	out.scanned = scan.min_version
	out.findings = scan.findings
	out.merge(fold_stored(scan.min_version, package_dirs), true)
	return out


## {version, stored: {dir: version}, via}: `version` raised to the highest stored value among
## `package_dirs`, `via` the dir that raised it ("" when none did).
static func fold_stored(version:String, package_dirs:Array) -> Dictionary:
	var out = {"version": version, "stored": {}, "via": ""}
	for dir in package_dirs:
		var v = stored_value(dir)
		if v == "" or out.stored.has(dir):
			continue
		out.stored[dir] = v
		if VersionApi.version_code(v) > VersionApi.version_code(out.version):
			out.version = v
			out.via = dir
	return out


## Computes and writes `target`'s cfg value. {ok, changed, line, error, result}; `line` is the
## describe() status. `package_dirs` may include `target` - it is dropped here.
static func stamp(target:String, files:Array, package_dirs:Array, allow_lower:bool = false) -> Dictionary:
	var out = {"ok": false, "changed": false, "line": "", "error": "", "result": {}}
	var path = PackageCfg.find(target)
	if path == "":
		out.error = "%s has no package cfg (%s)" % [target, "/".join(PackageCfg.NAMES)]
		return out
	var result = compute(files, package_dirs.filter(func(d): return d != target and d != ""))
	out.result = result
	if not result.has_index:
		out.error = "no min_version API index (extension_api/api_min_version.json), %s not written" % KEY
		return out
	var stored = stored_value(target)
	var decision = decide(stored, result.version, allow_lower)
	out.ok = true
	out.line = describe(stored, result, decision)
	if not decision.write:
		return out
	var text = FileAccess.get_file_as_string(path)
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		out.ok = false
		out.error = "could not write " + path
		return out
	file.store_string(set_in_text(text, decision.value))
	out.changed = true
	return out


## `dir`'s stored minimum_engine_version, "" when it has none.
static func stored_value(dir:String) -> String:
	if dir == "":
		return ""
	return str(PackageCfg.dir_value(dir, KEY, ""))


## {value, write, kept}: what to store over `stored`. A lower `computed` keeps `stored` (`kept`)
## unless `allow_lower`; an unparseable computed value never replaces anything.
static func decide(stored:String, computed:String, allow_lower:bool = false) -> Dictionary:
	var s = VersionApi.version_code(stored)
	var c = VersionApi.version_code(computed)
	if c == -1 or c == s:
		return {"value": stored, "write": false, "kept": false}
	if c < s and not allow_lower:
		return {"value": stored, "write": false, "kept": true}
	return {"value": computed, "write": true, "kept": false}


## `text` with the key set to `version` and any legacy key dropped.
static func set_in_text(text:String, version:String) -> String:
	return PackageCfg.set_value(PackageCfg.remove_value(text, LEGACY_KEY), KEY, version)


## Nearest ancestor dir holding a package cfg, never above `root`; "" when none does. Memoized
## per dir in `cache` - a crawl asks about the same few dirs hundreds of times.
static func package_dir(path:String, cache:Dictionary, root:String = "res://") -> String:
	var dir = path.get_base_dir()
	var walked = []
	var found = ""
	root = root.trim_suffix("/")
	while dir == root or dir.begins_with(root + "/"):
		if cache.has(dir):
			found = cache[dir]
			break
		walked.append(dir)
		if PackageCfg.has_cfg(dir):
			found = dir
			break
		var parent = dir.get_base_dir()
		if parent == dir or dir.trim_suffix("/") == root:
			break
		dir = parent
	for w in walked:
		cache[w] = found
	return found


## Distinct package dirs owning `files`, in first-seen order.
static func package_dirs_for(files:Array, cache = null, root:String = "res://") -> Array:
	if cache == null:
		cache = {}
	var seen = {}
	for f in files:
		var dir = package_dir(f, cache, root)
		if dir != "":
			seen[dir] = true
	return seen.keys()


## One status line: "4.3 -> 4.4 (via res://…)", "kept 4.5 (computed 4.4)" or "up to date (4.4)".
static func describe(stored:String, result:Dictionary, decision:Dictionary) -> String:
	if decision.kept:
		return "%s kept %s (computed %s)" % [KEY, stored, result.version]
	var via = " (via %s)" % result.via if result.via != "" else ""
	if decision.write:
		return "%s %s -> %s%s" % [KEY, stored if stored != "" else "unset", decision.value, via]
	return "%s up to date (%s)" % [KEY, stored]

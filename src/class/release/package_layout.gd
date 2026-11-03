@tool
extends RefCounted
## Where a fetched package's addon sits and where it installs - a port of gdaddon's resolveInstall
## (internal/addon/resolve.go), so both tools place a package the same way. Pure: it works on the
## package's relative file list plus a cfg reader, so git trees and extracted zips share it.
## Differs from gdaddon in two deliberate ways: a root cfg without path= fails instead of defaulting
## to addons/<name>, and a bundle yields only the folder whose url= names the repo.

const PackageCfg = preload("uid://ddo8w07hts45v") #! resolve GDPackageSpec.Cfg
const CFG_NAMES = PackageCfg.NAMES
const JUNK_FILES = [".DS_Store", "Thumbs.db", "desktop.ini", "ehthumbs.db"]


## Archive noise gdaddon's unzip drops too.
static func is_junk(rel_path:String) -> bool:
	return rel_path.begins_with("__MACOSX/") or rel_path.get_file() in JUNK_FILES


## {src, dest} for the dep's addon, or {error}. `files` are paths relative to the package root (a
## tag's tree or an extracted zip) and `src` is relative to that same root, wrapper included.
## `cfg_value.call(dir, key)` reads a package key from the cfg in `dir`; `repo_id_of.call(url)`
## normalizes a url= for comparison with `repo_id`. `root_default` (a res:// dir) stands in for a
## missing path= on a root cfg - only the export target passes one, since its dir is already known.
static func locate(files:Array, repo_id:String, cfg_value:Callable, repo_id_of:Callable, root_default:String = "") -> Dictionary:
	var clean:Array[String] = []
	for f in files:
		var path = String(f).trim_prefix("./")
		if path != "" and not path.ends_with("/") and not is_junk(path):
			clean.append(path)
	if clean.is_empty():
		return {"error": "the package is empty"}

	# A release zip usually wraps everything in one folder; gdaddon's staging does the same strip.
	var wrapper = _single_wrapper(clean)
	if wrapper != "":
		for i in clean.size():
			clean[i] = clean[i].trim_prefix(wrapper + "/")

	var cfg_dirs = {}
	for f in clean:
		if f.get_file() in CFG_NAMES:
			cfg_dirs[f.get_base_dir()] = true
	var unwrap = func(dir:String) -> String:
		return wrapper if dir == "" else (wrapper.path_join(dir) if wrapper != "" else dir)

	# 1. Submodule style: the package root is the addon, and only its own cfg can say where it goes.
	if cfg_dirs.has(""):
		var pinned = _override(unwrap.call(""), cfg_value)
		if pinned == "" and root_default != "":
			return {"src": wrapper, "dest": _res(root_default)}
		if pinned == "":
			return {"error": "cfg at the package root but no path= (or dir=); add path=\"addons/...\" to it"}
		return {"src": wrapper, "dest": _res(pinned)}

	# 2. An addons/ folder is the canonical layout: its children are the addons, descending into a
	# child that is only a namespace level (addons/_lib/<addon>).
	var base = _shallowest_addons(clean)
	var candidates:Array[String] = []
	if base != "":
		for child in _child_dirs(clean, base):
			var child_dir = base.path_join(child)
			if cfg_dirs.has(child_dir):
				candidates.append(child_dir)
				continue
			var nested = _top_cfg_dirs(cfg_dirs, child_dir)
			if nested.is_empty():
				candidates.append(child_dir) # a folder with no cfg at all, e.g. an icon pack
			else:
				candidates.append_array(nested)

	# 3. Otherwise the package root stands in for addons/.
	if candidates.is_empty():
		base = ""
		candidates = _top_cfg_dirs(cfg_dirs, "")
	if candidates.is_empty():
		return {"error": "no %s anywhere in the package" % "/".join(CFG_NAMES)}

	var with_cfg = candidates.filter(func(c): return cfg_dirs.has(c))
	var matching = with_cfg.filter(func(c):
		return repo_id != "" and repo_id_of.call(cfg_value.call(unwrap.call(c), "url")) == repo_id)
	var chosen = ""
	if matching.size() == 1:
		chosen = matching[0]
	elif matching.size() > 1:
		return {"error": "several folders have url= naming %s: %s" % [repo_id, ", ".join(matching)]}
	elif with_cfg.size() == 1:
		chosen = with_cfg[0]
	elif with_cfg.is_empty() and candidates.size() == 1:
		chosen = candidates[0]
	else:
		return {"error": "several addon folders and none has url= naming %s: %s" % [repo_id, ", ".join(candidates)]}

	var dest = _override(unwrap.call(chosen), cfg_value) if cfg_dirs.has(chosen) else ""
	if dest == "":
		dest = "addons".path_join(chosen.trim_prefix(base + "/") if base != "" else chosen)
	return {"src": unwrap.call(chosen), "dest": _res(dest)}


## The one top-level folder everything sits in, or "" when there are root files or several folders.
static func _single_wrapper(files:Array[String]) -> String:
	var top = ""
	for f in files:
		if not "/" in f:
			return ""
		var seg = f.get_slice("/", 0)
		if top == "":
			top = seg
		elif seg != top:
			return ""
	return top


## Shallowest dir named addons that some file sits under; ties go to the alphabetically first.
static func _shallowest_addons(files:Array[String]) -> String:
	var best = ""
	var best_depth = -1
	for f in files:
		var segs = f.split("/")
		for i in segs.size() - 1: # the last segment is the file name
			if segs[i] != "addons":
				continue
			var path = "/".join(segs.slice(0, i + 1))
			if best == "" or i < best_depth or (i == best_depth and path < best):
				best = path
				best_depth = i
			break
	return best


static func _child_dirs(files:Array[String], dir:String) -> Array[String]:
	var seen = {}
	for f in files:
		if not f.begins_with(dir + "/"):
			continue
		var rest = f.trim_prefix(dir + "/")
		if "/" in rest:
			seen[rest.get_slice("/", 0)] = true
	var out:Array[String] = []
	out.assign(seen.keys())
	out.sort()
	return out


## Cfg dirs under `under` (or anywhere, for "") that don't sit inside another cfg dir there.
static func _top_cfg_dirs(cfg_dirs:Dictionary, under:String) -> Array[String]:
	var inside:Array[String] = []
	for d in cfg_dirs:
		if d != "" and d != under and (under == "" or d.begins_with(under + "/")):
			inside.append(d)
	var out:Array[String] = []
	for d in inside:
		if not inside.any(func(o): return o != d and d.begins_with(o + "/")):
			out.append(d)
	out.sort()
	return out


## A cfg's dir= (gdaddon's key) or path=, when it is a relative path inside the project.
static func _override(dir:String, cfg_value:Callable) -> String:
	for key in ["dir", "path"]:
		var value = String(cfg_value.call(dir, key)).strip_edges().trim_prefix("res://")
		if value != "" and not value.begins_with("/") and not ".." in value.split("/"):
			return value.trim_suffix("/")
	return ""


static func _res(path:String) -> String:
	return "res://" + path.trim_prefix("res://").trim_prefix("/").trim_suffix("/")

@tool
extends RefCounted
## GitHub releases as dependencies, picked the way gdaddon's source.AutoAsset does: a release with
## exactly one uploaded asset installs that asset; a tag with no release, or a release with nothing
## uploaded, installs the tag's source instead (lookup answers "none"); several uploads are
## ambiguous. Assets are cached per tag and trusted as immutable; `refresh` re-downloads and fails
## if an asset changed upstream.

const DepResolver = preload("res://addons/gdpackage/src/class/release/dep_resolver.gd")
const ReleaseRunner = preload("res://addons/gdpackage/src/class/release/release_runner.gd")

const API_URL = "https://api.github.com/repos/%s/releases/tags/%s"
const NO_RELEASE_MARKER = ".no_release"
## A missing release can appear once one is published, so unlike assets it is only trusted a while.
const NO_RELEASE_TTL_SEC = 3600

var root:String
var refresh:bool
var last_error:String = ""


func _init(cache_root:String = "", refresh_assets:bool = false) -> void:
	root = cache_root if cache_root != "" else OS.get_cache_dir().path_join("gdpackage")
	refresh = refresh_assets


## Checksum and signature files published beside an asset; never the asset itself.
const SIDECAR_EXTENSIONS = ["sha256", "sha512", "sha1", "md5", "sig", "asc", "minisig"]


## The asset to install from GitHub release JSON: {name, url} for the single upload, {} when there
## are none (install the source), or {error} when several uploads leave no automatic choice.
## Sidecars (SIDECAR_EXTENSIONS) don't count, so a zip with its .sha256 is still a single upload.
## `pattern` (a spec's `:<asset>` glob) narrows the uploads to the one it must match.
static func auto_asset(release:Dictionary, pattern:String = "") -> Dictionary:
	var uploads:Array = release.get("assets", []).filter(func(a):
		return not str(a.get("name", "")).get_extension().to_lower() in SIDECAR_EXTENSIONS)
	var names = uploads.map(func(a): return str(a.get("name", "")))
	var tag = release.get("tag_name", "?")
	if pattern != "":
		var matched = uploads.filter(func(a): return str(a.get("name", "")).match(pattern))
		if matched.size() == 1:
			return {"name": str(matched[0].get("name", "")), "url": str(matched[0].get("browser_download_url", ""))}
		if matched.is_empty():
			return {"error": "release %s has no asset matching '%s' (%s)" % [tag, pattern, ", ".join(names) if not names.is_empty() else "no uploads"]}
		return {"error": "'%s' matches %d assets of release %s (%s); narrow the pattern" % [
			pattern, matched.size(), tag, ", ".join(matched.map(func(a): return str(a.get("name", ""))))]}
	if uploads.size() == 1:
		return {"name": str(uploads[0].get("name", "")), "url": str(uploads[0].get("browser_download_url", ""))}
	if uploads.is_empty():
		return {}
	return {"error": "release %s has %d uploaded assets (%s), so there is no automatic pick; pin one with /release@%s:<asset glob>, or drop /release to build from source" % [
		tag, uploads.size(), ", ".join(names), tag]}


func release_dir(repo_url:String, tag:String) -> String:
	return root.path_join("releases").path_join(DepResolver.repo_id_from_url(repo_url)).path_join(tag.validate_filename())


## {state: "asset", asset, sha} when the tag's release has one uploaded asset (or one matching
## `pattern`), {state: "none"} when the source should be used instead, or {state: "error"} with
## last_error set.
func lookup(repo_url:String, tag:String, pattern:String = "") -> Dictionary:
	var id = DepResolver.repo_id_from_url(repo_url)
	if not id.begins_with("github.com/"):
		return {"state": "none"} # no release API to ask; gdaddon falls back to source here too
	var dir = release_dir(repo_url, tag)
	var json_path = dir.path_join("release.json")
	if refresh or not FileAccess.file_exists(json_path):
		if not refresh and _recent_no_release(dir):
			return {"state": "none"}
		var fetched = _fetch_release(id.trim_prefix("github.com/"), tag, json_path)
		if fetched == "none":
			_write(dir.path_join(NO_RELEASE_MARKER), str(int(Time.get_unix_time_from_system())))
			return {"state": "none"}
		if fetched == "error":
			return {"state": "error"}

	var release = JSON.parse_string(FileAccess.get_file_as_string(json_path))
	if not release is Dictionary:
		last_error = "unreadable release data at " + json_path
		return {"state": "error"}
	var pick = auto_asset(release, pattern)
	if pick.is_empty():
		return {"state": "none"}
	if pick.has("error"):
		last_error = pick.error
		return {"state": "error"}

	var asset_path = dir.path_join(pick.name)
	if refresh or not FileAccess.file_exists(asset_path):
		var previous = FileAccess.get_sha256(asset_path) if FileAccess.file_exists(asset_path) else ""
		var part = asset_path + ".part"
		if not _curl(["-fsSL", "-o", part, pick.url]):
			DirAccess.remove_absolute(part)
			last_error = "download of %s failed" % pick.url
			return {"state": "error"}
		var got = FileAccess.get_sha256(part)
		if previous != "" and previous != got:
			DirAccess.remove_absolute(part)
			last_error = "release asset %s of %s %s changed upstream" % [pick.name, id, tag]
			return {"state": "error"}
		DirAccess.remove_absolute(asset_path)
		DirAccess.rename_absolute(part, asset_path)
		ReleaseRunner.remove_dir(dir.path_join("staging"))
		DirAccess.remove_absolute(dir.path_join("staging.done"))
	return {"state": "asset", "asset": pick.name, "sha": FileAccess.get_sha256(asset_path)}


## The asset extracted once under the release's cache dir; "" with last_error on failure.
func stage(repo_url:String, tag:String, asset:String) -> String:
	var dir = release_dir(repo_url, tag)
	var staging = dir.path_join("staging")
	var done = dir.path_join("staging.done") # beside the tree, so it never lands in an addon
	if FileAccess.file_exists(done):
		return staging
	var zip_path = dir.path_join(asset)
	if not FileAccess.file_exists(zip_path):
		last_error = "release asset %s is not in the cache" % zip_path
		return ""
	ReleaseRunner.remove_dir(staging)
	var err = ReleaseRunner.unzip(zip_path, staging)
	if err != "":
		last_error = "%s: %s" % [asset, err]
		return ""
	_write(done, asset)
	return staging


## Every file in the extracted asset, relative to its root.
func files(repo_url:String, tag:String, asset:String) -> Array:
	var staging = stage(repo_url, tag, asset)
	if staging == "":
		return []
	var out = []
	_walk(staging, "", out)
	return out


## "ok", "none" for a 404, or "error" with last_error set.
func _fetch_release(owner_repo:String, tag:String, json_path:String) -> String:
	DirAccess.make_dir_recursive_absolute(json_path.get_base_dir())
	var args = ["-sS", "-L", "-o", json_path, "-w", "%{http_code}", "-H", "Accept: application/vnd.github+json"]
	var token = OS.get_environment("GITHUB_TOKEN")
	if token != "":
		args.append_array(["-H", "Authorization: Bearer " + token])
	args.append(API_URL % [owner_repo, tag.uri_encode()])
	var output = []
	var code = OS.execute("curl", args, output, true)
	var status = "".join(output).strip_edges().right(3)
	if code == 0 and status == "200":
		DirAccess.remove_absolute(json_path.get_base_dir().path_join(NO_RELEASE_MARKER))
		return "ok"
	DirAccess.remove_absolute(json_path)
	if code == 0 and status == "404":
		return "none"
	last_error = "GitHub release lookup for %s %s failed (%s)%s" % [owner_repo, tag,
		("HTTP " + status) if code == 0 else "curl exit %d" % code,
		"; set GITHUB_TOKEN to raise the API rate limit" if status in ["403", "429"] else ""]
	return "error"


func _recent_no_release(dir:String) -> bool:
	var marker = dir.path_join(NO_RELEASE_MARKER)
	if not FileAccess.file_exists(marker):
		return false
	var at = FileAccess.get_file_as_string(marker).strip_edges().to_int()
	return Time.get_unix_time_from_system() - at < NO_RELEASE_TTL_SEC


static func _curl(args:Array) -> bool:
	var output = []
	return OS.execute("curl", args, output, true) == 0


static func _write(path:String, text:String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(text)
		file.close()


static func _walk(base:String, rel:String, out:Array) -> void:
	var dir = DirAccess.open(base.path_join(rel) if rel != "" else base)
	if dir == null:
		return
	dir.include_hidden = true
	for f in dir.get_files():
		out.append(rel.path_join(f) if rel != "" else f)
	for d in dir.get_directories():
		_walk(base, rel.path_join(d) if rel != "" else d, out)

@tool
extends RefCounted
## Bare git mirrors of release dependencies, kept under the OS cache dir. A tag already in a mirror
## is trusted without touching the network (tags are treated as immutable, as in Go's module
## cache); `refresh` compares every cached tag against the remote first and fails if one moved.
## This is DepResolver's fetcher: tag_sha / read_file / extract.

const DepResolver = preload("res://addons/gdpackage/src/class/release/dep_resolver.gd")
const ReleaseRunner = preload("res://addons/gdpackage/src/class/release/release_runner.gd")

var root:String
var refresh:bool
var last_error:String = ""
## Urls of checkouts in this project (--local). Their tags get re-pointed while iterating, so they
## are force-fetched once per run instead of trusted or checked for moves.
var local_urls:Dictionary = {}

var _synced:Dictionary = {} # mirror path -> true once cloned or fetched this run


func _init(cache_root:String = "", refresh_tags:bool = false) -> void:
	root = cache_root if cache_root != "" else default_root()
	refresh = refresh_tags


static func default_root() -> String:
	return OS.get_cache_dir().path_join("gdpackage")


## A file:// url is keyed by its full path's hash: its repo id only keeps the last two segments,
## which two different checkouts can share.
func mirror_path(url:String) -> String:
	var key = DepResolver.repo_id_from_url(url)
	if url.begins_with("file://"):
		var path = url.trim_prefix("file://").rstrip("/")
		key = "local/%s-%s" % [path.get_file().trim_suffix(".git").to_lower(), path.sha1_text().substr(0, 8)]
	return root.path_join("repos").path_join(key + ".git")


## Commit a tag points at, or "" when it doesn't exist even after one fetch.
func tag_sha(url:String, tag:String) -> String:
	var mirror = _ensure_mirror(url)
	if mirror == "":
		return ""
	if local_urls.has(url) and not _synced.has(mirror):
		if not _fetch(mirror, true):
			return ""
	elif refresh and not _synced.has(mirror):
		if not _verify_tags_unmoved(mirror) or not _fetch(mirror):
			return ""
	var sha = _rev(mirror, tag)
	if sha == "" and not _synced.has(mirror):
		if _fetch(mirror):
			sha = _rev(mirror, tag)
	return sha


## File contents at a tag, or null when the path isn't in that commit.
func read_file(url:String, tag:String, path:String):
	var mirror = _ensure_mirror(url)
	if mirror == "":
		return null
	var res = _git(["--git-dir=" + mirror, "show", "%s:%s" % [tag, path]])
	return res.output if res.exit == 0 else null


## Every file path in the tree at `tag`, so the addon can be located without extracting anything.
func list_files(url:String, tag:String) -> Array:
	var mirror = _ensure_mirror(url)
	if mirror == "":
		return []
	var res = _git(["--git-dir=" + mirror, "ls-tree", "-r", "--name-only", tag])
	return Array(res.output.split("\n", false)) if res.exit == 0 else []


## The tree at `tag` extracted once under <cache>/staging, keyed by commit and reused by later
## workspaces. The marker sits beside the tree so it never ends up inside an addon.
func stage(url:String, tag:String) -> String:
	var sha = tag_sha(url, tag)
	if sha == "":
		return ""
	var key = "%s-%s" % [mirror_path(url).get_file().trim_suffix(".git"), url.sha1_text().substr(0, 8)]
	var dir = root.path_join("staging").path_join(key).path_join(sha)
	var marker = dir + ".staged"
	if FileAccess.file_exists(marker):
		return dir
	if DirAccess.dir_exists_absolute(dir):
		ReleaseRunner.remove_dir(dir)
	if not extract(url, tag, dir):
		return ""
	FileAccess.open(marker, FileAccess.WRITE).close()
	return dir


## Writes the tree at `tag` into dest_dir. Goes through a zip so the mirror is never given a
## work tree or index, which keeps concurrent exports off each other's toes.
func extract(url:String, tag:String, dest_dir:String) -> bool:
	var mirror = _ensure_mirror(url)
	if mirror == "":
		return false
	var zip_path = root.path_join("tmp").path_join("%s-%d.zip" % [tag.validate_filename(), Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(zip_path.get_base_dir())
	var res = _git(["--git-dir=" + mirror, "archive", "--format=zip", "-o", zip_path, tag], true)
	if res.exit != 0:
		last_error = "git archive %s failed: %s" % [tag, res.output.strip_edges()]
		return false

	var err = ReleaseRunner.unzip(zip_path, dest_dir)
	DirAccess.remove_absolute(zip_path)
	if err != "":
		last_error = err
	return err == ""


func _ensure_mirror(url:String) -> String:
	var mirror = mirror_path(url)
	if DirAccess.dir_exists_absolute(mirror):
		return mirror
	DirAccess.make_dir_recursive_absolute(mirror.get_base_dir())
	var res = _git(["clone", "--bare", "--quiet", url, mirror], true)
	if res.exit != 0:
		last_error = "clone %s failed: %s" % [url, res.output.strip_edges()]
		return ""
	_synced[mirror] = true
	return mirror


func _fetch(mirror:String, force_tags:bool = false) -> bool:
	_synced[mirror] = true
	var args = ["--git-dir=" + mirror, "fetch", "--quiet", "--tags", "origin"]
	if force_tags:
		args.insert(3, "--force")
	var res = _git(args, true)
	if res.exit != 0:
		last_error = "fetch failed for %s: %s" % [mirror, res.output.strip_edges()]
		return false
	return true


## The go.sum check: a tag re-pointed upstream would otherwise go unnoticed, since plain
## `fetch --tags` refuses to clobber it and the stale commit keeps getting exported.
func _verify_tags_unmoved(mirror:String) -> bool:
	var local = _peeled_tags(_git(["--git-dir=" + mirror, "show-ref", "--tags", "-d"]).output)
	var remote_res = _git(["--git-dir=" + mirror, "ls-remote", "--tags", "origin"], true)
	if remote_res.exit != 0:
		last_error = "ls-remote failed for %s: %s" % [mirror, remote_res.output.strip_edges()]
		return false
	var remote = _peeled_tags(remote_res.output)
	for tag in local:
		if remote.has(tag) and remote[tag] != local[tag]:
			last_error = "tag %s moved upstream (%s -> %s) in %s" % [tag, local[tag], remote[tag], mirror]
			return false
	return true


## "<sha> refs/tags/<name>[^{}]" lines -> {name: commit sha}; a peeled ^{} line wins, since an
## annotated tag's own line carries the tag object's sha rather than the commit's.
static func _peeled_tags(text:String) -> Dictionary:
	var tags = {}
	for line in text.split("\n", false):
		var parts = line.strip_edges().split("\t") if "\t" in line else line.strip_edges().split(" ")
		if parts.size() < 2 or not parts[1].begins_with("refs/tags/"):
			continue
		var name = parts[1].trim_prefix("refs/tags/")
		if name.ends_with("^{}"):
			tags[name.trim_suffix("^{}")] = parts[0]
		elif not tags.has(name):
			tags[name] = parts[0]
	return tags


func _rev(mirror:String, tag:String) -> String:
	var res = _git(["--git-dir=" + mirror, "rev-parse", "-q", "--verify", tag + "^{commit}"])
	return res.output.strip_edges() if res.exit == 0 else ""


static func _git(args:Array, read_stderr:bool = false) -> Dictionary:
	# OS.execute blocks the editor: a credential prompt nobody can answer would hang it for good.
	OS.set_environment("GIT_TERMINAL_PROMPT", "0")
	var output = []
	var code = OS.execute("git", args, output, read_stderr)
	return {"exit": code, "output": "".join(output)}

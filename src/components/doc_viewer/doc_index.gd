## Locates a plugin's docs and orders them for the viewer.
##
## The order is a depth-first walk with files before directories, which reads as a table of
## contents without needing a tree structure - one flat Array drives both the contents page and
## prev/next. Engine-only, no dependencies.

const Parser = preload("res://addons/gdpackage/src/components/doc_viewer/markdown_parser.gd")

## Packaged docs. Dot-prefixed by the exporter so Godot never imports them.
const DOC_DIR_NAME = ".doc"
## Where the docs live before they are packaged, so the viewer works in a dev project too. Both
## spellings of the dev-only folder are accepted; the first that exists wins.
const SOURCE_DOC_DIRS = ["_export_ignore/doc", "export_ignore/doc"]

const KEY_PATH = "path"
const KEY_REL = "rel"
const KEY_DEPTH = "depth"
const KEY_TITLE = "title"

## How far into a file to look for its title before giving up on it having one.
const _TITLE_SCAN_LINES = 60


## Resolves [param path] to a doc directory. Accepts an addon dir (packaged or dev layout) or a
## doc dir directly. Empty string when there is nothing to show.
static func find_doc_dir(path:String) -> String:
	path = path.trim_suffix("/")
	if path == "" or not DirAccess.dir_exists_absolute(path):
		return ""
	var candidates = [path.path_join(DOC_DIR_NAME)]
	for source_dir in SOURCE_DOC_DIRS:
		candidates.append(path.path_join(source_dir))
	for candidate in candidates:
		if DirAccess.dir_exists_absolute(candidate):
			return candidate
	# A caller can also point straight at a doc folder. An addon root is never one, however many
	# .md files sit in it - its readme is a fallback, not a table of contents.
	if not FileAccess.file_exists(path.path_join("plugin.cfg")) and _has_doc(path):
		return path
	return ""


## Ordered doc entries under [param doc_dir], each {path, rel, depth, title}.
static func scan(doc_dir:String) -> Array:
	var docs:Array = []
	_scan_dir(doc_dir.trim_suffix("/"), doc_dir.trim_suffix("/"), docs)
	return docs


## The README a plugin falls back to when it ships no docs, or an empty string.
static func find_readme(addon_dir:String) -> String:
	var dir = DirAccess.open(addon_dir)
	if dir == null:
		return ""
	for file in dir.get_files():
		if file.get_basename().to_lower() != "readme":
			continue
		var extension = file.get_extension().to_lower()
		if extension == "md" or extension == "":
			return addon_dir.trim_suffix("/").path_join(file)
	return ""


## A single-entry index for one file, used for the README fallback.
static func single(path:String) -> Array:
	return [{KEY_PATH:path, KEY_REL:path.get_file(), KEY_DEPTH:0, KEY_TITLE:title_for(path)}]


## First heading in the doc, else its filename made readable.
static func title_for(path:String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	if file != null:
		var scanned := 0
		var in_fence := false
		while not file.eof_reached() and scanned < _TITLE_SCAN_LINES:
			var line = file.get_line()
			scanned += 1
			# A "#" comment inside a code fence is not the doc's title.
			if line.strip_edges().begins_with("```"):
				in_fence = not in_fence
				continue
			if in_fence:
				continue
			var heading = Parser.first_heading(line)
			if heading != "":
				return heading
	return path.get_file().get_basename().replace("-", " ").capitalize()


static func _has_doc(dir:String) -> bool:
	var dir_access = DirAccess.open(dir)
	if dir_access == null:
		return false
	for file in dir_access.get_files():
		if file.get_extension().to_lower() == "md":
			return true
	return false


static func _scan_dir(dir:String, root:String, docs:Array) -> void:
	var dir_access = DirAccess.open(dir)
	if dir_access == null:
		return

	var files = Array(dir_access.get_files())
	files.sort_custom(_compare_no_case)
	for file in files:
		if file.get_extension().to_lower() != "md":
			continue
		var path = dir.path_join(file)
		var rel = path.trim_prefix(root).trim_prefix("/")
		docs.append({KEY_PATH:path, KEY_REL:rel, KEY_DEPTH:rel.count("/"), KEY_TITLE:title_for(path)})

	var dirs = Array(dir_access.get_directories())
	dirs.sort_custom(_compare_no_case)
	for sub_dir in dirs:
		if sub_dir.begins_with("."):
			continue
		_scan_dir(dir.path_join(sub_dir), root, docs)


static func _compare_no_case(a:String, b:String) -> bool:
	return a.to_lower() < b.to_lower()

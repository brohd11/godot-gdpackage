@tool
extends RefCounted
## Writes what the crawl found into a package's own require list, in place: the cfg's require= by
## default (build_require and test_require default to it), or the export config's build_require.
## A tag comes from the required package's cfg version=, checked against its checkout's tags - a
## version nobody tagged yet is a warning, since tagging comes after the update. In build_require a
## "@require" is dropped rather than expanded: writing there means an explicit list.
## Only DepResolver is imported - reaching for the export pipeline here would break headless callers.

const DepResolver = preload("res://addons/gdpackage/src/class/release/dep_resolver.gd")

const KEY = DepResolver.BUILD_KEY
const CFG_NAMES = DepResolver.CFG_NAMES
const REQUIRE_REF = DepResolver.REQUIRE_REF


## {specs: [{id, dir, tag, spec, refs}], warnings, errors} for the target package's own rows, sorted
## by id.
## A spec carries "@tag" only when the tag resolved, so it stays printable while `errors` says
## nothing may be written.
static func resolve_target(report:Dictionary) -> Dictionary:
	var out = {"specs": [], "warnings": [], "errors": []}
	var target = report.get("target", "")
	if target == "":
		out.errors.append("%s has no package cfg (%s)" % [report.get("plugin_name", ""), "/".join(CFG_NAMES)])
		return out
	for row in report.get("groups", {}).get(target, {}).get("rows", []):
		if row.id == "":
			out.errors.append("%s has no git origin and no url= in its cfg" % row.dir)
			continue
		var short = short_id(row.id)
		var version = cfg_value(row.dir, "version")
		if version == "" or DepResolver.version_parts(version).is_empty():
			out.errors.append("%s: cfg version=\"%s\" is nothing to pin a tag to" % [row.dir, version])
			out.specs.append({"id": row.id, "dir": row.dir, "tag": "", "spec": short, "refs": row.get("refs", [])})
			continue
		var tag = "v" + version.trim_prefix("v").trim_prefix("V")
		if row.via != "git":
			out.warnings.append("%s is no checkout, %s comes from its cfg version= unverified" % [row.dir, tag])
		elif not DepResolver.local_tag_exists(row.dir, tag):
			out.warnings.append("%s is not tagged %s yet - a release export will fail on it" % [row.dir, tag])
		out.specs.append({"id": row.id, "dir": row.dir, "tag": tag, "spec": "%s@%s" % [short, tag], "refs": row.get("refs", [])})
	out.specs.sort_custom(func(a, b): return a.id < b.id)
	return out


## One line per reference: where it is (relative to `from_dir`, the referencing package), its kind,
## the text as written - what to search for - and the file it lands on, relative to `to_dir`.
static func ref_lines(refs:Array, from_dir:String, to_dir:String, indent:String) -> Array[String]:
	var out:Array[String] = []
	for r in refs:
		var where = _relative(r.from, from_dir)
		if r.line > 0:
			where += ":%d" % r.line
		out.append("%s%s  %s  %s  -> %s" % [indent, where, r.kind, r.raw, _relative(r.to, to_dir)])
	return out


static func _relative(path:String, dir:String) -> String:
	if dir == "" or not path.begins_with(dir.trim_suffix("/") + "/"):
		return path
	return path.trim_prefix(dir.trim_suffix("/") + "/")


## Just the target's specs, one per line, for piping. An unresolvable tag prints bare rather than
## stopping the listing - nothing is written here. `verbose` follows each with where it's referenced.
static func self_list(report:Dictionary, verbose:bool = false) -> Array:
	var out = []
	for s in resolve_target(report).specs:
		out.append(s.spec)
		if verbose:
			out.append_array(ref_lines(s.refs, report.get("target", ""), s.dir, "    "))
	return out


## {path, changed, added, repinned, kept, pruned, warnings, errors}. Writes the target's cfg
## require=, or with `export_config` its export config's build_require. `overwrite` re-pins entries
## already listed, `prune` drops the ones the crawl did not find. Nothing is written when `errors`
## is filled - a half-pinned list is worse than none.
static func apply(report:Dictionary, overwrite:bool, prune:bool, export_config:bool = false) -> Dictionary:
	var config_path = report.get("config_path", "")
	var path = config_path if export_config else DepResolver.PackageCfg.find(report.get("target", ""))
	var result = {"path": path, "changed": false, "added": [], "repinned": [],
		"kept": [], "pruned": [], "warnings": [], "errors": []}
	var resolved = resolve_target(report)
	result.warnings = resolved.warnings
	if not resolved.errors.is_empty():
		result.errors = resolved.errors
		return result
	if path == "" or not FileAccess.file_exists(path):
		result.errors.append(("no export config at " + config_path) if export_config else
			"%s has no package cfg (%s)" % [report.get("target", ""), "/".join(CFG_NAMES)])
		return result
	var text = FileAccess.get_file_as_string(path)
	var ext = String(path).get_extension()
	if not export_config and FileAccess.file_exists(config_path):
		var config_text = FileAccess.get_file_as_string(config_path)
		if bypasses_cfg(config_text, config_path.get_extension()):
			result.warnings.append("%s lists build_require without %s, so builds won't read the cfg list written here; use --export-config, or put %s in it" % [
				config_path, REQUIRE_REF, REQUIRE_REF])

	var needed = {} # repo_id -> tag
	for s in resolved.specs:
		needed[s.id] = s.tag
	var compile_declared = {} # already under compile_require, which counts as declared and wins
	for row in report.groups[report.target].rows:
		if row.declared == "compile":
			compile_declared[row.id] = true

	var out:Array = []
	var seen = {}
	for spec in (read_build_require(text, ext) if export_config else DepResolver.cfg_require(text)):
		var dep = DepResolver.parse_dep(spec)
		if dep == null: # not a spec this can judge, so it is left exactly as written
			out.append(spec)
			result.kept.append(spec)
			continue
		if not needed.has(dep.repo_id):
			if prune:
				result.pruned.append(spec)
				continue
			out.append(spec)
			result.kept.append(spec)
			continue
		seen[dep.repo_id] = true
		if dep.tag != "" and not overwrite:
			out.append(spec)
			result.kept.append(spec)
			continue
		var pinned = repin(spec, needed[dep.repo_id])
		out.append(pinned)
		if pinned == spec:
			result.kept.append(spec)
		else:
			result.repinned.append(pinned)
	for s in resolved.specs:
		if seen.has(s.id) or compile_declared.has(s.id):
			continue
		out.append(s.spec)
		result.added.append(s.spec)

	var new_text = text
	if export_config:
		new_text = rewrite(text, ext, out)
	elif out != DepResolver.cfg_require(text): # same list: leave a hand-formatted cfg alone
		new_text = DepResolver.PackageCfg.set_require(text, out, true)
	result.changed = new_text != text
	if result.changed:
		var file = FileAccess.open(result.path, FileAccess.WRITE)
		if file == null:
			result.errors.append("could not write " + result.path)
			return result
		file.store_string(new_text)
	return result


## The spec's own spelling with only its tag replaced, so a leading host, a /source or /release
## marker and a `:<asset>` pin survive a re-pin.
static func repin(spec:String, tag:String) -> String:
	var at = spec.rfind("@")
	var base = spec.substr(0, at) if at >= 0 else spec
	var old_tag = spec.substr(at + 1) if at >= 0 else ""
	var asset = old_tag.substr(old_tag.find(":")) if ":" in old_tag else ""
	return "%s@%s%s" % [base.strip_edges(), tag, asset.strip_edges()]


## How this project and gdaddon spell a github repo in a require list.
static func short_id(repo_id:String) -> String:
	return repo_id.trim_prefix("%s/" % DepResolver.DEFAULT_HOST)


## A package cfg's value, read by hand for the reason PackageCfg.section() gives.
static func cfg_value(dir:String, key:String) -> String:
	var path = DepResolver.PackageCfg.find(dir)
	if path == "":
		return ""
	return DepResolver.unquote(DepResolver.PackageCfg.section(FileAccess.get_file_as_string(path)).get(key, ""))


#region Config text

## Whether the export config lists build_require explicitly without "@require", so the cfg's
## require= takes no part in builds.
static func bypasses_cfg(text:String, ext:String) -> bool:
	var raw = ""
	if ext == "json":
		var at = _locate_json(text)
		if not at.found:
			return false
		raw = text.substr(at.from, at.to - at.from)
	else:
		var lines = text.split("\n")
		var at = _locate_yaml(lines)
		if not at.found:
			return false
		raw = "\n".join(lines.slice(at.from, at.to))
	return not REQUIRE_REF in raw


## The specs the config lists under build_require, exactly as written, "@require" dropped.
static func read_build_require(text:String, ext:String) -> Array:
	if ext == "json":
		return _locate_json(text).specs
	return _locate_yaml(text.split("\n")).specs


## `text` with its top-level build_require replaced by `specs` and nothing else touched - comments,
## key order and the trailing commas some of these configs carry all survive. The key is added when
## the config has none: above `exports:` in yaml, as the first key in json.
static func rewrite(text:String, ext:String, specs:Array) -> String:
	if ext == "json":
		return _rewrite_json(text, specs)
	return _rewrite_yaml(text, specs)


## {found, from, to, specs}: the line range holding the top-level build_require (`to` exclusive).
## Its value may be an inline scalar, an inline flow sequence over one or more lines, or a block of
## "- " items.
static func _locate_yaml(lines:PackedStringArray) -> Dictionary:
	var out = {"found": false, "from": -1, "to": -1, "specs": []}
	var prefix = KEY + ":"
	for i in lines.size():
		var line = lines[i]
		if line.begins_with(" ") or line.begins_with("\t") or not line.strip_edges().begins_with(prefix):
			continue
		out.found = true
		out.from = i
		out.to = i + 1
		var value = line.strip_edges().substr(prefix.length()).strip_edges()
		if value.begins_with("["):
			while not "]" in value and out.to < lines.size():
				value += lines[out.to]
				out.to += 1
			out.specs = _flow_items(value)
		elif value != "":
			value = DepResolver.unquote(value)
			if value != REQUIRE_REF:
				out.specs.append(value)
		else:
			var j = out.to
			while j < lines.size():
				var item = lines[j].strip_edges()
				if item.begins_with("- "):
					item = DepResolver.unquote(item.substr(2).strip_edges())
					if item != REQUIRE_REF:
						out.specs.append(item)
					out.to = j + 1 # only an item extends the range, so a comment after the block survives
				elif not item.begins_with("#"):
					break
				j += 1
		break
	return out


## {found, from, to, specs}: character offsets from the opening quote of "build_require" to the end
## of its value, a trailing comma excluded so the rest of the object stays valid.
static func _locate_json(text:String) -> Dictionary:
	var out = {"found": false, "from": -1, "to": -1, "specs": []}
	var needle = '"%s"' % KEY
	var at = text.find(needle)
	if at < 0:
		return out
	var colon = text.find(":", at + needle.length())
	if colon < 0:
		return out
	var i = colon + 1
	while i < text.length() and text[i] in [" ", "\t", "\n", "\r"]:
		i += 1
	if i >= text.length():
		return out
	out.found = true
	out.from = at
	if text[i] == "[":
		var depth = 0
		var in_string = false
		while i < text.length():
			var c = text[i]
			if in_string:
				if c == "\\":
					i += 1
				elif c == '"':
					in_string = false
			elif c == '"':
				in_string = true
			elif c == "[":
				depth += 1
			elif c == "]":
				depth -= 1
				if depth == 0:
					i += 1
					break
			i += 1
		out.to = i
		out.specs = _flow_items(text.substr(out.from, out.to - out.from))
		return out
	while i < text.length() and not text[i] in [",", "\n", "}"]:
		i += 1
	out.to = i
	var value = DepResolver.unquote(text.substr(colon + 1, out.to - colon - 1).strip_edges())
	if value != "" and value != REQUIRE_REF:
		out.specs.append(value)
	return out


## Items of a `[a, "b"]` sequence, quoted or not, "@require" dropped.
static func _flow_items(text:String) -> Array:
	var inside = text.substr(text.find("[") + 1)
	if "]" in inside:
		inside = inside.substr(0, inside.rfind("]"))
	var out = []
	for part in inside.split(","):
		var item = DepResolver.unquote(part.strip_edges())
		if item != "" and item != REQUIRE_REF:
			out.append(item)
	return out


static func _rewrite_yaml(text:String, specs:Array) -> String:
	var lines = Array(text.split("\n"))
	var block = _yaml_block(specs)
	var found = _locate_yaml(text.split("\n"))
	if found.found:
		var rest = lines.slice(found.to)
		lines = lines.slice(0, found.from)
		lines.append_array(block)
		lines.append_array(rest)
		return "\n".join(lines)

	var at = lines.size()
	for i in lines.size():
		if lines[i].begins_with("exports:"):
			at = i
			break
	if at == lines.size(): # appended, but still inside the file's last newline
		while at > 0 and lines[at - 1].strip_edges() == "":
			at -= 1
	var head = lines.slice(0, at)
	head.append_array(block)
	head.append_array(lines.slice(at))
	return "\n".join(head)


static func _yaml_block(specs:Array) -> Array:
	if specs.is_empty():
		return ["%s: []" % KEY]
	var out = ["%s:" % KEY]
	for spec in specs:
		out.append('  - "%s"' % spec)
	return out


static func _rewrite_json(text:String, specs:Array) -> String:
	var unit = _json_indent(text)
	var found = _locate_json(text)
	if found.found:
		var head = text.substr(0, found.from)
		var key_indent = head.substr(head.rfind("\n") + 1)
		if key_indent.strip_edges() != "": # the key shares its line with something else
			key_indent = unit
		return head + _json_block(specs, key_indent, unit) + text.substr(found.to)

	var brace = text.find("{")
	if brace < 0:
		return text
	# The text after the brace keeps its own newline, so the next key stays on its own line.
	return "%s\n%s%s,%s" % [text.substr(0, brace + 1), unit, _json_block(specs, unit, unit),
		text.substr(brace + 1)]


## The key line and its value, without the leading indent the caller already has in hand.
static func _json_block(specs:Array, key_indent:String, unit:String) -> String:
	if specs.is_empty():
		return '"%s": []' % KEY
	var items = specs.map(func(s): return '%s%s"%s"' % [key_indent, unit, s])
	return '"%s": [\n%s\n%s]' % [KEY, ",\n".join(items), key_indent]


## The indent one level down from the top-level object, taken from the first key that shows it.
static func _json_indent(text:String) -> String:
	for line in text.split("\n"):
		var stripped = line.strip_edges()
		if stripped == "" or stripped.begins_with("{"):
			continue
		var indent = line.substr(0, line.length() - String(line).lstrip(" \t").length())
		if indent != "":
			return indent
	return "\t"

#endregion

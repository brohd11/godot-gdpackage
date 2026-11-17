@tool
extends RefCounted
## Package-level dependency graph from declared requires, read as `require check` reads them.
## BFS from the root: a package sits in the first layer that reaches it, and the edge that found
## it is its tree edge. Nested requires come from each dep's local checkout, not the declared tag.
## apply_usage() then lays RequireReport's crawl over it: the files each package contributes, and
## drift between what is declared and what is used.

const DepResolver = preload("res://addons/gdpackage/src/class/release/dep_resolver.gd")
const RequireConsumers = preload("res://addons/gdpackage/src/class/release/require_consumers.gd")
const ExternalDeps = preload("res://addons/gdpackage/src/class/export/external_deps.gd")

const KEYS = ["build", "compile", "test"] # edge.keys order
const ADDONS = "res://addons/"


## {root, nodes: {id: node}, edges: [edge], errors}, nodes in BFS order.
## node: {id, dir, name, layer, declared_tag, kind, local_version, resolved, requires, flags, files,
##   usage_loaded}
## edge: {from, to, keys, tag, tree, state}; state is "", "undeclared" or "unused" (apply_usage)
## opts: include_tests (false); index (repo_id -> dir, else ExternalDeps.local_index());
## read_declared / read_version (Callable(dir)) to stub disk in tests.
static func build(package_dir:String, opts:Dictionary = {}) -> Dictionary:
	var include_tests:bool = opts.get("include_tests", false)
	var index:Dictionary = opts["index"] if opts.has("index") else ExternalDeps.local_index()
	var read_declared:Callable = opts.get("read_declared", func(dir): return RequireConsumers.declared(dir))
	var read_version:Callable = opts.get("read_version", func(dir): return _local_version(dir))

	var by_dir = {}
	for id in index:
		by_dir[_norm(index[id])] = id
	var root_dir = _norm(package_dir)
	var root_id:String = by_dir.get(root_dir, root_dir)

	var out = {"root": root_id, "nodes": {}, "edges": [], "errors": []}
	var nodes:Dictionary = out.nodes
	nodes[root_id] = _node(root_id, root_dir, 0, read_version)
	var edge_index = {} # "from|to" -> edge
	var queue:Array = [root_id]
	var i = 0
	while i < queue.size():
		var node = nodes[queue[i]]
		i += 1
		if not node.resolved:
			continue
		var declared:Dictionary = read_declared.call(node.dir)
		if declared.get("error", "") != "":
			out.errors.append("%s: %s" % [node.name, declared.error])
		var reqs = declared.get("requires", []).filter(func(r): return include_tests or not r.test)
		reqs.sort_custom(func(a, b): return a.dep.repo_id < b.dep.repo_id)
		for req in reqs:
			var to:String = req.dep.repo_id
			if to == node.id:
				continue
			var key = "compile" if req.compile else ("test" if req.test else "build")
			var edge_key = node.id + "|" + to
			if edge_index.has(edge_key):
				var keys:Array = edge_index[edge_key].keys
				if not key in keys:
					keys.append(key)
					keys.sort_custom(func(a, b): return KEYS.find(a) < KEYS.find(b))
				continue
			var edge = {"from": node.id, "to": to, "keys": [key], "tag": req.dep.tag, "tree": false, "state": ""}
			if not nodes.has(to):
				var dep_node = _node(to, _norm(index.get(to, "")), node.layer + 1, read_version)
				dep_node.declared_tag = req.dep.tag
				dep_node.kind = req.dep.kind
				if not dep_node.resolved:
					dep_node.name = req.dep.repo
				nodes[to] = dep_node
				edge.tree = true
				queue.append(to)
			node.requires.append(to)
			edge_index[edge_key] = edge
			out.edges.append(edge)
	return out


## Lays a RequireReport.build() result over `graph`, in place. A used package with no declared edge
## gets an "undeclared" edge, and a node of its own if the graph never reached it. "unused" is only
## judged on the root, as RequireReport does; compile-only requires are never crawled, so are skipped.
static func apply_usage(graph:Dictionary, report:Dictionary) -> void:
	var nodes:Dictionary = graph.nodes
	var by_dir = {}
	for id in nodes:
		if nodes[id].dir != "":
			by_dir[nodes[id].dir] = id
	var edge_index = {}
	for edge in graph.edges:
		edge_index[edge.from + "|" + edge.to] = edge

	var files = {} # node id -> {path: true}
	var root = nodes[graph.root]
	for path in report.get("files", []):
		_add_file(files, root.id, path)

	for from_dir in report.get("groups", {}):
		var from_id = by_dir.get(_norm(from_dir), "")
		for row in report.groups[from_dir].rows:
			var dir = _norm(row.dir)
			var to_id = by_dir.get(dir, "")
			if to_id == "" and nodes.has(row.id):
				to_id = row.id
			if to_id == "":
				if from_id == "":
					continue # used only from outside any package in the graph: nowhere to hang it
				to_id = row.id if row.id != "" else dir
				var added = _node(to_id, dir, nodes[from_id].layer + 1, func(d): return _local_version(d))
				added.usage_loaded = true
				nodes[to_id] = added
				by_dir[dir] = to_id
			for ref in row.refs:
				_add_file(files, to_id, ref.to)
			if from_id == "" or from_id == to_id or edge_index.has(from_id + "|" + to_id):
				continue
			var edge = {"from": from_id, "to": to_id, "keys": [], "tag": "", "tree": false, "state": "undeclared"}
			graph.edges.append(edge)
			edge_index[from_id + "|" + to_id] = edge
			_flag(nodes[to_id], "undeclared")

	for id in report.get("unused", {}).get(report.get("target", ""), []):
		var edge = edge_index.get(root.id + "|" + id)
		if edge == null or not "build" in edge.keys:
			continue
		edge.state = "unused"
		_flag(nodes[id], "unused")

	for id in nodes:
		var node = nodes[id]
		node.usage_loaded = true
		var paths = files.get(id, {}).keys()
		paths.sort()
		node.files = paths


static func _add_file(files:Dictionary, id:String, path:String) -> void:
	if not files.has(id):
		files[id] = {}
	files[id][path] = true


static func _flag(node:Dictionary, flag:String) -> void:
	if not flag in node.flags:
		node.flags.append(flag)


## 1 local checkout ahead of the declared tag, -1 behind, 0 same or not comparable.
static func version_state(node:Dictionary) -> int:
	if node.local_version == "" or node.declared_tag == "":
		return 0
	var cmp = DepResolver.compare_tags("v" + node.local_version.trim_prefix("v"), node.declared_tag)
	return 0 if cmp == DepResolver.TAGS_INCOMPARABLE else cmp


static func _node(id:String, dir:String, layer:int, read_version:Callable) -> Dictionary:
	var resolved = dir != ""
	return {"id": id, "dir": dir, "name": display_name(dir) if resolved else id, "layer": layer,
		"declared_tag": "", "kind": DepResolver.KIND_SOURCE,
		"local_version": String(read_version.call(dir)) if resolved else "",
		"resolved": resolved, "requires": [], "flags": [], "files": [], "usage_loaded": false}


## Relative to res://addons with _lib/ dropped, so nested libs stay apart (gdpackage/spec).
static func display_name(dir:String) -> String:
	if not dir.begins_with(ADDONS):
		return dir.get_file()
	return dir.trim_prefix(ADDONS).trim_prefix("_lib/")


static func _local_version(dir:String) -> String:
	return str(DepResolver.PackageCfg.dir_value(dir, "version", ""))


static func _norm(dir:String) -> String:
	return dir.simplify_path().trim_suffix("/")

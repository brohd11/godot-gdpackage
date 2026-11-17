@tool
extends RefCounted
## Package-level dependency graph from declared requires, read as `require check` reads them.
## BFS from the root: a package sits in the first layer that reaches it, and the edge that found
## it is its tree edge. Nested requires come from each dep's local checkout, not the declared tag.
## node.flags / node.files are empty here; a usage pass (RequireReport.build) is meant to fill them.

const DepResolver = preload("res://addons/gdpackage/src/class/release/dep_resolver.gd")
const RequireConsumers = preload("res://addons/gdpackage/src/class/release/require_consumers.gd")
const ExternalDeps = preload("res://addons/gdpackage/src/class/export/external_deps.gd")

const KEYS = ["build", "compile", "test"] # edge.keys order
const ADDONS = "res://addons/"


## {root, nodes: {id: node}, edges: [edge], errors}, nodes in BFS order.
## node: {id, dir, name, layer, declared_tag, kind, local_version, resolved, requires, flags, files}
## edge: {from, to, keys, tag, tree}
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
			var edge = {"from": node.id, "to": to, "keys": [key], "tag": req.dep.tag, "tree": false}
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
		"resolved": resolved, "requires": [], "flags": [], "files": []}


## Relative to res://addons with _lib/ dropped, so nested libs stay apart (gdpackage/spec).
static func display_name(dir:String) -> String:
	if not dir.begins_with(ADDONS):
		return dir.get_file()
	return dir.trim_prefix(ADDONS).trim_prefix("_lib/")


static func _local_version(dir:String) -> String:
	return str(DepResolver.PackageCfg.dir_value(dir, "version", ""))


static func _norm(dir:String) -> String:
	return dir.simplify_path().trim_suffix("/")

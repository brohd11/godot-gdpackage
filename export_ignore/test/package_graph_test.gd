@tool
extends EditorScript
## PackageGraph layering over stubbed requires: first layer wins, tree vs secondary edges,
## unresolved leaves, cycles, test_require behind the opt.

const PackageGraph = preload("res://addons/gdpackage/src/class/package_graph.gd")
const DepResolver = preload("res://addons/gdpackage/src/class/release/dep_resolver.gd")

static var _failures:Array[String] = []
static var _passed:int = 0


static func run_tests() -> Dictionary:
	_failures = []
	_passed = 0
	_test_layers()
	_test_tests_opt()
	_test_root_in_index()
	_test_version_state()
	_test_usage()
	_test_usage_compile_only()
	_test_flow_columns()
	var output:Array[String] = ["package_graph: %d passed, %d failed" % [_passed, _failures.size()]]
	for failure in _failures:
		output.append("  FAIL  " + failure)
	return {"result": _failures.size(), "output": output}


func _run() -> void:
	print("\n".join(run_tests().output))


# r -> a, b (+ t as test); a -> c, b; b -> c; c -> a (cycle), x (no local dir)
static func _fixture() -> Dictionary:
	return {
		"res://r": [_req("o/a"), _req("o/b"), _req("o/a", "test"), _req("o/t", "test")],
		"res://a": [_req("o/c"), _req("o/b")],
		"res://b": [_req("o/c")],
		"res://c": [_req("o/a"), _req("o/x@v1.2")],
		"res://t": [],
	}


static func _index() -> Dictionary:
	return {_id("o/a"): "res://a", _id("o/b"): "res://b/", _id("o/c"): "res://c", _id("o/t"): "res://t"}


static func _opts(extra:Dictionary = {}) -> Dictionary:
	var declared = _fixture()
	var opts = {
		"index": _index(),
		"read_declared": func(dir): return {"requires": declared.get(dir, []), "error": ""},
		"read_version": func(_dir): return "",
	}
	opts.merge(extra, true)
	return opts


static func _test_layers() -> void:
	var g = PackageGraph.build("res://r/", _opts())
	var a = _id("o/a"); var b = _id("o/b"); var c = _id("o/c"); var x = _id("o/x")
	_check("root id falls back to its dir", g.root, "res://r")
	_check("layers, first layer wins", g.nodes.keys().map(func(k): return [g.nodes[k].name, g.nodes[k].layer]),
		[["r", 0], ["a", 1], ["b", 1], ["c", 2], ["x", 3]])
	_check("tree edges", _edges(g, true), [["res://r", a], ["res://r", b], [a, c], [c, x]])
	_check("secondary edges, cycle included", _edges(g, false), [[a, b], [b, c], [c, a]])
	_check("test require left out by default", g.nodes.has(_id("o/t")), false)
	_check("unresolved leaf", [g.nodes[x].resolved, g.nodes[x].dir, g.nodes[x].declared_tag], [false, "", "v1.2"])
	_check("requires recorded per node", g.nodes[a].requires, [b, c])
	_check("index dir normalised", g.nodes[b].dir, "res://b")
	_check("deterministic", str(PackageGraph.build("res://r", _opts())), str(g))


static func _test_tests_opt() -> void:
	var g = PackageGraph.build("res://r", _opts({"include_tests": true}))
	_check("test require included with the opt", g.nodes.has(_id("o/t")) and g.nodes[_id("o/t")].layer == 1, true)
	var keys = g.edges.filter(func(e): return e.to == _id("o/a") and e.from == "res://r").map(func(e): return e.keys)
	_check("one edge per pair, keys merged", keys, [["build", "test"]])


static func _test_root_in_index() -> void:
	var index = _index()
	index[_id("o/r")] = "res://r"
	var fixture = _fixture()
	fixture["res://c"].append(_req("o/r"))
	var g = PackageGraph.build("res://r", _opts({"index": index,
		"read_declared": func(dir): return {"requires": fixture.get(dir, []), "error": ""}}))
	_check("root takes its repo id", g.root, _id("o/r"))
	_check("cycle back to root is a secondary edge", _edges(g, false).has([_id("o/c"), _id("o/r")]), true)
	_check("root not duplicated", g.nodes.size(), 5)


static func _test_version_state() -> void:
	var node = {"local_version": "0.3.0", "declared_tag": "v0.2.1"}
	_check("ahead", PackageGraph.version_state(node), 1)
	node.local_version = "0.2.1"
	_check("same", PackageGraph.version_state(node), 0)
	node.declared_tag = "v1"
	_check("behind", PackageGraph.version_state(node), -1)
	node.declared_tag = ""
	_check("no tag", PackageGraph.version_state(node), 0)
	_check("display_name", ["res://addons/_lib/gdpackage/spec", "res://addons/gdpackage", "user://x/lib"].map(PackageGraph.display_name),
		["gdpackage/spec", "gdpackage", "lib"])


static func _report() -> Dictionary:
	var a = _id("o/a")
	return {"target": "res://r", "files": ["res://r/main.gd", "res://r/b.gd"], "unused": {"res://r": [_id("o/b")]},
		"groups": {
			"res://r/": {"rows": [_row("res://a", a, ["res://a/2.gd", "res://a/1.gd"]), _row("res://c", _id("o/c"), ["res://c/1.gd"])]},
			"res://b": {"rows": [_row("res://a", a, ["res://a/1.gd", "res://a/3.gd"])]},
			"res://c": {"rows": [_row("res://z", _id("o/z"), ["res://z/z.gd"])]},
			"": {"rows": [_row("res://a", a, ["res://a/4.gd"])]},
		}}


static func _row(dir:String, id:String, tos:Array) -> Dictionary:
	return {"dir": dir, "id": id, "refs": tos.map(func(t): return {"to": t})}


static func _test_usage() -> void:
	var g = PackageGraph.build("res://r", _opts())
	var before = _edges(g, true) + _edges(g, false)
	PackageGraph.apply_usage(g, _report())
	var a = _id("o/a"); var b = _id("o/b"); var c = _id("o/c"); var z = _id("o/z")
	_check("root files from the crawl roots", g.nodes["res://r"].files, ["res://r/b.gd", "res://r/main.gd"])
	_check("files unioned over every consumer, sorted", g.nodes[a].files, ["res://a/1.gd", "res://a/2.gd", "res://a/3.gd", "res://a/4.gd"])
	_check("declared edges keep state", g.edges.filter(func(e): return [e.from, e.to] in before and e.state == "undeclared"), [])
	var undeclared = g.edges.filter(func(e): return e.state == "undeclared").map(func(e): return [e.from, e.to])
	_check("undeclared edges, none from outside a package", undeclared, [["res://r", c], [b, a], [c, z]])
	_check("undeclared package gets a node one layer past its user", [g.nodes[z].layer, g.nodes[z].dir, g.nodes[z].files], [3, "res://z", ["res://z/z.gd"]])
	_check("undeclared flags", [g.nodes[c].flags, g.nodes[a].flags, g.nodes[z].flags], [["undeclared"], ["undeclared"], ["undeclared"]])
	var unused = g.edges.filter(func(e): return e.state == "unused").map(func(e): return [e.from, e.to])
	_check("unused judged on the root edge", [unused, g.nodes[b].flags], [[["res://r", b]], ["unused"]])
	_check("usage_loaded everywhere, x has no files", [g.nodes.values().all(func(n): return n.usage_loaded), g.nodes[_id("o/x")].files], [true, []])

	var clean = PackageGraph.build("res://r", _opts())
	PackageGraph.apply_usage(clean, {"target": "res://r", "files": [], "unused": {},
		"groups": {"res://r": {"rows": [_row("res://a", a, ["res://a/1.gd"])]}}})
	_check("no drift when use matches declared", [clean.edges.all(func(e): return e.state == ""), clean.nodes.values().all(func(n): return n.flags.is_empty())], [true, true])


static func _test_usage_compile_only() -> void:
	var fixture = _fixture()
	fixture["res://r"].append(_req("o/t", "compile"))
	var g = PackageGraph.build("res://r", _opts({"read_declared": func(dir): return {"requires": fixture.get(dir, []), "error": ""}}))
	PackageGraph.apply_usage(g, {"target": "res://r", "files": [], "groups": {}, "unused": {"res://r": [_id("o/t")]}})
	var edge = g.edges.filter(func(e): return e.to == _id("o/t"))[0]
	_check("compile-only require never flagged unused", [edge.keys, edge.state, g.nodes[_id("o/t")].flags], [["compile"], "", []])


static func _test_flow_columns() -> void:
	var g = PackageGraph.build("res://r", _opts())
	var cols = PackageGraph.flow_columns(g)
	var a = _id("o/a"); var b = _id("o/b"); var c = _id("o/c"); var x = _id("o/x")
	_check("longest path from the root", [cols["res://r"], cols[a], cols[b], cols[c], cols[x]], [0, 1, 2, 3, 4])
	var backward = g.edges.filter(func(e): return cols[e.to] <= cols[e.from]).map(func(e): return [e.from, e.to])
	_check("only the cycle-closing edge points back", backward, [[c, a]])
	_check("flow deterministic", str(PackageGraph.flow_columns(PackageGraph.build("res://r", _opts()))), str(cols))
	_check("new_requires", [PackageGraph.new_requires(g, "res://r"), PackageGraph.new_requires(g, a), PackageGraph.new_requires(g, b)], [2, 1, 0])

	# c -> z undeclared: z lands one past c
	PackageGraph.apply_usage(g, {"target": "res://r", "files": [], "unused": {},
		"groups": {"res://x": {"rows": []}, "res://c": {"rows": [_row("res://z", _id("o/z"), ["res://z/z.gd"])]}}})
	var with_z = PackageGraph.flow_columns(g)
	_check("undeclared edges take part", with_z[_id("o/z")], 4)


static func _req(spec:String, key:String = "build") -> Dictionary:
	return {"dep": DepResolver.parse_dep(spec), "compile": key == "compile", "test": key == "test"}


static func _id(spec:String) -> String:
	return DepResolver.parse_dep(spec).repo_id


static func _edges(g:Dictionary, tree:bool) -> Array:
	return g.edges.filter(func(e): return e.tree == tree).map(func(e): return [e.from, e.to])


static func _check(label:String, got, expected) -> void:
	if got == expected:
		_passed += 1
		return
	_failures.append("%s (expected %s, got %s)" % [label, expected, got])

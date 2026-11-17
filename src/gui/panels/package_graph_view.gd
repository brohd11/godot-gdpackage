@tool
extends GraphEdit
## Draws a PackageGraph: one node per package, a column per BFS layer. Tree edges by default;
## show_all_edges adds the rest through a second, muted port row, since GraphEdit colours a line
## from its port colours and has no per-connection style.

const PackageGraph = preload("res://addons/gdpackage/src/class/package_graph.gd")

const ROOT_COLOR = Color("6aa9e3")
const EDGE_COLOR = Color("c8ccd0")
const MUTED_COLOR = Color("6c7177")
const UNRESOLVED_COLOR = Color("e05a5a")
const AHEAD_COLOR = Color("d9b35a")  # local checkout past the declared tag
const BEHIND_COLOR = Color("e05a5a")
const NODE_WIDTH = 220.0
const VIEW_MARGIN = 40.0

const PORT_TREE = 0
const PORT_SECONDARY = 1

signal package_activated(dir:String)

var h_gap:float = 120.0
var v_gap:float = 24.0
var show_all_edges:bool = false:
	set(value):
		show_all_edges = value
		if not _data.is_empty():
			_rebuild()

var _data:Dictionary = {}
var _nodes:Dictionary = {} # package id -> PackageNode


func _ready() -> void:
	minimap_enabled = true
	show_grid = true
	right_disconnects = false
	connection_lines_curvature = 0.4
	connection_lines_antialiased = true
	connection_lines_thickness = 2.5
	zoom_min = 0.05
	zoom_max = 2.0


func set_graph(data:Dictionary) -> void:
	_data = data
	_rebuild()


func clear_graph() -> void:
	clear_connections()
	for node in _nodes.values():
		remove_child(node) # before free: rebuilt names would otherwise collide with the queued ones
		node.queue_free()
	_nodes.clear()


func _rebuild() -> void:
	clear_graph()
	if _data.is_empty():
		return
	var i = 0
	for id in _data.nodes:
		var node = PackageNode.new()
		node.name = "p%d" % i
		i += 1
		add_child(node)
		node.setup(_data.nodes[id], id == _data.root, show_all_edges, _edge_keys(id))
		node.activated.connect(func(dir): package_activated.emit(dir))
		_nodes[id] = node
	_layout()
	for edge in _data.edges:
		if not (edge.tree or show_all_edges):
			continue
		var port = PORT_TREE if edge.tree else PORT_SECONDARY
		connect_node(_nodes[edge.from].name, port, _nodes[edge.to].name, port)
	_fit_view()
	if is_inside_tree():
		# GraphEdit clamps scroll against bounds it has not measured yet on the build frame
		get_tree().process_frame.connect(_fit_view, CONNECT_ONE_SHOT | CONNECT_DEFERRED)


## "keys" of every edge into `id`, for the tooltip: who requires it and how.
func _edge_keys(id:String) -> Array:
	var out = []
	for edge in _data.edges:
		if edge.to == id:
			var from = _data.nodes[edge.from].name
			out.append("%s  %s%s" % [from, ", ".join(edge.keys), (" @" + edge.tag) if edge.tag != "" else ""])
	return out


# Columns by layer; within one, ordered by the tree parent's row so tree edges cross least.
func _layout() -> void:
	var scale = EditorInterface.get_editor_scale()
	var parent_of = {}
	for edge in _data.edges:
		if edge.tree:
			parent_of[edge.to] = edge.from
	var columns = {} # layer -> [id]
	for id in _data.nodes:
		var layer:int = _data.nodes[id].layer
		if not columns.has(layer):
			columns[layer] = []
		columns[layer].append(id)

	var row_of = {}
	var x = 0.0
	var layers = columns.keys()
	layers.sort()
	for layer in layers:
		var ids:Array = columns[layer]
		ids.sort_custom(func(a, b):
			var ra = row_of.get(parent_of.get(a, ""), -1)
			var rb = row_of.get(parent_of.get(b, ""), -1)
			return ra < rb if ra != rb else _data.nodes[a].name < _data.nodes[b].name)
		var height = 0.0
		var width = 0.0
		for id in ids:
			var size = _nodes[id].get_combined_minimum_size()
			height += size.y
			width = maxf(width, size.x)
		height += v_gap * scale * maxi(ids.size() - 1, 0)
		var y = -height * 0.5
		for r in ids.size():
			var id = ids[r]
			row_of[id] = r
			_nodes[id].position_offset = Vector2(x, y)
			y += _nodes[id].get_combined_minimum_size().y + v_gap * scale
		x += width + h_gap * scale


func _fit_view() -> void:
	if _nodes.is_empty() or size.x <= 0.0 or size.y <= 0.0:
		return
	var bounds:Rect2
	var first = true
	for node in _nodes.values():
		var rect = Rect2(node.position_offset, node.get_combined_minimum_size())
		bounds = rect if first else bounds.merge(rect)
		first = false
	bounds = bounds.grow(VIEW_MARGIN * EditorInterface.get_editor_scale())
	zoom = clampf(minf(size.x / bounds.size.x, size.y / bounds.size.y), zoom_min, 1.0)
	scroll_offset = bounds.get_center() * zoom - size * 0.5


class PackageNode extends GraphNode:
	signal activated(dir:String)

	var dir:String = ""

	func setup(node:Dictionary, is_root:bool, secondary:bool, required_by:Array) -> void:
		var scale = EditorInterface.get_editor_scale()
		dir = node.dir
		title = node.name
		custom_minimum_size = Vector2(NODE_WIDTH * scale, 0.0)
		resizable = false

		var version = _row()
		version.text = _version_text(node)
		var state = PackageGraph.version_state(node)
		if state != 0:
			version.add_theme_color_override("font_color", AHEAD_COLOR if state > 0 else BEHIND_COLOR)
		var info = _row()
		var parts:Array = []
		if node.resolved:
			parts.append("%d requires" % node.requires.size())
		else:
			parts.append("not in project")
		parts.append_array(node.flags)
		info.text = "  ·  ".join(parts)
		info.add_theme_color_override("font_color", MUTED_COLOR)

		var tree_color = UNRESOLVED_COLOR if not node.resolved else EDGE_COLOR
		set_slot(PORT_TREE, not is_root, 0, tree_color, node.resolved and not node.requires.is_empty(), 0, EDGE_COLOR)
		if secondary:
			# input always on: a cycle can lead back into the root
			set_slot(PORT_SECONDARY, true, 0, MUTED_COLOR, node.resolved and not node.requires.is_empty(), 0, MUTED_COLOR)

		if is_root:
			add_theme_color_override("title_color", ROOT_COLOR)
		elif not node.resolved:
			add_theme_color_override("title_color", UNRESOLVED_COLOR)
			modulate.a = 0.75

		var tip:Array = [node.dir if node.resolved else node.id]
		if node.resolved and node.id != node.dir:
			tip.append(node.id)
		if not required_by.is_empty():
			tip.append("required by:")
			tip.append_array(required_by.map(func(l): return "  " + l))
		tooltip_text = "\n".join(tip)

	func _row() -> Label:
		var label = Label.new()
		label.custom_minimum_size.y = 22.0 * EditorInterface.get_editor_scale()
		add_child(label)
		return label

	static func _version_text(node:Dictionary) -> String:
		var tag = node.declared_tag
		var local = ("v" + node.local_version.trim_prefix("v")) if node.local_version != "" else ""
		if tag == "":
			return local if local != "" else "-"
		if local == "" or PackageGraph.version_state(node) == 0:
			return tag
		return "%s  (local %s)" % [tag, local]

	func _gui_input(event:InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.double_click \
				and event.button_index == MOUSE_BUTTON_LEFT and dir != "":
			activated.emit(dir)
			accept_event()

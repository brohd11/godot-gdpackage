@tool
extends GraphEdit
## Draws a PackageGraph: one node per package, a column per BFS layer. Each edge kind has its own
## port row (tree, secondary, undeclared), since GraphEdit colours a line from its port colours and
## has no per-connection style. With usage applied, a node also draws the files it contributes.

const UtilsRemote = preload("res://addons/gdpackage/src/class/utils_remote.gd")
const KindStyle = UtilsRemote.DepGraphUI.KindStyle
const PackageGraph = preload("res://addons/gdpackage/src/class/package_graph.gd")

const ROOT_COLOR = Color("6aa9e3")
const EDGE_COLOR = Color("c8ccd0")
const MUTED_COLOR = Color("6c7177")
const UNRESOLVED_COLOR = Color("e05a5a")
const UNDECLARED_COLOR = Color("e05a5a")
const WARN_COLOR = Color("d9b35a")
const AHEAD_COLOR = Color("d9b35a")  # local checkout past the declared tag
const BEHIND_COLOR = Color("e05a5a")
const NODE_WIDTH = 220.0
const NODE_WIDTH_FILES = 300.0
const VIEW_MARGIN = 40.0
## Below this zoom file names are unreadable, so canvases draw blocks instead.
const DETAIL_ZOOM = 0.45

const SLOT_TREE = 0
const SLOT_SECONDARY = 1
const SLOT_UNDECLARED = 2

signal package_activated(dir:String)
signal file_activated(path:String)

var h_gap:float = 120.0
var v_gap:float = 24.0
var show_all_edges:bool = false:
	set(value):
		show_all_edges = value
		if not _data.is_empty():
			_rebuild()

var _data:Dictionary = {}
var _nodes:Dictionary = {} # package id -> PackageNode
var _expanded:Dictionary = {} # package id -> true; survives rebuilds of the same graph
var _detailed:bool = true


func _ready() -> void:
	minimap_enabled = true
	show_grid = true
	right_disconnects = false
	connection_lines_curvature = 0.4
	connection_lines_antialiased = true
	connection_lines_thickness = 2.5
	zoom_min = 0.05
	zoom_max = 2.0
	scroll_offset_changed.connect(func(_o): _update_detail()) # zooming moves the offset too


func set_graph(data:Dictionary) -> void:
	if data.get("root") != _data.get("root"):
		_expanded.clear()
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
	var drawn = _data.edges.filter(_edge_drawn)
	var in_slots = {} # id -> {slot: true}
	var out_slots = {}
	for edge in drawn:
		_mark(out_slots, edge.from, _slot_of(edge))
		_mark(in_slots, edge.to, _slot_of(edge))

	_detailed = zoom >= DETAIL_ZOOM
	var i = 0
	for id in _data.nodes:
		var node = PackageNode.new()
		node.name = "p%d" % i
		i += 1
		add_child(node)
		node.setup(_data.nodes[id], id == _data.root, in_slots.get(id, {}), out_slots.get(id, {}), _required_by(id))
		node.activated.connect(package_activated.emit)
		if node.canvas != null:
			node.canvas.expanded = _expanded.has(id)
			node.canvas.set_detailed(_detailed)
			node.canvas.file_activated.connect(file_activated.emit)
			node.canvas.expanded_changed.connect(_on_expanded_changed.bind(id))
		_nodes[id] = node
	_layout()
	for edge in drawn:
		var slot = _slot_of(edge)
		var from = _nodes[edge.from]
		var to = _nodes[edge.to]
		connect_node(from.name, from.out_port_of[slot], to.name, to.in_port_of[slot])
	_fit_view()
	if is_inside_tree():
		# GraphEdit clamps scroll against bounds it has not measured yet on the build frame
		get_tree().process_frame.connect(_fit_view, CONNECT_ONE_SHOT | CONNECT_DEFERRED)


func _edge_drawn(edge:Dictionary) -> bool:
	return edge.tree or edge.state == "undeclared" or show_all_edges


static func _slot_of(edge:Dictionary) -> int:
	if edge.tree:
		return SLOT_TREE
	return SLOT_UNDECLARED if edge.state == "undeclared" else SLOT_SECONDARY


static func _mark(slots:Dictionary, id:String, slot:int) -> void:
	if not slots.has(id):
		slots[id] = {}
	slots[id][slot] = true


## Tooltip lines: who requires `id`, under which keys and tag.
func _required_by(id:String) -> Array:
	var out = []
	for edge in _data.edges:
		if edge.to != id:
			continue
		var how = ", ".join(edge.keys) if not edge.keys.is_empty() else "not declared"
		var tag = (" @" + edge.tag) if edge.tag != "" else ""
		var state = ("  [%s]" % edge.state) if edge.state != "" else ""
		out.append("%s  %s%s%s" % [_data.nodes[edge.from].name, how, tag, state])
	return out


func _on_expanded_changed(id:String) -> void:
	var node = _nodes.get(id)
	if node == null:
		return
	if node.canvas.expanded:
		_expanded[id] = true
	else:
		_expanded.erase(id)
	for n in _nodes.values():
		n.reset_size() # GraphNode keeps its old size until told; layout reads the new minimum
	_layout()


func _update_detail() -> void:
	var detailed = zoom >= DETAIL_ZOOM
	if detailed == _detailed:
		return
	_detailed = detailed
	for node in _nodes.values():
		if node.canvas != null:
			node.canvas.set_detailed(detailed)


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
	var canvas:FileCanvas
	## slot -> port index. GraphEdit numbers ports per side over enabled slots only.
	var in_port_of:Dictionary = {}
	var out_port_of:Dictionary = {}

	func setup(node:Dictionary, is_root:bool, in_slots:Dictionary, out_slots:Dictionary, required_by:Array) -> void:
		var scale = EditorInterface.get_editor_scale()
		var show_files = node.usage_loaded and not node.files.is_empty()
		dir = node.dir
		title = node.name
		custom_minimum_size = Vector2((NODE_WIDTH_FILES if show_files else NODE_WIDTH) * scale, 0.0)
		resizable = false

		var version = _row(_version_text(node))
		var state = PackageGraph.version_state(node)
		if state != 0:
			version.add_theme_color_override("font_color", AHEAD_COLOR if state > 0 else BEHIND_COLOR)
		var info = _row(("%d requires" % node.requires.size()) if node.resolved else "not in project")
		info.add_theme_color_override("font_color", MUTED_COLOR)
		var colors = {SLOT_TREE: UNRESOLVED_COLOR if not node.resolved else EDGE_COLOR,
			SLOT_SECONDARY: MUTED_COLOR, SLOT_UNDECLARED: UNDECLARED_COLOR}
		var slots = [SLOT_TREE, SLOT_SECONDARY]

		if node.usage_loaded:
			var count = node.files.size()
			var parts = ["%d file%s %s" % [count, "" if count == 1 else "s", "in export" if is_root else "used"]]
			parts.append_array(node.flags)
			var usage = _row("  ·  ".join(parts))
			usage.add_theme_color_override("font_color", WARN_COLOR if not node.flags.is_empty() else MUTED_COLOR)
			slots.append(SLOT_UNDECLARED)
		if show_files:
			canvas = FileCanvas.new()
			canvas.files = node.files
			add_child(canvas)

		var in_count = 0
		var out_count = 0
		for slot in slots:
			var has_in = in_slots.has(slot)
			var has_out = out_slots.has(slot)
			set_slot(slot, has_in, 0, colors[slot], has_out, 0, colors[slot])
			if has_in:
				in_port_of[slot] = in_count
				in_count += 1
			if has_out:
				out_port_of[slot] = out_count
				out_count += 1

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

	func _row(text:String) -> Label:
		var label = Label.new()
		label.text = text
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


## The files a package contributes, drawn rather than built from Controls: a node can carry
## hundreds, and at low zoom they collapse to coloured blocks. Long lists stop at MAX_ROWS
## behind a "+N more" row that toggles the rest.
class FileCanvas extends Control:
	signal file_activated(path:String)
	signal expanded_changed

	const MAX_ROWS = 30
	const ROW_HEIGHT = 18.0
	const EXT_COLORS = {"gd": Color("6aa9e3"), "cs": Color("8fc97a"), "tscn": Color("c792ea"),
		"tres": Color("d9b35a"), "md": Color("8a8f94")}
	const OTHER_COLOR = Color("a0a4a8")

	var files:Array = []
	var expanded:bool = false:
		set(value):
			expanded = value
			_update_size()
	var _detailed:bool = true

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_PASS # clicks still reach the node, so it drags from here too

	func _ready() -> void:
		_update_size()

	func set_detailed(value:bool) -> void:
		if value != _detailed:
			_detailed = value
			queue_redraw()

	func _shown() -> int:
		return files.size() if expanded or files.size() <= MAX_ROWS else MAX_ROWS

	func _has_more() -> bool:
		return files.size() > MAX_ROWS

	func _row_height() -> float:
		return ROW_HEIGHT * EditorInterface.get_editor_scale()

	func _update_size() -> void:
		custom_minimum_size.y = (_shown() + (1 if _has_more() else 0)) * _row_height()
		queue_redraw()

	func _draw() -> void:
		var scale = EditorInterface.get_editor_scale()
		var row_h = _row_height()
		var font = get_theme_default_font()
		var font_size = get_theme_default_font_size()
		var icon_size = 14.0 * scale
		var text_color = get_theme_color(&"font_color", &"Label")
		var baseline = (row_h + font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
		for i in _shown():
			var path:String = files[i]
			var y = i * row_h
			if not _detailed:
				draw_rect(Rect2(2.0 * scale, y + 2.0 * scale, size.x - 4.0 * scale, row_h - 4.0 * scale),
					EXT_COLORS.get(path.get_extension(), OTHER_COLOR))
				continue
			var icon = KindStyle.get_file_icon(path)
			if icon != null:
				draw_texture_rect(icon, Rect2(2.0 * scale, y + (row_h - icon_size) * 0.5, icon_size, icon_size), false)
			var x = icon_size + 6.0 * scale
			draw_string(font, Vector2(x, y + baseline), path.get_file(), HORIZONTAL_ALIGNMENT_LEFT,
				size.x - x, font_size, text_color)
		if _has_more():
			var text = "show less" if expanded else "+%d more" % (files.size() - MAX_ROWS)
			draw_string(font, Vector2(2.0 * scale, _shown() * row_h + baseline), text,
				HORIZONTAL_ALIGNMENT_LEFT, size.x, font_size, MUTED_COLOR)

	## -1 outside the canvas: tooltip lookups can arrive with positions beyond its rect.
	func _row_at(pos:Vector2) -> int:
		if not Rect2(Vector2.ZERO, size).has_point(pos):
			return -1
		return int(pos.y / _row_height())

	func _get_tooltip(at_position:Vector2) -> String:
		var row = _row_at(at_position)
		return files[row] if row >= 0 and row < _shown() else ""

	func _gui_input(event:InputEvent) -> void:
		if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
			return
		var row = _row_at(event.position)
		if row < 0:
			return
		if row == _shown() and _has_more():
			expanded = not expanded
			expanded_changed.emit()
			accept_event()
		elif event.double_click and row < _shown():
			file_activated.emit(files[row])
			accept_event()

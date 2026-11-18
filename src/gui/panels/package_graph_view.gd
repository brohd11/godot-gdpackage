@tool
extends GraphEdit
## Draws a PackageGraph: one node per package, a column per BFS layer. Each edge kind has its own
## port row (tree, secondary, undeclared), since GraphEdit colours a line from its port colours and
## has no per-connection style. With usage applied, a node also draws the files it contributes.

const UtilsRemote = preload("res://addons/gdpackage/src/class/utils_remote.gd")
const DepGraphUI = UtilsRemote.DepGraphUI
const KindStyle = DepGraphUI.KindStyle
const ClickCallback = UtilsRemote.ClickCallback
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
## Column gap for both layouts, unscaled. It stretches up to the max to match the view's aspect,
## so the graph fills the panel instead of a strip.
const COLUMN_GAP = 260.0
const COLUMN_GAP_MAX = 700.0
## Show All Edges only: roomier rows, and barycenter passes over the columns.
const FLOW_V_GAP = 48.0
const FLOW_SWEEPS = 4

const SLOT_TREE = 0
const SLOT_SECONDARY = 1
const SLOT_UNDECLARED = 2

## Clicks on package nodes; callbacks get (dir:String). Unresolved packages have no dir, so never fire.
var package_clicks := ClickCallback.new()
## Clicks on the file rows drawn inside nodes; callbacks get (path:String).
var file_clicks := ClickCallback.new()

var v_gap:float = 24.0
var show_all_edges:bool = false:
	set(value):
		show_all_edges = value
		if not _data.is_empty():
			_rebuild()

var _data:Dictionary = {}
var _nodes:Dictionary = {} # package id -> PackageNode
var _expanded:Dictionary = {} # package id -> true; survives rebuilds of the same graph
var _drawn:Array = [] # edges with a line on screen; the flow layout ranks over these
var _detailed:bool = true
var _activity_queued:bool = false


func _ready() -> void:
	minimap_enabled = true
	show_grid = true
	right_disconnects = false
	connection_lines_curvature = 0.4
	connection_lines_antialiased = true
	connection_lines_thickness = DepGraphUI.LINE_THICKNESS
	zoom_min = 0.05
	zoom_max = 2.0
	scroll_offset_changed.connect(_on_zoom_or_scroll) # zooming moves the offset too
	add_theme_color_override(&"activity", DepGraphUI.ACTIVE_LINE_COLOR)
	node_selected.connect(func(_n): _queue_activity())
	node_deselected.connect(func(_n): _queue_activity())


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
	_drawn = _data.edges.filter(_edge_drawn)
	var in_slots = {} # id -> {slot: true}
	var out_slots = {}
	for edge in _drawn:
		_mark(out_slots, edge.from, _slot_of(edge))
		_mark(in_slots, edge.to, _slot_of(edge))

	_detailed = zoom >= DETAIL_ZOOM
	var i = 0
	for id in _data.nodes:
		var node = PackageNode.new()
		node.name = "p%d" % i
		i += 1
		add_child(node)
		node.setup(_data.nodes[id], id == _data.root, PackageGraph.new_requires(_data, id),
			in_slots.get(id, {}), out_slots.get(id, {}), _required_by(id))
		node.clicks = package_clicks
		if node.canvas != null:
			node.canvas.expanded = _expanded.has(id)
			node.canvas.set_detailed(_detailed)
			node.canvas.clicks = file_clicks
			node.canvas.expanded_changed.connect(_on_expanded_changed.bind(id))
		_nodes[id] = node
	_layout()
	for edge in _drawn:
		var slot = _slot_of(edge)
		var from = _nodes[edge.from]
		var to = _nodes[edge.to]
		connect_node(from.name, from.out_port_of[slot], to.name, to.in_port_of[slot])
	_queue_activity()
	_fit_view()
	if is_inside_tree():
		# GraphEdit clamps scroll against bounds it has not measured yet on the build frame
		get_tree().process_frame.connect(_fit_view, CONNECT_ONE_SHOT | CONNECT_DEFERRED)


# Coalesced like GraphUI's: a box select fires node_selected once per node.
func _queue_activity() -> void:
	if _activity_queued:
		return
	_activity_queued = true
	(func():
		_activity_queued = false
		DepGraphUI.highlight_selected_connections(self)).call_deferred()


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


func _on_zoom_or_scroll(_offset:Vector2) -> void:
	_update_detail()
	DepGraphUI.apply_zoom_line_thickness(self)


func _update_detail() -> void:
	var detailed = zoom >= DETAIL_ZOOM
	if detailed == _detailed:
		return
	_detailed = detailed
	for node in _nodes.values():
		if node.canvas != null:
			node.canvas.set_detailed(detailed)


## Tree mode: a column per BFS layer. Show All Edges: a left-to-right flow over every drawn edge
## (PackageGraph.flow_columns), reordered by barycenter sweeps with roomier rows.
func _layout() -> void:
	var scale = EditorInterface.get_editor_scale()
	var flow = show_all_edges
	var col_of = PackageGraph.flow_columns(_data, _drawn) if flow else {}
	var by_col = {}
	for id in _data.nodes:
		var col:int = col_of[id] if flow else _data.nodes[id].layer
		if not by_col.has(col):
			by_col[col] = []
		by_col[col].append(id)
	var keys = by_col.keys()
	keys.sort()
	var columns:Array = keys.map(func(k): return by_col[k])
	_order_by_tree_parent(columns)
	if flow:
		_order_by_barycenter(columns)

	var v_space = (FLOW_V_GAP if flow else v_gap) * scale
	var widths:Array[float] = []
	var heights:Array[float] = []
	for ids in columns:
		var width = 0.0
		var height = v_space * maxi(ids.size() - 1, 0)
		for id in ids:
			var min_size = _nodes[id].get_combined_minimum_size()
			width = maxf(width, min_size.x)
			height += min_size.y
		widths.append(width)
		heights.append(height)

	var h_space = COLUMN_GAP * scale
	if columns.size() > 1 and size.y > 0.0:
		var total_width = widths.reduce(func(acc, w): return acc + w, 0.0)
		var fill = (heights.max() * size.x / size.y - total_width) / (columns.size() - 1)
		h_space = clampf(fill, COLUMN_GAP * scale, COLUMN_GAP_MAX * scale)

	var x = 0.0
	for c in columns.size():
		var y = -heights[c] * 0.5
		for id in columns[c]:
			_nodes[id].position_offset = Vector2(x, y)
			y += _nodes[id].get_combined_minimum_size().y + v_space
		x += widths[c] + h_space


# Within a column, follow the tree parent's row so tree edges cross least; ties by name.
func _order_by_tree_parent(columns:Array) -> void:
	var parent_of = {}
	for edge in _data.edges:
		if edge.tree:
			parent_of[edge.to] = edge.from
	var row_of = {}
	for ids in columns:
		ids.sort_custom(func(a, b):
			var ra = row_of.get(parent_of.get(a, ""), -1)
			var rb = row_of.get(parent_of.get(b, ""), -1)
			return ra < rb if ra != rb else _data.nodes[a].name < _data.nodes[b].name)
		for r in ids.size():
			row_of[ids[r]] = r


# Alternating sweeps: sort each column by the mean position of its neighbours in the column just
# fixed - predecessors going right, successors going left. Positions are normalised to 0..1, so
# columns of different heights compare; a node with no such neighbours keeps its slot.
func _order_by_barycenter(columns:Array) -> void:
	var preds = {}
	var succs = {}
	for edge in _drawn:
		_append(preds, edge.to, edge.from)
		_append(succs, edge.from, edge.to)
	var pos = {}
	for ids in columns:
		_record_positions(ids, pos)
	for sweep in FLOW_SWEEPS:
		var forward = sweep % 2 == 0
		var neighbours = preds if forward else succs
		var order = range(1, columns.size()) if forward else range(columns.size() - 2, -1, -1)
		for c in order:
			var ids:Array = columns[c]
			var key = {}
			for id in ids:
				var near = neighbours.get(id, []).filter(func(n): return pos.has(n))
				if near.is_empty():
					key[id] = pos[id]
				else:
					key[id] = near.reduce(func(acc, n): return acc + pos[n], 0.0) / near.size()
			ids.sort_custom(func(a, b): return key[a] < key[b] if key[a] != key[b] else pos[a] < pos[b])
			_record_positions(ids, pos)


static func _append(map:Dictionary, key:String, value:String) -> void:
	if not map.has(key):
		map[key] = []
	map[key].append(value)


static func _record_positions(ids:Array, pos:Dictionary) -> void:
	for r in ids.size():
		pos[ids[r]] = (r + 0.5) / ids.size()


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
	DepGraphUI.apply_zoom_line_thickness(self)


class PackageNode extends GraphNode:
	var dir:String = ""
	var clicks:ClickCallback
	var canvas:FileCanvas
	## slot -> port index. GraphEdit numbers ports per side over enabled slots only.
	var in_port_of:Dictionary = {}
	var out_port_of:Dictionary = {}

	func setup(node:Dictionary, is_root:bool, new_count:int, in_slots:Dictionary, out_slots:Dictionary, required_by:Array) -> void:
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
		var info = _row(_requires_text(node, new_count))
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

	## "new" are the requires this package brought into the graph; the rest were placed earlier.
	static func _requires_text(node:Dictionary, new_count:int) -> String:
		if not node.resolved:
			return "not in project"
		var count = node.requires.size()
		return "Requires: %d (%d new)" % [count, new_count] if count > 0 else "Requires: 0"

	static func _version_text(node:Dictionary) -> String:
		var tag = node.declared_tag
		var local = ("v" + node.local_version.trim_prefix("v")) if node.local_version != "" else ""
		if tag == "":
			return local if local != "" else "-"
		if local == "" or PackageGraph.version_state(node) == 0:
			return tag
		return "%s  (local %s)" % [tag, local]

	func _gui_input(event:InputEvent) -> void:
		if clicks != null and dir != "":
			clicks.handle_input(event, [dir], self)


## The files a package contributes, drawn rather than built from Controls: a node can carry
## hundreds, and at low zoom they collapse to coloured blocks. Long lists stop at MAX_ROWS
## behind a "+N more" row that toggles the rest.
class FileCanvas extends Control:
	signal expanded_changed

	const MAX_ROWS = 30
	const ROW_HEIGHT = 18.0
	const EXT_COLORS = {"gd": Color("6aa9e3"), "cs": Color("8fc97a"), "tscn": Color("c792ea"),
		"tres": Color("d9b35a"), "md": Color("8a8f94")}
	const OTHER_COLOR = Color("a0a4a8")

	var files:Array = []
	var clicks:ClickCallback
	var expanded:bool = false:
		set(value):
			expanded = value
			_update_size()
	var _detailed:bool = true
	var _hover_row:int = -1
	## Held while the right-click menu is open, which takes the mouse off the canvas.
	var _pinned_row:int = -1

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_PASS # clicks still reach the node, so it drags from here too
		mouse_exited.connect(_set_hover.bind(-1))

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
		if _detailed:
			var accent = get_theme_color(&"accent_color", &"Editor")
			for row in [_hover_row, _pinned_row]:
				if row >= 0 and row < _shown():
					var alpha = 0.32 if row == _pinned_row else 0.18
					draw_rect(Rect2(0.0, row * row_h, size.x, row_h), Color(accent, alpha))
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
		if event is InputEventMouseMotion:
			var at = _row_at(event.position)
			_set_hover(at if at < _shown() else -1)
			return
		if not event is InputEventMouseButton:
			return
		var row = _row_at(event.position)
		if row < 0:
			return
		if row == _shown() and _has_more():
			if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				expanded = not expanded
				expanded_changed.emit()
				accept_event()
		elif row < _shown() and clicks != null:
			if event.pressed and event.button_index == MOUSE_BUTTON_RIGHT \
					and clicks.has_slot(ClickCallback.State.RMB_PRESSED):
				_pin(row)
			clicks.handle_input(event, [files[row]], self)

	# Reaching another row means the menu is gone; the same row may just be the way to the menu.
	func _set_hover(row:int) -> void:
		var unpin = _pinned_row >= 0 and row >= 0 and row != _pinned_row
		if row == _hover_row and not unpin:
			return
		_hover_row = row
		if unpin:
			_pinned_row = -1
		queue_redraw()

	# The menu is its own window: closing it hands focus back to ours.
	func _pin(row:int) -> void:
		_pinned_row = row
		var window = get_window()
		if not window.focus_entered.is_connected(_unpin):
			window.focus_entered.connect(_unpin, CONNECT_ONE_SHOT)
		queue_redraw()

	func _unpin() -> void:
		_pinned_row = -1
		queue_redraw()

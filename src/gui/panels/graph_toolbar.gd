## Trims a GraphEdit's built-in toolbar to Zoom Out / Zoom In plus a tools button, and fills that
## button's menu with the shared graph items. Kept out of dep_map, which builds no menus itself.

const UtilsRemote = preload("res://addons/gdpackage/src/class/utils_remote.gd")
const Options = UtilsRemote.Options

## Returns the tools button; the host connects `pressed` to its own popup.
static func setup(graph:GraphEdit) -> Button:
	graph.show_zoom_label = false
	graph.show_grid_buttons = false
	graph.show_minimap_button = false
	graph.show_arrange_button = false
	# the theme icon is only there once the graph enters the tree
	if graph.is_inside_tree():
		_hide_zoom_reset(graph)
	else:
		graph.ready.connect(_hide_zoom_reset.bind(graph), CONNECT_ONE_SHOT)

	var button = Button.new()
	button.theme_type_variation = &"FlatButton"
	button.tooltip_text = "Graph Options"
	button.icon = EditorInterface.get_editor_theme().get_icon(&"Tools", &"EditorIcons")
	graph.get_menu_hbox().add_child(button)
	return button

static func add_graph_options(options:Options, graph:GraphEdit, reset_layout:Callable) -> void:
	options.add_separator()
	var minimap_label = "Hide Minimap" if graph.minimap_enabled else "Show Minimap"
	options.add_option(minimap_label, func(): graph.minimap_enabled = not graph.minimap_enabled)
	options.add_option("Reset Layout", reset_layout)
	options.add_option("Reset Zoom", func(): graph.zoom = 1.0) # zooms about the centre, like the built-in

# The menu children are internal and unnamed, and the tooltip is translated, so match the icon.
# GraphEdit only touches this button again through show_zoom_buttons.
static func _hide_zoom_reset(graph:GraphEdit) -> void:
	var reset_icon = graph.get_theme_icon(&"zoom_reset")
	for child in graph.get_menu_hbox().get_children(true):
		if child is Button and child.icon == reset_icon:
			child.hide()
			return

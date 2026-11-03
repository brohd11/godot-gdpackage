extends VBoxContainer
## Renders one parsed markdown doc as a flow of controls - RichTextLabel for prose, read-only
## CodeEdit for fences, TextureRect for standalone images.
##
## Every size comes from the theme rather than a constant, and the doc re-renders on a theme
## change, so the view tracks the editor's font size and scale instead of fighting them.
## Engine-only and host-agnostic: links are reported, never resolved here.

const Parser = preload("res://addons/gdpackage/src/components/doc_viewer/markdown_parser.gd")

const _FALLBACK_FONT_SIZE = 16
## Images are held to a fraction of the viewport height so a screenshot cannot fill the page.
## Width needs no ratio - an image is never allowed past the width of the view itself.
const _MAX_IMAGE_HEIGHT_RATIO = 0.6

signal link_activated(meta:String)

## Optional (lang:String) -> SyntaxHighlighter. Without it, gdscript fences use the built-in
## highlighter and everything else renders plain, which keeps this view dependency free.
var highlighter_provider:Callable

## Directory relative image paths resolve against.
var base_dir:String = ""

var _source:String = ""
var _prose_style:StyleBoxEmpty
var _rendering:bool = false


func _init() -> void:
	_prose_style = StyleBoxEmpty.new()


func _notification(what:int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and is_node_ready() and _source != "":
		_render()
	elif what == NOTIFICATION_RESIZED:
		_fit_images()


func set_markdown(text:String) -> void:
	_source = text
	_render()


func set_file(path:String) -> void:
	base_dir = path.get_base_dir()
	set_markdown(FileAccess.get_file_as_string(path))


func clear() -> void:
	_source = ""
	_clear_children()


func _clear_children() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()


func _render() -> void:
	# clear() re-emits theme changes as children leave, which would land back here.
	if _rendering:
		return
	_rendering = true
	_clear_children()

	var base_font_size = _base_font_size()
	add_theme_constant_override("separation", maxi(4, base_font_size / 2))

	for block in Parser.parse(_source):
		match block.get(Parser.KEY_TYPE):
			Parser.TYPE_TEXT:
				add_child(_new_prose(block[Parser.KEY_TEXT], base_font_size))
			Parser.TYPE_CODE:
				add_child(_new_code(block[Parser.KEY_TEXT], block[Parser.KEY_LANG]))
			Parser.TYPE_IMAGE:
				add_child(_new_image(block[Parser.KEY_SRC], block[Parser.KEY_ALT]))
			Parser.TYPE_RULE:
				add_child(HSeparator.new())
	_rendering = false


## The theme's own size, so headings scale with the editor instead of a hardcoded pixel size.
func _base_font_size() -> int:
	var size = get_theme_default_font_size()
	return size if size > 0 else _FALLBACK_FONT_SIZE


func _new_prose(text:String, base_font_size:int) -> RichTextLabel:
	var label = RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.selection_enabled = true
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_stylebox_override("normal", _prose_style)
	label.text = Parser.to_bbcode(text, base_font_size)
	label.meta_clicked.connect(_on_meta_clicked)
	return label


func _new_code(text:String, lang:String) -> Control:
	var wrapper = PanelContainer.new()
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var code_edit = CodeEdit.new()
	wrapper.add_child(code_edit)
	code_edit.text = text
	code_edit.editable = false
	code_edit.focus_mode = Control.FOCUS_CLICK
	code_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	code_edit.scroll_fit_content_height = true
	code_edit.context_menu_enabled = false
	# Theme lookups only resolve once the node is in the tree, so the readonly dim is undone there.
	code_edit.ready.connect(_undim_readonly.bind(code_edit))
	var highlighter = _get_highlighter(lang)
	if highlighter != null:
		code_edit.syntax_highlighter = highlighter

	var copy_button = Button.new()
	code_edit.add_child(copy_button)
	# Editor icon where there is an editor theme to take one from, a label everywhere else.
	if Engine.is_editor_hint():
		copy_button.icon = EditorInterface.get_editor_theme().get_icon(&"ActionCopy", &"EditorIcons")
	else:
		copy_button.text = "Copy"
	copy_button.theme_type_variation = &"FlatButton"
	copy_button.flat = true
	copy_button.focus_mode = Control.FOCUS_NONE
	copy_button.set_anchors_and_offsets_preset.call_deferred(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE)
	copy_button.pressed.connect(DisplayServer.clipboard_set.bind(text))

	return wrapper


func _undim_readonly(code_edit:CodeEdit) -> void:
	code_edit.add_theme_color_override(&"font_readonly_color", Color.WHITE)#code_edit.get_theme_color(&"font_color", &"CodeEdit"))


func _get_highlighter(lang:String):
	if highlighter_provider.is_valid():
		return highlighter_provider.call(lang)
	# The built-in highlighter is an editor class, so it is not always there to instantiate.
	if lang in ["", "gd", "gdscript"] and ClassDB.can_instantiate("GDScriptSyntaxHighlighter"):
		return GDScriptSyntaxHighlighter.new()
	return null


func _new_image(src:String, alt:String) -> Control:
	var path = src
	if not path.contains("://") and base_dir != "":
		path = base_dir.path_join(path).simplify_path()

	var texture = _load_texture(path)
	if texture == null:
		var label = Label.new()
		label.text = alt if alt != "" else src
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		return label

	var rect = TextureRect.new()
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	rect.tooltip_text = alt
	# Natural size for now; the first real layout fits it to the width actually available.
	rect.custom_minimum_size = Vector2(texture.get_size())
	return rect


## Imported images go through the loader - reading one off disk instead works but warns that it
## will not survive an export. Docs shipped in a dot-prefixed folder are never imported, and raw
## file data is the only way to reach those.
func _load_texture(path:String) -> Texture2D:
	if not FileAccess.file_exists(path):
		return null
	if ResourceLoader.exists(path):
		var resource = ResourceLoader.load(path)
		if resource is Texture2D:
			return resource
	var image = Image.load_from_file(path)
	if image == null or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)


## Images are sized on layout, not on build - at build time the view has no width yet, and a
## window that has not been popped up reports a placeholder size that shrinks every image to it.
func _fit_images() -> void:
	for child in get_children():
		if child is TextureRect:
			_fit_image(child)


func _fit_image(rect:TextureRect) -> void:
	if rect.texture == null:
		return
	var natural = Vector2(rect.texture.get_size())
	if natural.x <= 0 or natural.y <= 0:
		return

	var factor := 1.0
	if size.x > 0:
		factor = minf(factor, size.x / natural.x)
	var max_height = get_viewport_rect().size.y * _MAX_IMAGE_HEIGHT_RATIO
	if max_height > 0:
		factor = minf(factor, max_height / natural.y)
	# custom_minimum_size ignores an unchanged value, so this cannot feed itself another resize.
	rect.custom_minimum_size = natural * minf(factor, 1.0)


func _on_meta_clicked(meta:Variant) -> void:
	link_activated.emit(str(meta))

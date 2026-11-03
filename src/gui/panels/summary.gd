extends ScrollContainer

const UtilsRemote = preload("res://addons/gdpackage/src/class/utils_remote.gd")
const Options = UtilsRemote.Options

const UtilsLocal = preload("res://addons/gdpackage/src/class/utils_local.gd")
const PluginExporterStatic = UtilsLocal.PluginExporterStatic
const ExportData = UtilsLocal.ExportData
const Export = ExportData.Export

var _label_sb:StyleBoxEmpty

var _main_vbox:VBoxContainer

func _init() -> void:
	name = "Summary"
	_label_sb = StyleBoxEmpty.new()
	_label_sb.content_margin_left = 4 * EditorInterface.get_editor_scale()
	_label_sb.content_margin_right = 4 * EditorInterface.get_editor_scale()

func _ready() -> void:
	_main_vbox = VBoxContainer.new()
	add_child(_main_vbox)

func set_export_data(export_data:ExportData):
	_clear_current()
	if not export_data.data_valid:
		_new_line("Data invalid")
		return
	_new_line("Export Root: %s" % [export_data.export_root])
	_new_line("Exports: %s" % export_data.exports.size())
	_new_line("Include Import: %s" % export_data.include_import)
	_new_line("Include UID: %s" % export_data.include_uid)
	_new_line("Full Export Dir: %s" % export_data.full_export_path)
	
	for i in range(export_data.exports.size()):
		_main_vbox.add_child(HSeparator.new())
		var e:Export = export_data.exports[i]
		_new_line("Export %s" % i)
		_new_line("Source: %s" % e.source)
		_new_line("Files Count: %s" % e.files_to_copy.size())
		_new_line("Remote Dir: %s" % e.remote_dir)
		


func clear():
	_clear_current()

func _clear_current():
	for c in _main_vbox.get_children():
		_main_vbox.remove_child(c)
		c.queue_free()

func _new_line(text:String):
	var label = Label.new()
	_main_vbox.add_child(label)
	label.add_theme_stylebox_override("normal", _label_sb)
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func get_options() -> Options:
	var options = Options.new()
	return options

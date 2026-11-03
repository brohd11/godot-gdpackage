extends GDPackage.UtilsRemote.TreeHelperBase

const UtilsRemote = preload("res://addons/gdpackage/src/class/utils_remote.gd")

func _set_folder_icon_img():
	folder_icon = EditorInterface.get_base_control().get_theme_icon("Folder", &"EditorIcons")
	folder_color = EditorInterface.get_base_control().get_theme_color("folder_icon_color", "FileDialog")

func _set_folder_icon(file_path, slice_item):
	slice_item.set_icon(0, folder_icon)
	slice_item.set_icon_modulate(0, folder_color)


func _set_item_icon(last_item:TreeItem, file_data):
	var icon = file_data.get("File Icon")
	if icon:
		last_item.set_icon(0, icon)
		last_item.set_icon_modulate(0, Color.WHITE)
	

func _mouse_left_clicked():
	mouse_left_clicked.emit()

func _mouse_right_clicked(data):
	mouse_right_clicked.emit()

func _mouse_double_clicked():
	mouse_double_clicked.emit()

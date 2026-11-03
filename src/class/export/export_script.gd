@tool
extends Node
## Base for a config's pre_script / post_script: `extends GDPackage.ExportScript`.
## _configure runs before pre_export / post_export; override it to pull more from ExportData.

const ExportData = preload("res://addons/gdpackage/src/class/export/export_data.gd")

var export_path:String

func _configure(export_data:ExportData) -> void:
	export_path = export_data.full_export_path

func pre_export() -> void:
	pass

func post_export() -> void:
	pass

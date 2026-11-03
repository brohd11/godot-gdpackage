extends Node

const _ContextBackport = preload("res://addons/gdpackage/src/class/export/backport/context/context_backport.gd")


func _popup_menu(paths: PackedStringArray) -> void: # give node path to desired node from root
	
	pass


func add_context_menu_item(_name, callback, icon=null):
	_ContextBackport.get_instance().add_popup_item(self, _name, callback, icon)

func add_context_submenu_item(_name, submenu, icon=null):
	_ContextBackport.get_instance().add_popup_submenu(self, _name, submenu, icon)

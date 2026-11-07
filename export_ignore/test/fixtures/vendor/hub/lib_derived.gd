extends "res://addons/gdpackage/export_ignore/test/fixtures/vendor/hub/lib_base.gd"


static func ping() -> int:
	return KeptHub.ping() + Leaf.VALUE

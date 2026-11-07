extends RefCounted
## Reaches only through its own hub, so the export should need neither the hub nor its siblings.

const LibHub = preload("res://addons/gdpackage/export_ignore/test/fixtures/vendor/hub/lib_hub.gd")
const Leaf = LibHub.Leaf


static func total() -> int:
	return Leaf.value() + LibHub.Leaf.VALUE

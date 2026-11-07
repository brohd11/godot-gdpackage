extends RefCounted
## Every mention of KeptHub here reduces, but lib_derived.gd inherits it and still calls through
## it, so this declaration has to survive what looks like a pass-through.

const KeptHub = preload("res://addons/gdpackage/export_ignore/test/fixtures/vendor/hub/lib_kept_hub.gd")
const Leaf = KeptHub.Leaf

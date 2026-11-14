# Shipping documentation

With `options.include_docs` on (the default), the `doc` folder beside your `export.yml` is copied
into the exported plugin as `.doc`, structure intact. Nothing in it is parsed or crawled for
dependencies, it is copied verbatim, and no `.uid`/`.import` sidecars come along. The dot prefix
keeps Godot from importing the folder, so it never reaches a game export.

The `DocViewer` component renders those docs. Preload it from GDPackage so the exporter
gathers it into your package. Provide an entry point, such as a button or menu item,
and the addon directory to read from:

``` gdscript
const DocViewer = preload("res://addons/gdpackage/src/components/doc_viewer/doc_viewer.gd")

func _on_help_pressed() -> void:
	DocViewer.open("res://addons/my_plugin/")
```

`open()` puts the viewer in its own window that frees itself when closed. To embed it instead,
instance it as a normal Control and set `docs_path`.

It resolves a directory itself: `<addon>/.doc` in a released plugin,
`<addon>/_export_ignore/doc` or `<addon>/export_ignore/doc` in a development checkout
(in that order), or the plugin's `README.md` when there is no doc folder at all. Docs are listed
depth first, files before folders, on a contents page, with navigation between them.

Give it a **file** instead and that file is the whole viewer - nothing is scanned or guessed at,
and the contents page and navigation stay out of the way:

``` gdscript
DocViewer.open("res://addons/my_plugin/README.md")   # window on one file
viewer.display("res://addons/my_plugin/README.md")   # same, on an embedded instance
```

Links follow through: a doc in the contents opens as a page, a `.md` outside it opens too (the
Contents button goes back), a `res://` file is revealed in the FileSystem dock, and anything else
is handed to the OS.

Markdown support covers headings, emphasis, lists, quotes, links, rules, images and fenced code.
Code fences render as read-only `CodeEdit`s - gdscript is highlighted out of the box, and
`highlighter_provider` takes a `(lang:String) -> SyntaxHighlighter` callable for anything else.
Heading sizes are ratios of the editor's own font size, so the whole view follows the editor scale.

Use relative links between documentation files so they continue to work after the
folder is copied to `.doc`. See [Export settings](export_settings.md#options) for the
packaging option, and [Setup](setup.md) for export configuration locations.

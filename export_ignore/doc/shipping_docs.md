# Shipping documentation

With `options.include_docs` on (the default), the `doc` folder beside `export.yml` is copied into the exported plugin as `.doc`, structure intact.

- The files are copied verbatim: nothing is parsed or crawled for dependencies, and no `.uid`/`.import` sidecars come along.
- The dot prefix keeps Godot from importing the folder, so it never reaches a game export.
- Use relative links between doc files so they keep working after the copy.

## DocViewer

The `DocViewer` component renders those docs. Preload it from GDPackage so the exporter gathers it into the package, then give it an entry point (a button, a menu item) and the addon directory to read from:

``` gdscript
const DocViewer = preload("res://addons/gdpackage/src/components/doc_viewer/doc_viewer.gd")

func _on_help_pressed() -> void:
	DocViewer.open("res://addons/my_plugin/")
```

`open()` puts the viewer in its own window, which frees itself when closed. To embed it instead, instance it as a normal Control and set `docs_path`.

### Tools menu

To skip building an entry point, register the plugin under **Project > Tools > Docs** instead:

``` gdscript
func _enter_tree() -> void:
	DocViewer.register("My Plugin", "res://addons/my_plugin/")

func _exit_tree() -> void:
	DocViewer.unregister("My Plugin")
```

- The `Docs` submenu is created by the first plugin to register and removed with the last.
- Every registered plugin shares one window, a tab each. Picking a plugin whose docs are already open focuses its tab.
- The name is the menu item and the tab title, so it has to be unique among plugins.

### Finding the docs

Given a directory, it looks for docs in this order:

1. `<addon>/.doc` - a released plugin
2. `<addon>/_export_ignore/doc`, then `<addon>/export_ignore/doc` - a development checkout
3. the plugin's `README.md` - when there is no doc folder

Docs are listed depth first, files before folders, on a contents page with navigation between them.

Given a **file**, that file is the whole viewer. Nothing is scanned, and there is no contents page or navigation:

``` gdscript
DocViewer.open("res://addons/my_plugin/README.md")   # window on one file
viewer.display("res://addons/my_plugin/README.md")   # same, on an embedded instance
```

Links:

- A doc in the contents opens as a page.
- A `.md` outside the contents opens too; the Contents button goes back.
- A `res://` file is revealed in the FileSystem dock.
- Anything else is handed to the OS.

Markdown:

- Headings, emphasis, strikethrough, nested and task lists, tables, quotes and `> [!NOTE]` alerts, links (inline, reference, bare URLs), rules, images and fenced code are supported. Raw HTML is shown as text.
- A link's `#heading-id` scrolls to that heading, in the same doc or another. Ids follow GitHub's rule: lowercase, punctuation dropped, spaces to hyphens.
- Inline code, links, quotes and table headers take their colors from the editor theme, including its accent color.
- Code fences render as read-only `CodeEdit`s. GDScript is highlighted out of the box; `highlighter_provider` takes a `(lang:String) -> SyntaxHighlighter` callable for anything else.
- Heading sizes are ratios of the editor's font size, so the view follows the editor scale.

See [Export settings](export_settings.md#options) for the packaging option.

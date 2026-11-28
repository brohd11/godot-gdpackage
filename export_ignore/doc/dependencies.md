# Dependencies and tags

Develop against shared scripts and global classes. On export, the files a package uses are copied into it and their references rewritten. For tagged package requirements, see [Releases](releases.md).

## Automatic dependencies

Every exportable source file is scanned for references, and each dependency found is scanned in turn. Preloads, inheritance, global classes, and scene/resource references are gathered.

Global classes can be used normally during development. On export, `class_name` declarations are removed and preloads are added to the scripts using them. Use `options.parser_settings.parse_gd.class_rename_ignore` to keep selected classes global. See [Export settings](export_settings.md#parse_gd).

Each export gets its own copies of shared classes, so static libraries and self contained classes work well.

The [pseudo-namespace](https://github.com/brohd11/Godot-Pseudo-Namespace) plugin can organize scripts into a hierarchy. The exporter can reduce those dotted access paths to direct preloads, see [Parser settings](export_settings.md#parse_gd).

## Manual dependencies

Files that can't be preloaded are declared with the `#! gdp-dependency` tag on a path string. An optional destination after the tag sets where the file goes in the export:

``` gdscript
const MY_FILE = "res://some_other/folder/non-resource.file" #! gdp-dependency
const MY_CUST_FILE = "res://file.file" #! gdp-dependency res://addons/my_plugin/deps/renamed.file
const FONT_LICENSE = "res://some_library/font.LICENSE.txt" #! gdp-dependency <package>/licenses/font/LICENSE
```

| Destination | Placement |
| --- | --- |
| `licenses/font/LICENSE` or `./licenses/font/LICENSE` | Named `LICENSE` below the declaring file's exported directory |
| `../licenses/font/LICENSE` | Relative to the parent of that directory |
| `current` or `.` | Original filename beside the exported declaring file |
| `<package>/licenses/font/LICENSE` | Named `LICENSE` below the active export's source root, then converted and renamed |
| `res://addons/my_plugin/licenses/font/LICENSE` | Absolute file path within the active export's source folder |
| Omitted | Default remote placement |

- A destination is a complete file path. One ending in `/` is rejected.
- The export fails before copying on an absolute destination outside the active source folder, a relative destination escaping the exported plugin, or a cycle of relative placements.
- Shared libraries should use `<package>/` for package-root assets, so they work in every plugin that uses them.

## Tags

A tag has the form `#! tag value` or `#! tag mods; args`, and has to open its comment. gdpackage's own tags carry the `gdp-` prefix.

- `#! gdp-dependency` - gathers a literal path, including `load()` targets and non-resource files such as config or JSON. See [Manual dependencies](#manual-dependencies).
- `#! gdp-ignore` - skips dependency gathering and path rewriting for references on this line, including global-class and access-path discovery. Another untagged reference can still gather the dependency. There is no file-wide form.
- `#! gdp-replace` - replaces an extending stub with its base script. See [Replace stub](#replace-stub).
- `#! gdp-strip-cast A, B` - strips type casts to the listed names (`: A`, `-> A`, `as A`) anywhere in the file. See [Strip casts](#strip-casts).
- `#! gdp-skip-parse` - within the first 10 lines: the file is copied untouched, its dependencies aren't gathered, and the release compile check doesn't load it.
- `#! struct` and `#! inline` - optimizer tags, owned by the shared GDScript optimizer. See [Optimization](optimization.md).

Custom parsers under `gdpackage/src/class/export/parse/<extension>` can handle additional tags. Pass their settings through `options.parser_settings` in `export.yml`, see [Export settings](export_settings.md#parser_settings).

---

## Replace stub

Places an external script at a chosen location in the export, using an extending stub:

``` gdscript
#! gdp-replace
extends "res://some_other/folder/my_class.gd"
```

- On export, the base script replaces the stub and its dependencies are gathered.
- `#! gdp-replace` must be within the first 10 lines.
- Changes made in the stub are lost on replacement. Put custom behavior in a separate script that extends it.
- The tag only enables replacement. Ordinary dependencies, including preload hubs, are gathered without it.
- During development the stub is a subclass of the external script, with its own script identity. Use a preload hub to reference the external script directly.

## Strip casts

Each export gets its own copy of a singleton module, and at runtime another plugin's copy may be the live instance. A cast to this export's copy would then fail, so those casts are removed on export:

- Global classes that extend a singleton base are stripped everywhere, automatically.
- Anything else is named with `#! gdp-strip-cast`, in each file that casts to it. A singleton's self const is the usual case:

``` gdscript
#! gdp-strip-cast PE_STRIP_CAST_SCRIPT
const PE_STRIP_CAST_SCRIPT = preload("res://addons/my_plugin/my_singleton.gd")

static func get_instance() -> PE_STRIP_CAST_SCRIPT:
	return _get_instance(PE_STRIP_CAST_SCRIPT)
```

- A dotted type (`Head.Inner`) is stripped through its head's name, even after `reduce_access_paths` rewrites it to a binding.

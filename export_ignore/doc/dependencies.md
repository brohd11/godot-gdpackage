# Dependencies and tags

Develop against shared scripts and global classes. On export, the files a package uses are copied into it and their references rewritten. For tagged package requirements, see [Releases](releases.md).

## Automatic dependencies

Every exportable source file is scanned for references, and each dependency found is scanned in turn. Preloads, inheritance, global classes, and scene/resource references are gathered.

Global classes can be used normally during development. On export, `class_name` declarations are removed and preloads are added to the scripts using them. Use `options.parser_settings.parse_gd.class_rename_ignore` to keep selected classes global. See [Export settings](export_settings.md#parse_gd).

Each export gets its own copies of shared classes, so static libraries and self contained classes work well.

The [pseudo-namespace](https://github.com/brohd11/Godot-Pseudo-Namespace) plugin can organize scripts into a hierarchy. The exporter can reduce those dotted access paths to direct preloads, see [Parser settings](export_settings.md#parse_gd).

## Manual dependencies

Files that can't be preloaded are declared with the `#! dependency` tag on a path string. An optional destination after the tag sets where the file goes in the export:

``` gdscript
const MY_FILE = "res://some_other/folder/non-resource.file" #! dependency
const MY_CUST_FILE = "res://file.file" #! dependency res://addons/my_plugin/deps/renamed.file
const FONT_LICENSE = "res://some_library/font.LICENSE.txt" #! dependency <package>/licenses/font/LICENSE
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

A tag has the form `#! tag value` or `#! tag mods; args`, and has to open its comment.

- `#! dependency` - gathers a literal path, including `load()` targets and non-resource files such as config or JSON. See [Manual dependencies](#manual-dependencies).
- `#! ignore-remote` - skips dependency gathering and path rewriting for references on this line, including global-class and access-path discovery. Another untagged reference can still gather the dependency. There is no file-wide form.
- `#! struct` and `#! inline` - opt definitions into the optimizer passes. See [Optimization](optimization.md).
- `#! remote` - replaces an extending stub with its base script. See [Remote Class](#remote-class---deprecated).

Custom parsers under `gdpackage/src/class/export/parse/<extension>` can handle additional tags. Pass their settings through `options.parser_settings` in `export.yml`, see [Export settings](export_settings.md#parser_settings).

---

## Remote Class - **Deprecated**

Places an external script at a chosen location in the export, using an extending stub:

``` gdscript
#! remote
extends "res://some_other/folder/my_class.gd"
```

- On export, the base script replaces the stub and its dependencies are gathered.
- `#! remote` must be within the first 10 lines.
- Changes made in the stub are lost on replacement. Put custom behavior in a separate script that extends it.
- The tag only enables replacement. Ordinary dependencies are gathered without it, and a tag on a file with no replaceable base is harmless.
- During development the stub is a subclass of the external script, with its own script identity. Use a preload hub to reference the external script directly.

# Dependencies and tags

Develop against shared scripts and global classes; GDPackage gathers and rewrites
their references for each exported package. For tagged package requirements, see
[Releases](releases.md).

## Automatic dependencies

Every exportable source file is scanned for references, and each discovered dependency is scanned
in turn. Preloads, inheritance, global classes, and scene/resource references are gathered.

You can use global classes normally during development. On export, `class_name` declarations are removed and are 
preloads added to the scripts using them. Use `options.parser_settings.parse_gd.class_rename_ignore`
to keep selected public classes global. See [Export settings](export_settings.md#parse_gd).

Each export gets its own copies of shared classes. So static libraries or self contained classes work well.

## Manual dependencies

You can also declare files as dependencies if they are not preloadable using the tag: `#! dependency`.
You can follow that up with a path to redirect where the file will go during export, the tag alone keeps the derived path:

| Destination | Placement |
| --- | --- |
| `licenses/font/LICENSE` or `./licenses/font/LICENSE` | Named `LICENSE` below the declaring file's exported directory |
| `../licenses/font/LICENSE` | Relative to the parent of that directory |
| `current` or `.` | Original filename beside the exported declaring file |
| `<package>/licenses/font/LICENSE` | Named `LICENSE` below the active export's source root, then converted and renamed |
| `res://addons/my_plugin/licenses/font/LICENSE` | Absolute file path within the active export's source folder |
| Omitted | Default remote placement |

An absolute destination outside the active source folder, a relative destination escaping the
exported plugin, or a cycle of relative placements fails the export before copying. Shared
libraries should use `<package>/` for package-root assets so they work in every consuming plugin.
These rules affect the destination argument only; dependency source literals resolve as before.
Directory-only forms ending in `/` are rejected. Existing explicit directory destinations must
have the intended filename appended; the exporter no longer appends it automatically.

``` gdscript
const MY_FILE = "res://some_other/folder/non-resource.file" #! dependency
const MY_CUST_FILE = "res://file.file" #! dependency res://addons/my_plugin/deps/renamed.file
const FONT_LICENSE = "res://some_library/font.LICENSE.txt" #! dependency <package>/licenses/font/LICENSE
```

## Tags

A tag has the form `#! tag value` or `#! tag mods; args`, and has to open its comment.

- `#! remote`: replace an extending stub with its base script, as shown above.
- `#! ignore-remote`: skip dependency gathering and path rewriting for references on
  this line, including global-class and access-path discovery. Another untagged reference
  can still gather the dependency. A standalone header tag does not opt out the whole file.
- `#! dependency`: gather a literal path, including `load()` targets and non-resource
  files such as config or JSON. Its optional destination is a complete file path,
  `current`, or `.`, as shown in the placement table above.
- `#! struct` and `#! inline`: opt definitions into the configured optimizer passes.
  See [Optimization](optimization.md).

Custom parsers under `gdpackage/src/class/export/parse/<extension>` can handle
additional tags. Pass their settings through `options.parser_settings` in `export.yml`;
see [Export settings](export_settings.md#parser_settings).

---

## Remote Class - **Deprecated** 

Place an external script at a chosen location in the export with an extending stub:

``` gdscript
#! remote
extends "res://some_other/folder/my_class.gd"
```

On export, the base script replaces the stub, and its dependencies are gathered.
Put `#! remote` within the first 10 lines. Changes made in the stub are lost during
replacement; put custom behavior in a separate script that extends it.

`#! remote` only enables replacement. Ordinary dependencies are gathered without it;
existing tags on files without a replaceable base are harmless.

During development the stub is a subclass of the external script, with its own script
identity. Use a preload hub when you need to reference the external script directly.



On export, the files are copied into your plugin and their paths adjusted. The
[pseudo-namespace](https://github.com/brohd11/Godot-Pseudo-Namespace) plugin can organize
scripts into a hierarchy. The exporter can reduce dotted access paths to direct
preloads; see [Parser settings](export_settings.md#parse_gd).



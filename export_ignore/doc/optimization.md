# Optimization and compatibility

## GDScript optimization

Exports run the shared GDScript optimizer before packaging rewrites when enabled.
New `export.yml` files explicitly set `options.parser_settings.parse_gd.optimizer.enabled`
to `false`. Set it to `true` to optimize tagged `#! struct` classes and `#! inline`
static functions. Existing configs that omit the optimizer block default to enabled.

Structs run before inlining, with scalar replacement and typed field reads included.
Reference types remain opt-in through `aggressive`. Disable the optimizer for an
unoptimized baseline, or override individual settings in an export entry's
`parser_overide_settings.parse_gd.optimizer` mapping.
See [Optimizer settings](export_settings.md#gdscript-optimizer) for the configuration.

## Structs

A class tagged `#! struct` is written like any data class, but exports as a plain Array, which
skips object allocation and property lookup.

``` gdscript
#! struct
class Hit:
	var position: Vector2
	var damage := 1

	func _init(p_position: Vector2) -> void:
		position = p_position

func spawn(at: Vector2) -> Hit:
	return Hit.new(at)
```

exports as

``` gdscript
#! struct
class Hit:
	enum { POSITION, DAMAGE }
	static func create(p_position: Vector2) -> Array:
		return [p_position, 1]

func spawn(at: Vector2) -> Array:
	return [at, 1]
```

- Put the tag on the line above `class X:`. At the top of a file, followed by a blank line, it makes
  the whole script the struct.
- A struct holds only `var` fields and an `_init` that assigns fields from its arguments. Methods,
  signals, setters/getters, annotations, or extending anything but RefCounted/Object fail the
  export.
- `X.new(...)` becomes an array literal when the arguments are in field order and every other field
  defaults to a literal; otherwise it becomes `X.create(...)`.
- `: X`, `-> X`, `as X`, `Array[X]` and `Dictionary[K, X]` become `Array`.
- `hit.damage` becomes `hit[Hit.DAMAGE]` wherever `hit` is statically typed as the struct: a typed
  var, param, member or return, `:=`, a `for` over a typed Array, an index into one. A file that
  reads a field without naming the struct gets a `const` preload appended for the enum.
- A struct must keep its static type, because once it is an Array a field read through Variant
  compiles and only fails at runtime. So the export fails on:
  - an untyped `var x = <struct>`, or a var typed as something else
  - returning a struct from a func whose return type isn't that struct
  - assigning a struct into a slot not typed as it
  - passing a struct to an untyped parameter
  - appending or inserting one into an untyped Array
  - a struct inside an array or dict literal, unless the literal is the whole value of a var,
    assignment or return typed `Array[X]` or `Dictionary[K, X]`
  - an untyped element parameter in a lambda given to `map`, `filter`, `any`, `all`, `reduce`,
    `sort_custom`, `find_custom` or `rfind_custom` on an Array of structs, whether the lambda is
    written inline or bound to a var and passed by name
  - `is X`, `is_instance_valid()`, `get()`/`set()`/`call()` on a struct
- Lambdas may take structs: `func(hit: Hit): return hit.damage` is rewritten like any other typed
  read, inline or bound to a var, including several lambdas on one line.
- The export warns, with file and line, when a struct is passed to `emit`, `emit_signal`, `call`,
  `call_deferred`, `callv`, `bind`, `set_meta` or `rpc`, or when a Callable that isn't a lambda in
  scope iterates an Array of structs. Their receivers can't be seen, so type their parameters as the
  struct.
- Not checked: structs passed to other engine methods with Variant parameters. A struct is also a
  plain Array to anything outside the plugin, so keep structs out of a plugin's public API.

## Static function inlining

Tag eligible static functions for expansion at supported call sites:

```gdscript
#! inline
static func affine(value: int, scale: int) -> int:
	return value * scale + value - 3
```

Conservative inlining preserves argument evaluation and supported value-type
conversions. Unsupported sites remain calls with diagnostic reasons. `#! inline; off`
excludes a definition; `#! inline; substitute` explicitly allows argument substitution
that can skip, repeat, or reorder effectful arguments. Use that modifier only when
the helper's callers can tolerate those effects.

`inline_mode` and `struct_mode` each accept `tagged`, `auto`, or `off`. Auto mode
discovers eligible definitions without adding tags; explicit exclusions still apply.
See the [shared optimizer documentation](https://github.com/brohd11/godot-gdscript-optimizer)
for supported syntax and exact eligibility rules. For export validation commands,
see [GDPackage development checks](testing.md#gdpackage-development-checks).

## Backport - **Deprecated**

Set `options.parser_settings.backport_target` in `export.yml` to the Godot 4 minor
version to target. For example, `3` targets Godot 4.3.x:

```yaml
options:
  parser_settings:
    backport_target: 3
```

The default `100` disables compatibility backports. Transformations depend on the
target: static variables can remain for 4.3, while EditorContextMenuPlugin needs a
compatibility implementation. Targeting 4.0 also rewrites static variables.

Backports cover supported constructs, including:

- EditorInterface singleton access and EditorContextMenuPlugin compatibility classes.
- Static variables converted to singleton storage with static getters and setters.
- Typed loop variables and dictionaries, raw strings, `X is not Y`, and `@abstract` syntax.
- Selected methods recreated in compatibility classes, and DPITexture resources converted to SVG.

This is a targeted compatibility pass; it does not cover every API or property change.
Use `gdpackage min_version` to inspect exported files, and test on the target engine.
See [Commands](commands.md#compatibility-inspection) for scanner options.

To branch on the exported target in your own code, declare `const BACKPORTED = 100`.
The exporter replaces it with the configured minor version when backporting.

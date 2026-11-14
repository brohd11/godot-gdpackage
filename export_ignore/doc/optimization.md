# Optimization and compatibility

## GDScript optimization

When enabled, exports run the shared GDScript optimizer before the packaging rewrites. It handles `#! struct` classes and `#! inline` static functions.

- New `export.yml` files set `options.parser_settings.parse_gd.optimizer.enabled` to `false`. Set it to `true` to turn it on. A config that omits the optimizer block has it enabled.
- Structs run before inlining. Scalar replacement and typed field reads are part of the struct pass.
- `struct_mode` and `inline_mode` each accept `tagged`, `auto`, or `off`. Auto discovers eligible definitions without tags. `#! struct; off` and `#! inline; off` exclude a definition in either mode.
- Reference types are opt-in through `aggressive`.
- Individual settings can be overridden per export entry in `parser_overide_settings.parse_gd.optimizer`.

See [Optimizer settings](export_settings.md#gdscript-optimizer) for the config block, and the [shared optimizer documentation](https://github.com/brohd11/godot-gdscript-optimizer) for supported syntax and exact eligibility rules.

## Structs

A class tagged `#! struct` is written like any data class, but exports as a plain Array, which skips object allocation and property lookup.

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

Writing one:

- The tag goes on the line above `class X:`. At the top of a file, followed by a blank line, it makes the whole script the struct.
- A struct holds only `var` fields and an `_init` that assigns fields from its arguments. Methods, signals, setters/getters, annotations, or extending anything but RefCounted/Object fail the export.

What gets rewritten:

- `X.new(...)` becomes an array literal when the arguments are in field order and every other field defaults to a literal. Otherwise it becomes `X.create(...)`.
- `: X`, `-> X`, `as X`, `Array[X]` and `Dictionary[K, X]` become `Array`.
- `hit.damage` becomes `hit[Hit.DAMAGE]` wherever `hit` is statically typed as the struct: a typed var, param, member or return, `:=`, a `for` over a typed Array, an index into one.
- A file that reads a field without naming the struct gets a `const` preload appended for the enum.
- Lambdas may take structs: `func(hit: Hit): return hit.damage` is rewritten like any other typed read, inline or bound to a var.

A struct must keep its static type. Once it is an Array, a field read through Variant compiles and only fails at runtime. So the export fails on:

- an untyped `var x = <struct>`, or a var typed as something else
- returning a struct from a func whose return type isn't that struct
- assigning a struct into a slot not typed as it
- passing a struct to an untyped parameter
- appending or inserting one into an untyped Array
- a struct inside an array or dict literal, unless the literal is the whole value of a var, assignment or return typed `Array[X]` or `Dictionary[K, X]`
- an untyped element parameter in a lambda given to `map`, `filter`, `any`, `all`, `reduce`, `sort_custom`, `find_custom` or `rfind_custom` on an Array of structs, whether the lambda is inline or bound to a var and passed by name
- `is X`, `is_instance_valid()`, `get()`/`set()`/`call()` on a struct

The export warns, with file and line, when:

- a struct is passed to `emit`, `emit_signal`, `call`, `call_deferred`, `callv`, `bind`, `set_meta` or `rpc`
- a Callable that isn't a lambda in scope iterates an Array of structs

Their receivers can't be seen, so type the receiving parameters as the struct.

Not checked: structs passed to other engine methods with Variant parameters. A struct is also a plain Array to anything outside the plugin, so keep structs out of a plugin's public API.

## Static function inlining

A static function tagged `#! inline` is expanded at supported call sites:

```gdscript
#! inline
static func affine(value: int, scale: int) -> int:
	return value * scale + value - 3
```

- Inlining preserves argument evaluation and supported value-type conversions.
- Unsupported sites stay as calls, with a diagnostic reason.
- `#! inline; substitute` allows argument substitution that can skip, repeat, or reorder effectful arguments. Use it only when the callers can tolerate that.

For export validation commands, see [GDPackage development checks](testing.md#gdpackage-development-checks).

## Backport - **Deprecated**

Set `options.parser_settings.backport_target` in `export.yml` to the Godot 4 minor version to target. `3` targets Godot 4.3.x:

```yaml
options:
  parser_settings:
    backport_target: 3
```

The default `100` disables backports. Transformations depend on the target: static variables can stay for 4.3 but are rewritten for 4.0, while EditorContextMenuPlugin needs a compatibility implementation.

Covered:

- EditorInterface singleton access and EditorContextMenuPlugin compatibility classes.
- Static variables converted to singleton storage with static getters and setters.
- Typed loop variables and dictionaries, raw strings, `X is not Y`, and `@abstract` syntax.
- Selected methods recreated in compatibility classes, and DPITexture resources converted to SVG.

It does not cover every API or property change. Use [`gdpackage min_version`](commands.md#compatibility-inspection) to inspect exported files, and test on the target engine.

To branch on the exported target in code, declare `const BACKPORTED = 100`. The exporter replaces it with the configured minor version when backporting.

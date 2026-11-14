# Kitchen sink

Every construct the doc viewer renders, in one page. Open it with
`DocViewer.open()` to check a change by eye. This paragraph is wrapped
in the source and should read as **one** flowing paragraph with *italic*,
~~struck~~, ***both***, and `inline code` in it.

A hard break follows this line\
and this is the second line. Jump to [Tables](#tables) or [the end](#the-end).

## Inline

- Links: [inline](https://godotengine.org), <https://godotengine.org>, https://godotengine.org, and a [reference][ref].
- Literal text: snake_case_name, 2 * 3 * 4, array[0], `<package>/licenses`, <package>, \*escaped\*, &amp; &lt;tag&gt;.
- Emphasis **spanning a [link](#inline) and `code`** in one run.
- `code with [brackets] and **stars**`

[ref]: https://docs.godotengine.org "Docs"

## Lists

- First item with enough text that it has to wrap onto a second line, so the hanging indent under the bullet can be checked against the item's first line.
  - Nested item
    - Deeper item
  - Another nested item
- Item with a continuation
  line that joins it.
- [ ] Task to do
- [x] Task done

1. Step one
2. Step two
   - Detail of step two
3. Step three

```gdscript
func resumed() -> void:
	pass
```

4. Step four, resumed after a code block
5. Step five

## Tables

| Destination | Placement | Count |
| :--- | :---: | ---: |
| `licenses/font/LICENSE` | Named `LICENSE` below the declaring file's exported directory | 1 |
| `current` or `.` | Original filename **beside** the exported declaring file | 20 |
| Omitted | Default [remote](#lists) placement | 300 |

## Quotes

> A plain quote with **bold** text and a [link](#kitchen-sink).
>
> - It can hold a list
> - and `code`
>
> ```gdscript
> var quoted := true
> ```

> [!NOTE]
> A note alert.

> [!WARNING]
> A warning alert.

> [!CAUTION]
> A caution alert.

### Third level

#### Fourth level

Setext heading
--------------

---

## The end

Last paragraph.

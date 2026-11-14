@tool
extends EditorScript

## Tests for the doc viewer's markdown parser — block segmentation and the inline-to-BBCode pass.
## The parser is static and pure, so the whole suite runs headless with no scene and no fixtures.
##
##     load("res://addons/gdpackage/export_ignore/test/doc_viewer/markdown_parser_test.gd").run_tests()

const Parser = preload("res://addons/gdpackage/src/components/doc_viewer/markdown_parser.gd")

## Base size the bbcode assertions are written against; heading sizes are ratios of it.
const BASE = 16

static var _failures:Array[String] = []
static var _passed:int = 0


static func run_tests() -> Dictionary:
	_failures = []
	_passed = 0

	_test_fences()
	_test_images_and_rules()
	_test_headings()
	_test_emphasis()
	_test_links_and_escaping()
	_test_lists_and_quotes()
	_test_first_heading()
	_test_heading_blocks()
	_test_tables()
	_test_quote_blocks()
	_test_reflow()
	_test_inline_extras()
	_test_reference_links()
	_test_context_colors()
	_test_no_marker_collision()
	_test_tag_balance()

	var output:Array[String] = []
	output.append("markdown_parser: %d passed, %d failed" % [_passed, _failures.size()])
	for failure in _failures:
		output.append("  FAIL  " + failure)

	return {"result": _failures.size(), "output": output}


func _run() -> void: # EditorScript entry, for running this from the editor
	print("\n".join(run_tests().output))


## The info string names the fence's language and must not survive into the code itself.
static func _test_fences() -> void:
	var blocks = Parser.parse("intro\n\n```gdscript\nvar x = 1\n```\n\nouttro")
	_check("fence: block count", blocks.size(), 3)
	_check("fence: prose before", blocks[0][Parser.KEY_TYPE], Parser.TYPE_TEXT)
	_check("fence: code type", blocks[1][Parser.KEY_TYPE], Parser.TYPE_CODE)
	_check("fence: lang", blocks[1][Parser.KEY_LANG], "gdscript")
	_check("fence: body excludes the fences", blocks[1][Parser.KEY_TEXT], "var x = 1")
	_check("fence: prose after", blocks[2][Parser.KEY_TEXT], "outtro")

	var no_lang = Parser.parse("```\nplain\n```")
	_check("fence: no info string", no_lang[0][Parser.KEY_LANG], "")

	var tilde = Parser.parse("~~~yaml\nkey: value\n~~~")
	_check("fence: tilde lang", tilde[0][Parser.KEY_LANG], "yaml")
	_check("fence: tilde body", tilde[0][Parser.KEY_TEXT], "key: value")

	# A backtick run inside a longer fence is body text, not the close.
	var nested = Parser.parse("````\n```\ninner\n````")
	_check("fence: longer run closes", nested.size(), 1)
	_check("fence: shorter run is body", nested[0][Parser.KEY_TEXT], "```\ninner")

	# An unterminated fence renders as code rather than swallowing the rest of the doc.
	var unterminated = Parser.parse("before\n\n```\nvar x = 1\nvar y = 2")
	_check("fence: unterminated count", unterminated.size(), 2)
	_check("fence: unterminated is code", unterminated[1][Parser.KEY_TYPE], Parser.TYPE_CODE)
	_check("fence: unterminated body", unterminated[1][Parser.KEY_TEXT], "var x = 1\nvar y = 2")

	_check("fence: blank lines around blocks dropped", Parser.parse("\n\ntext\n\n").size(), 1)


static func _test_images_and_rules() -> void:
	var blocks = Parser.parse("![a shot](images/shot.png)")
	_check("image: type", blocks[0][Parser.KEY_TYPE], Parser.TYPE_IMAGE)
	_check("image: src", blocks[0][Parser.KEY_SRC], "images/shot.png")
	_check("image: alt", blocks[0][Parser.KEY_ALT], "a shot")

	var titled = Parser.parse('![](shot.png "hover")')
	_check("image: title dropped", titled[0][Parser.KEY_SRC], "shot.png")

	# Only a standalone image becomes a block - one inside a sentence stays in the prose.
	var inline = Parser.parse("see ![a shot](shot.png) here")
	_check("image: inline stays prose", inline[0][Parser.KEY_TYPE], Parser.TYPE_TEXT)

	var ruled = Parser.parse("above\n\n---\n\nbelow")
	_check("rule: block count", ruled.size(), 3)
	_check("rule: type", ruled[1][Parser.KEY_TYPE], Parser.TYPE_RULE)
	_check("rule: asterisks", Parser.parse("a\n\n***\n\nb")[1][Parser.KEY_TYPE], Parser.TYPE_RULE)


static func _test_headings() -> void:
	for level in range(1, 7):
		var text = Parser.to_bbcode("#".repeat(level) + " Title", BASE)
		var expected = "[font_size=%d][b]Title[/b][/font_size]" % Parser.heading_size(level, BASE)
		_check("heading: level %d" % level, text, expected)

	_check("heading: h1 is the largest", Parser.heading_size(1, BASE) > Parser.heading_size(2, BASE), true)
	_check("heading: sizes track the base", Parser.heading_size(1, 32) > Parser.heading_size(1, 16), true)
	_check("heading: seven hashes is not a heading", Parser.to_bbcode("####### x", BASE).contains("font_size"), false)
	_check("heading: closing hashes trimmed", Parser.to_bbcode("## Title ##", BASE).contains("[b]Title[/b]"), true)

	_check("heading: hash without a space before it is text", Parser.to_bbcode("# C#", BASE).contains("[b]C#[/b]"), true)

	# A setext underline turns the line above it into a heading.
	var setext = Parser.parse("Title\n=====\n\nbody")
	_check("heading: setext h1", [setext[0][Parser.KEY_LEVEL], setext[0][Parser.KEY_TEXT]], [1, "Title"])
	_check("heading: setext leaves the body", setext[1][Parser.KEY_TEXT], "body")
	_check("heading: setext h2", Parser.parse("Title\n---")[0][Parser.KEY_LEVEL], 2)
	# Dashes under a list item end the list with a rule; they do not promote the item.
	_check("heading: no setext from a list item", Parser.parse("- item\n---")[1][Parser.KEY_TYPE], Parser.TYPE_RULE)
	# The same dashes with no line above them are a rule, not a heading.
	_check("heading: dashes alone are a rule", Parser.parse("---")[0][Parser.KEY_TYPE], Parser.TYPE_RULE)


static func _test_emphasis() -> void:
	_check("emphasis: bold", Parser.to_bbcode("a **b** c", BASE), "a [b]b[/b] c")
	_check("emphasis: bold underscores", Parser.to_bbcode("a __b__ c", BASE), "a [b]b[/b] c")
	_check("emphasis: italic", Parser.to_bbcode("a *b* c", BASE), "a [i]b[/i] c")
	_check("emphasis: strike", Parser.to_bbcode("a ~~b~~ c", BASE), "a [s]b[/s] c")
	_check("emphasis: triple run nests cleanly", Parser.to_bbcode("***b***", BASE), "[i][b]b[/b][/i]")
	_check("emphasis: code span", Parser.to_bbcode("call `do_it()` now", BASE), "call [code]do_it()[/code] now")

	# Snake_case is everywhere in this repo's docs and must not read as emphasis.
	_check("emphasis: snake_case untouched", Parser.to_bbcode("my_var_name", BASE), "my_var_name")
	# Nothing inside a code span is markdown.
	_check("emphasis: not applied in code", Parser.to_bbcode("`a_b_c **d**`", BASE), "[code]a_b_c **d**[/code]")
	# A star with space on both sides is arithmetic or a typo, never emphasis.
	_check("emphasis: stray stars stay literal", Parser.to_bbcode("a * b * c", BASE), "a * b * c")
	_check("emphasis: spans a link", Parser.to_bbcode("**see [docs](x.md) now**", BASE),
		"[b]see [url=x.md]docs[/url] now[/b]")
	_check("emphasis: spans a code span", Parser.to_bbcode("*run `go` now*", BASE), "[i]run [code]go[/code] now[/i]")
	_check("emphasis: nested", Parser.to_bbcode("**a *b* c**", BASE), "[b]a [i]b[/i] c[/b]")
	_check("emphasis: unclosed stays literal", Parser.to_bbcode("**a", BASE), "**a")
	_check("emphasis: single tilde is text", Parser.to_bbcode("~5 and ~6", BASE), "~5 and ~6")


static func _test_links_and_escaping() -> void:
	_check("link: basic", Parser.to_bbcode("[docs](other.md)", BASE), "[url=other.md]docs[/url]")
	_check("link: emphasis in label", Parser.to_bbcode("[**docs**](x.md)", BASE), "[url=x.md][b]docs[/b][/url]")
	_check("link: url", Parser.to_bbcode("[site](https://a.b/c)", BASE), "[url=https://a.b/c]site[/url]")
	_check("link: inline image falls back to alt", Parser.to_bbcode("see ![shot](a.png)", BASE), "see shot")

	# A literal bracket must not read as BBCode once it reaches the label.
	_check("escape: bare bracket", Parser.to_bbcode("array[0]", BASE), "array[lb]0]")
	_check("escape: bbcode in prose", Parser.to_bbcode("[b]not bold[/b]", BASE), "[lb]b]not bold[lb]/b]")
	_check("escape: bracket in code span", Parser.to_bbcode("`a[0]`", BASE), "[code]a[lb]0][/code]")


static func _test_lists_and_quotes() -> void:
	_check("list: bullet", Parser.to_bbcode("- one", BASE), "[ul]one[/ul]")
	_check("list: asterisk bullet", Parser.to_bbcode("* one", BASE), "[ul]one[/ul]")
	_check("list: items", Parser.to_bbcode("- one\n- two", BASE), "[ul]one\ntwo[/ul]")
	_check("list: ordered", Parser.to_bbcode("1. one\n2. two", BASE), "[ol]one\ntwo[/ol]")
	_check("list: nested", Parser.to_bbcode("- a\n  - b\n- c", BASE), "[ul]a\n[ul]b[/ul]\nc[/ul]")
	_check("list: ordered inside bullets", Parser.to_bbcode("- a\n  1. b", BASE), "[ul]a\n[ol]b[/ol][/ul]")
	_check("list: marker change starts a new list", Parser.to_bbcode("- a\n1. b", BASE), "[ul]a[/ul]\n[ol]b[/ol]")
	_check("list: emphasis inside item", Parser.to_bbcode("- **a**", BASE), "[ul][b]a[/b][/ul]")
	_check("list: follows its paragraph", Parser.to_bbcode("intro:\n- a", BASE), "intro:\n[ul]a[/ul]")
	_check("list: lazy line joins the item", Parser.to_bbcode("- a\nb\n- c", BASE), "[ul]a b\nc[/ul]")
	_check("list: blank line between items", Parser.to_bbcode("- a\n\n- b", BASE), "[ul]a\nb[/ul]")
	_check("list: paragraph after a blank line", Parser.to_bbcode("- a\n\nb", BASE), "[ul]a[/ul]\n\nb")
	_check("list: task boxes", Parser.to_bbcode("- [ ] todo\n- [x] done", BASE), "[ul]☐ todo\n☑ done[/ul]")
	# [ol] cannot start mid-count, so a list resumed after a code block writes its numbers out.
	_check("list: resumed ordered keeps its number", Parser.to_bbcode("2. two\n3. three", BASE),
		"[indent]2. two[/indent]\n[indent]3. three[/indent]")

	# A fence nested in a list item sheds the item's indent.
	var nested = Parser.parse("- step\n  ```sh\n  run\n    deep\n  ```")
	_check("list: nested fence is a code block", nested[1][Parser.KEY_TYPE], Parser.TYPE_CODE)
	_check("list: nested fence dedented", nested[1][Parser.KEY_TEXT], "run\n  deep")


static func _test_first_heading() -> void:
	_check("title: from heading", Parser.first_heading("# Export Settings"), "Export Settings")
	_check("title: level does not matter", Parser.first_heading("### Deep"), "Deep")
	_check("title: markers stripped", Parser.first_heading("# The **big** `one`"), "The big one")
	_check("title: link label kept", Parser.first_heading("# [Home](i.md)"), "Home")
	_check("title: none", Parser.first_heading("just prose"), "")


static func _test_heading_blocks() -> void:
	var blocks = Parser.parse("intro\n## Setup `now`\nbody")
	_check("heading block: splits the prose", blocks.size(), 3)
	_check("heading block: type", blocks[1][Parser.KEY_TYPE], Parser.TYPE_HEADING)
	_check("heading block: level", blocks[1][Parser.KEY_LEVEL], 2)
	_check("heading block: text keeps its markdown", blocks[1][Parser.KEY_TEXT], "Setup `now`")
	_check("heading block: id", blocks[1][Parser.KEY_ID], "setup-now")

	# The slugs the shipped docs already link to.
	_check("slug: punctuation dropped", Parser.slug("GUT, GDUnit4, and custom runners"), "gut-gdunit4-and-custom-runners")
	_check("slug: hyphens kept", Parser.slug("Backport - deprecated"), "backport---deprecated")
	_check("slug: underscores kept", Parser.slug("parse_gd"), "parse_gd")

	var twice = Parser.parse("# Usage\n\n# Usage\n\n> # Usage")
	_check("slug: second duplicate numbered", twice[1][Parser.KEY_ID], "usage-1")
	_check("slug: counted across quotes", twice[2][Parser.KEY_BLOCKS][0][Parser.KEY_ID], "usage-2")


static func _test_tables() -> void:
	var blocks = Parser.parse("before\n\n| Name | Count |\n| :--- | ---: |\n| `a\\|b` | 1 |\n| c \\| d |\n\nafter")
	_check("table: block count", blocks.size(), 3)
	var table:Dictionary = blocks[1]
	_check("table: type", table[Parser.KEY_TYPE], Parser.TYPE_TABLE)
	_check("table: header", table[Parser.KEY_HEADER], ["Name", "Count"])
	_check("table: align", table[Parser.KEY_ALIGN], [Parser.ALIGN_LEFT, Parser.ALIGN_RIGHT])
	_check("table: escaped pipe in a code span", table[Parser.KEY_ROWS][0], ["`a|b`", "1"])
	_check("table: short row padded", table[Parser.KEY_ROWS][1], ["c | d", ""])

	var span = Parser.parse("| a | b |\n| --- | :-: |\n| `x | y` | z |")[0]
	_check("table: pipe in a code span does not split", span[Parser.KEY_ROWS][0], ["`x | y`", "z"])
	_check("table: center and default align", span[Parser.KEY_ALIGN], [Parser.ALIGN_NONE, Parser.ALIGN_CENTER])

	var bare = Parser.parse("a | b\n--- | ---\n1 | 2")[0]
	_check("table: outer pipes optional", [bare[Parser.KEY_HEADER], bare[Parser.KEY_ROWS]], [["a", "b"], [["1", "2"]]])

	# Without a delimiter row it is only a line with pipes in it.
	_check("table: needs a delimiter row", Parser.parse("| a | b |\n| c | d |")[0][Parser.KEY_TYPE], Parser.TYPE_TEXT)
	_check("table: column count must match", Parser.parse("| a | b |\n| --- |")[0][Parser.KEY_TYPE], Parser.TYPE_TEXT)


static func _test_quote_blocks() -> void:
	var blocks = Parser.parse("above\n> quoted **bold**\n> - item\n>\n> ```\n> code\n> ```\nbelow")
	_check("quote: block count", blocks.size(), 3)
	var quote:Dictionary = blocks[1]
	_check("quote: type", quote[Parser.KEY_TYPE], Parser.TYPE_QUOTE)
	_check("quote: plain has no kind", quote[Parser.KEY_KIND], "")
	_check("quote: prose inside", quote[Parser.KEY_BLOCKS][0][Parser.KEY_TEXT], "quoted **bold**\n- item")
	_check("quote: fence inside", quote[Parser.KEY_BLOCKS][1][Parser.KEY_TEXT], "code")

	var nested = Parser.parse("> outer\n> > inner")[0]
	_check("quote: nested", nested[Parser.KEY_BLOCKS][1][Parser.KEY_TYPE], Parser.TYPE_QUOTE)

	var alert = Parser.parse("> [!WARNING]\n> careful")[0]
	_check("quote: alert kind", alert[Parser.KEY_KIND], "warning")
	_check("quote: alert marker removed", alert[Parser.KEY_BLOCKS][0][Parser.KEY_TEXT], "careful")
	_check("quote: unknown alert is text", Parser.parse("> [!NOPE]\n> x")[0][Parser.KEY_KIND], "")


## Source line breaks are the writer's wrapping, not the reader's.
static func _test_reflow() -> void:
	_check("reflow: soft break is a space", Parser.to_bbcode("one\ntwo", BASE), "one two")
	_check("reflow: blank line separates", Parser.to_bbcode("one\n\ntwo", BASE), "one\n\ntwo")
	_check("reflow: two trailing spaces break", Parser.to_bbcode("one  \ntwo", BASE), "one\ntwo")
	_check("reflow: trailing backslash breaks", Parser.to_bbcode("one\\\ntwo", BASE), "one\ntwo")
	_check("reflow: br breaks", Parser.to_bbcode("one<br>two", BASE), "one\ntwo")
	_check("reflow: emphasis across a soft break", Parser.to_bbcode("**one\ntwo**", BASE), "[b]one two[/b]")


static func _test_inline_extras() -> void:
	_check("escape: backslash star", Parser.to_bbcode("\\*not\\*", BASE), "*not*")
	_check("escape: backslash bracket", Parser.to_bbcode("\\[x](y)", BASE), "[lb]x](y)")
	_check("escape: backslash before a letter kept", Parser.to_bbcode("C:\\dir", BASE), "C:\\dir")
	_check("autolink: angle brackets", Parser.to_bbcode("<https://a.b/c>", BASE), "[url=https://a.b/c]https://a.b/c[/url]")
	_check("autolink: bare url", Parser.to_bbcode("see https://a.b/c.", BASE), "see [url=https://a.b/c]https://a.b/c[/url].")
	_check("autolink: not inside a word", Parser.to_bbcode("xhttps://a.b", BASE), "xhttps://a.b")
	_check("autolink: not inside a link label", Parser.to_bbcode("[https://a.b](c.md)", BASE), "[url=c.md]https://a.b[/url]")
	_check("link: linked image keeps its alt", Parser.to_bbcode("[![build](b.svg)](ci.md)", BASE), "[url=ci.md]build[/url]")
	_check("link: brackets in the label", Parser.to_bbcode("[a [b] c](x.md)", BASE), "[url=x.md]a [lb]b] c[/url]")
	_check("link: parens in the url", Parser.to_bbcode("[w](https://a.b/x_(y))", BASE), "[url=https://a.b/x_(y)]w[/url]")
	_check("link: title dropped", Parser.to_bbcode('[a](x.md "hover")', BASE), "[url=x.md]a[/url]")
	_check("html: placeholder stays literal", Parser.to_bbcode("use <package>/x", BASE), "use <package>/x")
	_check("html: comment dropped", Parser.to_bbcode("a<!-- note -->b", BASE), "ab")
	_check("entity: named", Parser.to_bbcode("a &amp; b &lt;c&gt;", BASE), "a & b <c>")
	_check("entity: unknown kept", Parser.to_bbcode("a &foo; b", BASE), "a &foo; b")
	_check("code: double backticks hold a backtick", Parser.to_bbcode("`` a`b ``", BASE), "[code]a`b[/code]")


static func _test_reference_links() -> void:
	var source = "see [the docs][docs] and [Home]\n\n[docs]: https://a.b/docs\n[home]: index.md \"Start\"\n```\n[code]: no.md\n```"
	var refs = Parser.link_refs(source)
	_check("refs: collected", refs, {"docs":"https://a.b/docs", "home":"index.md"})
	_check("refs: definitions leave the output", Parser.parse(source)[0][Parser.KEY_TEXT], "see [the docs][docs] and [Home]")
	_check("refs: resolved", Parser.to_bbcode("see [the docs][docs] and [Home]", BASE, {Parser.CTX_REFS:refs}),
		"see [url=https://a.b/docs]the docs[/url] and [url=index.md]Home[/url]")
	_check("refs: unknown id stays literal", Parser.to_bbcode("[nope][x]", BASE, {Parser.CTX_REFS:refs}), "[lb]nope][lb]x]")


## Colors come from the renderer; the parser only knows where they go.
static func _test_context_colors() -> void:
	var ctx = {Parser.CTX_CODE_BG:"#111", Parser.CTX_CODE_FG:"#eee", Parser.CTX_LINK:"#08f"}
	_check("ctx: code span", Parser.to_bbcode("`x`", BASE, ctx), "[bgcolor=#111] [color=#eee][code]x[/code][/color] [/bgcolor]")
	_check("ctx: link", Parser.to_bbcode("[a](b.md)", BASE, ctx), "[color=#08f][url=b.md]a[/url][/color]")
	_check("ctx: table cell", Parser.inline_bbcode("**a** `b`", {Parser.CTX_CODE_BG:"#111"}), "[b]a[/b] [bgcolor=#111] [code]b[/code] [/bgcolor]")


## The inline pass once substituted finished spans back into the text behind index markers, and
## the markers collided with any digit on the line - mangling urls and unbalancing the bbcode.
## Converted spans are kept out of the text entirely now, so a document cannot collide with them.
static func _test_no_marker_collision() -> void:
	_check("collision: digit beside a link", Parser.to_bbcode("v1.0 uses [api](a.md) on 8080", BASE),
		"v1.0 uses [url=a.md]api[/url] on 8080")
	_check("collision: digit beside a code span", Parser.to_bbcode("run `go` 10 times", BASE),
		"run [code]go[/code] 10 times")
	_check("collision: digits inside the url", Parser.to_bbcode("[ref](https://github.com/brohd11/x)", BASE),
		"[url=https://github.com/brohd11/x]ref[/url]")
	_check("collision: digits inside a code span", Parser.to_bbcode("`v1 and v0`", BASE),
		"[code]v1 and v0[/code]")
	_check("collision: two links on one line", Parser.to_bbcode("[a](1.md) and [b](2.md)", BASE),
		"[url=1.md]a[/url] and [url=2.md]b[/url]")


## Unbalanced output makes RichTextLabel pop tags it never pushed, which surfaces as engine errors
## rather than anything visible in the text - so balance is asserted here instead.
static func _test_tag_balance() -> void:
	var corpus:Array[String] = [
		"# Heading with `code` and [a link](x.md)",
		" - [EditorNodeRef](https://github.com/brohd11/Godot-Editor-Node-Ref) -> res://addons/_lib/editor_node_ref",
		"### **Be sure to download the zip in releases, not the repo source code.**",
		"> quoted **bold** with [link](y.md) and 2 digits",
		"  - nested item with `a[0]` and *emphasis*",
		"literal [brackets] and [/url] and [b] in prose",
		"1. ordered with ![inline image](shot.png)",
		"trailing ** star and _ underscore and ` tick",
		"- one\n  - two **bold\n- three** `x`",
		"1. a\n   - b\n2. c\n\n3. d",
		"*a **b* c** and ~~x *y~~ z*",
		"**[link *one](x.md) two* <https://a.b> https://c.d**",
		"- [ ] task with [ref] and \\[escaped] ![img](a.png)",
	]
	for line in corpus:
		var bbcode = Parser.to_bbcode(line, BASE)
		_check("balance: " + line.substr(0, 34), _unbalanced_tag(bbcode), "")


## The first tag that closes without an open one, or that is left open at the end. Empty when the
## bbcode is balanced.
static func _unbalanced_tag(bbcode:String) -> String:
	var stack:Array[String] = []
	var re = RegEx.create_from_string(r"\[(/?)([a-zA-Z_]+)[^\]]*\]")
	for m in re.search_all(bbcode):
		var name = m.get_string(2)
		if name in ["lb", "rb", "img"]:
			continue
		if m.get_string(1) == "":
			stack.append(name)
			continue
		if stack.is_empty():
			return "closed [/%s] with nothing open" % name
		var open = stack.pop_back()
		if open != name:
			return "[%s] closed by [/%s]" % [open, name]
	if not stack.is_empty():
		return "left open: " + str(stack)
	return ""


# --- harness -----------------------------------------------------------------------------

static func _check(label:String, actual, expected) -> void:
	if actual == expected:
		_passed += 1
		return
	_failures.append("%s — expected %s, got %s" % [label, var_to_str(expected), var_to_str(actual)])

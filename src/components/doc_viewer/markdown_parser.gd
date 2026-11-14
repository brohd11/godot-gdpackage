## Markdown to renderable blocks, plus inline markdown to BBCode. Pure and static - no engine
## state, no plugin coupling - so the whole thing is testable headless and portable as is.
##
## Inline conversion emits finished spans as separate tokens instead of substituting them back
## into the text, so nothing a document contains can be mistaken for the parser's own markers.

const TYPE_TEXT = "text"
const TYPE_CODE = "code"
const TYPE_IMAGE = "image"
const TYPE_RULE = "rule"
const TYPE_HEADING = "heading"
const TYPE_TABLE = "table"
const TYPE_QUOTE = "quote"

const KEY_TYPE = "type"
const KEY_TEXT = "text"
const KEY_LANG = "lang"
const KEY_SRC = "src"
const KEY_ALT = "alt"
const KEY_LEVEL = "level"
## Anchor slug of a heading, unique within the document.
const KEY_ID = "id"
## Table cells hold raw inline markdown; KEY_ALIGN has one ALIGN_* per column.
const KEY_HEADER = "header"
const KEY_ALIGN = "align"
const KEY_ROWS = "rows"
## A quote's content, parsed into blocks of its own.
const KEY_BLOCKS = "blocks"
## Alert kind of a quote ("note", "warning", ...), or empty for a plain quote.
const KEY_KIND = "kind"

const ALIGN_NONE = ""
const ALIGN_LEFT = "left"
const ALIGN_CENTER = "center"
const ALIGN_RIGHT = "right"

## Optional to_bbcode context. Colors are BBCode color values; without them output is structural.
const CTX_CODE_BG = "code_bg"
const CTX_CODE_FG = "code_fg"
const CTX_LINK = "link"
## Reference link definitions, as returned by link_refs().
const CTX_REFS = "refs"

const ALERT_KINDS:Array[String] = ["note", "tip", "important", "warning", "caution"]

## Heading size as a ratio of the host's base font size. Ratios rather than pixels so headings
## track the editor's font size and scale, which is where fixed-size markdown previews fall apart.
const HEADING_RATIOS:Array[float] = [1.7, 1.45, 1.25, 1.15, 1.05, 1.0]

## Line break that stays inside its paragraph. A plain newline would start a new list item.
const _SOFT_BREAK = " "
const _PUNCTUATION = "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~"
const _WHITESPACE = " \t\n  "
const _ENTITIES = {"amp":"&", "lt":"<", "gt":">", "quot":"\"", "apos":"'", "nbsp":" "}

const _RE_HEADING = r"^\s{0,3}(#{1,6})(?:[ \t]+(.*?))??(?:[ \t]+#+)?[ \t]*$"
const _RE_LIST = r"^(\s*)(?:([-*+])|(\d{1,9})[.)])\s+(.*)$"
const _RE_REF_DEF = r"^\s{0,3}\[([^\]^][^\]]*)\]:\s+<?([^\s>]+)>?(?:\s+[\"'(].*)?\s*$"
const _RE_LINK_DEST = r"\G\(\s*(<[^>]*>|(?:[^()\s]|\([^()\s]*\))+)(?:\s+(?:\"[^\"]*\"|'[^']*'))?\s*\)"

static var _re_cache:Dictionary = {}


## Splits [param text] into an ordered Array of block dictionaries, each keyed by KEY_TYPE.
static func parse(text:String) -> Array:
	return _parse_lines(text.replace("\r\n", "\n").split("\n"), {})


## Converts a prose block to BBCode. [param base_font_size] is the host's font size, which heading
## sizes are derived from. [param ctx] takes the CTX_* keys; empty keeps the output structural.
static func to_bbcode(text:String, base_font_size:int, ctx:Dictionary = {}) -> String:
	var out := ""
	for element in _elements(text):
		if out != "":
			out += "\n\n" if element.gap else "\n"
		match element.kind:
			"h":
				out += heading_bbcode(element.text, element.level, base_font_size, ctx)
			"list":
				out += _list_bbcode(element.items, ctx)
			_:
				out += inline_bbcode(_join_lines(element.lines, "\n"), ctx)
	return out


## Converts one run of inline markdown - a table cell, a heading - to BBCode.
static func inline_bbcode(text:String, ctx:Dictionary = {}) -> String:
	return _inline(text, ctx, false)


static func heading_bbcode(text:String, level:int, base_font_size:int, ctx:Dictionary = {}) -> String:
	return "[font_size=%d][b]%s[/b][/font_size]" % [heading_size(level, base_font_size), _inline(text, ctx, false)]


## Font size for an ATX heading level 1-6, given the host's base size.
static func heading_size(level:int, base_font_size:int) -> int:
	var ratio:float = HEADING_RATIOS[clampi(level, 1, HEADING_RATIOS.size()) - 1]
	return maxi(1, roundi(base_font_size * ratio))


## The first "# " heading in [param text], else an empty string.
static func first_heading(text:String) -> String:
	for line in text.replace("\r\n", "\n").split("\n"):
		var match_result = _re(_RE_HEADING).search(line)
		if match_result and match_result.get_string(2) != "":
			return _strip_inline_markers(match_result.get_string(2))
	return ""


## Anchor for a heading, the way GitHub derives it: lowercase, punctuation dropped, spaces to
## hyphens. Not deduplicated - parse() does that per document.
static func slug(heading_text:String) -> String:
	var plain = _strip_inline_markers(heading_text).to_lower()
	plain = _re(r"[^\p{L}\p{N}_\- ]").sub(plain, "", true)
	return plain.replace(" ", "-")


## Reference link definitions ("[id]: url") in [param text], keyed by lowercased id.
static func link_refs(text:String) -> Dictionary:
	var refs:Dictionary = {}
	var fence := ""
	for line in text.replace("\r\n", "\n").split("\n"):
		if fence != "":
			if _closes_fence(line, fence):
				fence = ""
			continue
		var opened = _fence_opened(line)
		if not opened.is_empty():
			fence = opened[0]
			continue
		var definition = _re(_RE_REF_DEF).search(line)
		if definition:
			var id = definition.get_string(1).strip_edges().to_lower()
			if not refs.has(id):
				refs[id] = definition.get_string(2)
	return refs


#region blocks

## [param slugs] counts heading ids across the whole document, quotes included.
static func _parse_lines(lines:PackedStringArray, slugs:Dictionary) -> Array:
	var blocks:Array = []
	var prose:Array[String] = []
	var code:Array[String] = []
	var fence := ""
	var fence_indent := 0
	var lang := ""

	var i := -1
	while i + 1 < lines.size():
		i += 1
		var line := lines[i]
		if fence != "":
			if _closes_fence(line, fence):
				blocks.append(_code_block(code, lang))
				code.clear()
				fence = ""
				lang = ""
			else:
				code.append(_dedent(line, fence_indent))
			continue

		var opened = _fence_opened(line)
		if not opened.is_empty():
			_flush_prose(prose, blocks)
			fence = opened[0]
			lang = opened[1]
			fence_indent = opened[2]
			continue

		if _re(_RE_REF_DEF).search(line):
			continue

		if _is_quote(line):
			_flush_prose(prose, blocks)
			var quoted:PackedStringArray = []
			while i < lines.size() and _is_quote(lines[i]):
				quoted.append(_re(r"^\s{0,3}>\s?").sub(lines[i], ""))
				i += 1
			i -= 1
			blocks.append(_quote_block(quoted, slugs))
			continue

		var heading = _re(_RE_HEADING).search(line)
		if heading:
			_flush_prose(prose, blocks)
			blocks.append(_heading_block(heading.get_string(1).length(), heading.get_string(2), slugs))
			continue

		if line.contains("|") and i + 1 < lines.size():
			var align = _table_align(lines[i + 1])
			var header = _split_row(line)
			if not align.is_empty() and align.size() == header.size():
				_flush_prose(prose, blocks)
				var rows:Array = []
				i += 2
				while i < lines.size() and lines[i].contains("|") and lines[i].strip_edges() != "":
					var row = _split_row(lines[i])
					row.resize(header.size())
					rows.append(Array(row).map(func(cell): return cell if cell != null else ""))
					i += 1
				i -= 1
				blocks.append({KEY_TYPE:TYPE_TABLE, KEY_HEADER:header, KEY_ALIGN:align, KEY_ROWS:rows})
				continue

		# A setext underline retroactively turns the line above it into a heading, so it has to be
		# tested before the rule check - "---" is both.
		var setext = _setext_level(line)
		if setext != 0 and not prose.is_empty() and prose[-1].strip_edges() != "" \
				and not _re(_RE_LIST).search(prose[-1]):
			var title = prose.pop_back().strip_edges()
			_flush_prose(prose, blocks)
			blocks.append(_heading_block(setext, title, slugs))
			continue

		if _is_rule(line):
			_flush_prose(prose, blocks)
			blocks.append({KEY_TYPE:TYPE_RULE})
			continue

		var image = _image_only(line)
		if not image.is_empty():
			_flush_prose(prose, blocks)
			blocks.append(image)
			continue

		prose.append(line)

	# An unterminated fence renders as code rather than swallowing the rest of the doc.
	if fence != "":
		blocks.append(_code_block(code, lang))
	_flush_prose(prose, blocks)

	return blocks


static func _code_block(code:Array[String], lang:String) -> Dictionary:
	return {KEY_TYPE:TYPE_CODE, KEY_LANG:lang, KEY_TEXT:"\n".join(code)}


static func _heading_block(level:int, text:String, slugs:Dictionary) -> Dictionary:
	var id = slug(text)
	var seen:int = slugs.get(id, 0)
	slugs[id] = seen + 1
	if seen > 0:
		id += "-%d" % seen
	return {KEY_TYPE:TYPE_HEADING, KEY_LEVEL:level, KEY_TEXT:text, KEY_ID:id}


static func _quote_block(lines:PackedStringArray, slugs:Dictionary) -> Dictionary:
	var kind := ""
	var alert = _re(r"^\s*\[!(\w+)\]\s*$").search(lines[0])
	if alert and alert.get_string(1).to_lower() in ALERT_KINDS:
		kind = alert.get_string(1).to_lower()
		lines.remove_at(0)
	return {KEY_TYPE:TYPE_QUOTE, KEY_KIND:kind, KEY_BLOCKS:_parse_lines(lines, slugs)}


static func _flush_prose(prose:Array[String], blocks:Array) -> void:
	while not prose.is_empty() and prose[0].strip_edges() == "":
		prose.remove_at(0)
	while not prose.is_empty() and prose[-1].strip_edges() == "":
		prose.remove_at(prose.size() - 1)
	if prose.is_empty():
		return
	blocks.append({KEY_TYPE:TYPE_TEXT, KEY_TEXT:"\n".join(prose)})
	prose.clear()


## The opening fence run, its info string and its indent, or an empty Array for any other line.
static func _fence_opened(line:String) -> Array:
	var match_result = _re(r"^(\s*)(`{3,}|~{3,})\s*([^`\s]*)").search(line)
	if not match_result:
		return []
	return [match_result.get_string(2), match_result.get_string(3).to_lower(), match_result.get_string(1).length()]


## A closing fence has to be at least as long as the one that opened it and carry nothing else.
static func _closes_fence(line:String, fence:String) -> bool:
	var stripped = line.strip_edges()
	if not stripped.begins_with(fence):
		return false
	return stripped.lstrip(fence[0]) == ""


## Drops up to [param width] leading whitespace characters, so a fence nested in a list item
## does not carry the item's indent into its code.
static func _dedent(line:String, width:int) -> String:
	var cut := 0
	while cut < width and cut < line.length() and line[cut] in " \t":
		cut += 1
	return line.substr(cut)


static func _is_quote(line:String) -> bool:
	return _re(r"^\s{0,3}>").search(line) != null


## Setext heading level for an underline row, or 0.
static func _setext_level(line:String) -> int:
	var stripped = line.strip_edges()
	if stripped == "":
		return 0
	if stripped.lstrip("=") == "":
		return 1
	if stripped.lstrip("-") == "":
		return 2
	return 0


static func _is_rule(line:String) -> bool:
	var stripped = line.strip_edges().replace(" ", "")
	if stripped.length() < 3:
		return false
	for c in ["-", "*", "_"]:
		if stripped.lstrip(c) == "":
			return true
	return false


## An image block, but only when the image is alone on its line - inline images stay inline.
static func _image_only(line:String) -> Dictionary:
	var match_result = _re(r'^\s*!\[([^\]]*)\]\(\s*([^)\s]+)(?:\s+"[^"]*")?\s*\)\s*$').search(line)
	if not match_result:
		return {}
	return {KEY_TYPE:TYPE_IMAGE, KEY_SRC:match_result.get_string(2), KEY_ALT:match_result.get_string(1)}


## Column alignments of a table delimiter row, or an empty Array when the line is not one.
static func _table_align(line:String) -> Array:
	if not line.contains("|"):
		return []
	var align:Array = []
	for cell in _split_row(line):
		if not _re(r"^:?-+:?$").search(cell):
			return []
		var left:bool = cell.begins_with(":")
		var right:bool = cell.ends_with(":")
		if left and right:
			align.append(ALIGN_CENTER)
		elif right:
			align.append(ALIGN_RIGHT)
		else:
			align.append(ALIGN_LEFT if left else ALIGN_NONE)
	return align


## Cells of one table row. A pipe that is escaped or sits inside a code span does not split.
static func _split_row(line:String) -> Array:
	var text := line.strip_edges()
	if text.begins_with("|"):
		text = text.substr(1)
	var cells:Array = []
	var cell := ""
	var i := 0
	while i < text.length():
		var c := text[i]
		if c == "\\" and i + 1 < text.length() and text[i + 1] == "|":
			cell += "|"
			i += 2
		elif c == "`":
			var run = _run_length(text, i, "`")
			var close = text.find("`".repeat(run), i + run)
			var end = i + run if close == -1 else close + run
			# The escape is the table's, so it comes off even where code would keep a backslash.
			cell += text.substr(i, end - i).replace("\\|", "|")
			i = end
		elif c == "|":
			cells.append(cell.strip_edges())
			cell = ""
			i += 1
		else:
			cell += c
			i += 1
	# Text after the last pipe is a cell; nothing after it means the pipe only closed the row.
	if cell.strip_edges() != "":
		cells.append(cell.strip_edges())
	return cells

#endregion

#region prose

## Groups a prose block's lines into paragraphs, headings and lists. "gap" records a blank line
## before the element, which is all that survives of the source's vertical spacing.
static func _elements(text:String) -> Array:
	var elements:Array = []
	var blank := false
	var open := ""
	for line in text.split("\n"):
		if line.strip_edges() == "":
			blank = true
			continue

		var heading = _re(_RE_HEADING).search(line)
		if heading:
			elements.append({"kind":"h", "gap":blank, "level":heading.get_string(1).length(),
				"text":heading.get_string(2)})
			open = ""
			blank = false
			continue

		var list = _re(_RE_LIST).search(line)
		if list:
			if open != "list":
				elements.append({"kind":"list", "gap":blank, "items":[]})
				open = "list"
			elements[-1].items.append({"indent":_indent_width(line), "ordered":list.get_string(3) != "",
				"number":list.get_string(3).to_int(), "lines":[list.get_string(4)]})
			blank = false
			continue

		# After a blank line only an indented line still belongs to the item above it.
		if open == "list" and (not blank or _indent_width(line) >= 2):
			var item_lines:Array = elements[-1].items[-1].lines
			if blank:
				item_lines.append("")
			item_lines.append(line)
		elif open == "p" and not blank:
			elements[-1].lines.append(line)
		else:
			elements.append({"kind":"p", "gap":blank, "lines":[line]})
			open = "p"
		blank = false
	return elements


## Reflows source lines into one run: a soft line break is a space, a hard one (two trailing
## spaces, a trailing backslash, or an empty entry) becomes [param hard_break].
static func _join_lines(lines:Array, hard_break:String) -> String:
	var out := ""
	var separator := ""
	for line:String in lines:
		var text = line.strip_edges()
		if text == "":
			separator = hard_break
			continue
		out += separator
		separator = " "
		if text.ends_with("\\"):
			text = text.left(-1)
			separator = hard_break
		elif line.ends_with("  "):
			separator = hard_break
		out += text
	return out


## Leading whitespace width, a tab counting as four.
static func _indent_width(line:String) -> int:
	var width := 0
	for c in line:
		if c == "\t":
			width += 4
		elif c == " ":
			width += 1
		else:
			break
	return width


## Nesting level per item. An item nests under the one above only when indented two or more
## past it, the narrowest indent markdown writers actually use.
static func _list_levels(items:Array) -> Array[int]:
	var levels:Array[int] = []
	var stack:Array[int] = []
	for item in items:
		while not stack.is_empty() and item.indent < stack[-1]:
			stack.pop_back()
		if stack.is_empty() or item.indent >= stack[-1] + 2:
			stack.append(item.indent)
		levels.append(stack.size() - 1)
	return levels


static func _list_bbcode(items:Array, ctx:Dictionary) -> String:
	var levels = _list_levels(items)
	# [ol] always counts from one, so a list resumed after a code block keeps its own numbers.
	if items[0].ordered and items[0].number != 1:
		return _list_numbered(items, levels, ctx)

	var out := ""
	var open:Array[bool] = []
	for i in range(items.size()):
		var ordered:bool = items[i].ordered
		while open.size() > levels[i] + 1:
			out += _list_close(open.pop_back())
		if open.size() == levels[i] + 1 and open[-1] != ordered:
			out += _list_close(open.pop_back())
		if out != "":
			out += "\n"
		if open.size() <= levels[i]:
			out += "[ol]" if ordered else "[ul]"
			open.append(ordered)
		out += _item_bbcode(items[i], ctx)
	while not open.is_empty():
		out += _list_close(open.pop_back())
	return out


static func _list_close(ordered:bool) -> String:
	return "[/ol]" if ordered else "[/ul]"


## List items with their markers written out, one indented line each.
static func _list_numbered(items:Array, levels:Array[int], ctx:Dictionary) -> String:
	var out:Array[String] = []
	for i in range(items.size()):
		var marker = "%d. " % items[i].number if items[i].ordered else "• "
		var depth = levels[i] + 1
		out.append("[indent]".repeat(depth) + marker + _item_bbcode(items[i], ctx) + "[/indent]".repeat(depth))
	return "\n".join(out)


static func _item_bbcode(item:Dictionary, ctx:Dictionary) -> String:
	var text = _join_lines(item.lines, _SOFT_BREAK)
	var task = _re(r"^\[([ xX])\]\s+").search(text)
	if task:
		var box = "☐ " if task.get_string(1) == " " else "☑ "
		return box + _inline(text.substr(task.get_end()), ctx, false)
	return _inline(text, ctx, false)

#endregion

#region inline

## [param in_link] is set for a link's own label, where another link cannot start.
static func _inline(text:String, ctx:Dictionary, in_link:bool) -> String:
	var tokens = _tokenize(text, ctx, in_link)
	_match_emphasis(tokens)
	var out := ""
	for token in tokens:
		if token.has("done"):
			out += token.done
		elif token.has("ch"):
			out += token.before + String(token.ch).repeat(token.n) + token.after
		else:
			# Whatever is left is literal, so its brackets must not read as BBCode.
			out += String(token.text).replace("[", "[lb]")
	return out


## Splits a run into literal text, finished BBCode ("done") and emphasis delimiter runs. Emitted
## tags never re-enter the text, so no part of a document can collide with the conversion itself.
static func _tokenize(text:String, ctx:Dictionary, in_link:bool) -> Array:
	var tokens:Array = []
	var literal := ""
	var i := 0
	var length := text.length()

	while i < length:
		var c := text[i]

		if c == "\\" and i + 1 < length and text[i + 1] in _PUNCTUATION:
			literal += text[i + 1]
			i += 2
			continue

		if c == "`":
			var run = _run_length(text, i, "`")
			var close = text.find("`".repeat(run), i + run)
			if close != -1:
				literal = _push_literal(tokens, literal)
				tokens.append({"done":_code_bbcode(text.substr(i + run, close - (i + run)), ctx)})
				i = close + run
				continue
			literal += "`".repeat(run)
			i += run
			continue

		if c == "[" or (c == "!" and i + 1 < length and text[i + 1] == "["):
			var is_image = c == "!"
			var link = _link_at(text, i + 1 if is_image else i, ctx)
			if not link.is_empty() and (is_image or not in_link):
				if is_image:
					# An inline image cannot be drawn in a text run, so its alt text stands in.
					literal += link.label
				else:
					literal = _push_literal(tokens, literal)
					tokens.append({"done":_link_bbcode(link.dest, _inline(link.label, ctx, true), ctx)})
				i = link.end
				continue

		if c == "<":
			var html = _re(r"\G<(?:(https?://[^\s<>]+|mailto:[^\s<>]+)>|(br\s*/?)>|(!--.*?--)>)").search(text, i)
			if html:
				literal = _push_literal(tokens, literal)
				if html.get_string(1) != "" and not in_link:
					var url = html.get_string(1)
					tokens.append({"done":_link_bbcode(url, url.trim_prefix("mailto:").replace("[", "[lb]"), ctx)})
				elif html.get_string(1) != "":
					literal += html.get_string(1)
				elif html.get_string(2) != "":
					tokens.append({"done":"\n"})
				i = html.get_end()
				continue

		if c == "h" and not in_link and (i == 0 or not _is_word(text[i - 1])):
			var bare = _re(r"\Ghttps?://[^\s<>\[\]]+").search(text, i)
			if bare:
				# Sentence punctuation after a url is the sentence's, not the url's.
				var url = bare.get_string().rstrip(".,;:!?)'\"*_~")
				literal = _push_literal(tokens, literal)
				tokens.append({"done":_link_bbcode(url, url, ctx)})
				i += url.length()
				continue

		if c == "&":
			var entity = _re(r"\G&(?:(\w+)|#(\d+));").search(text, i)
			if entity and (entity.get_string(2) != "" or _ENTITIES.has(entity.get_string(1))):
				if entity.get_string(2) != "":
					literal += String.chr(entity.get_string(2).to_int())
				else:
					literal += _ENTITIES[entity.get_string(1)]
				i = entity.get_end()
				continue

		if c == "*" or c == "_" or c == "~":
			var run = _run_length(text, i, c)
			# A single tilde is ordinary text; only a pair strikes through.
			if c != "~" or run == 2:
				literal = _push_literal(tokens, literal)
				tokens.append(_delimiter(text, i, run))
				i += run
				continue

		literal += c
		i += 1

	_push_literal(tokens, literal)
	return tokens


## Appends [param literal] as a token when it holds anything, and returns the empty accumulator.
static func _push_literal(tokens:Array, literal:String) -> String:
	if literal != "":
		tokens.append({"text":literal})
	return ""


static func _run_length(text:String, from:int, c:String) -> int:
	var run := 0
	while from + run < text.length() and text[from + run] == c:
		run += 1
	return run


static func _is_word(c:String) -> bool:
	return not (c in _WHITESPACE or c in _PUNCTUATION)


## An emphasis delimiter run and whether it may open or close, by CommonMark's flanking rules.
## The underscore's extra conditions are what keep snake_case out of italics.
static func _delimiter(text:String, at:int, run:int) -> Dictionary:
	var c := text[at]
	var prev := text[at - 1] if at > 0 else " "
	var next := text[at + run] if at + run < text.length() else " "
	var prev_space = prev in _WHITESPACE
	var next_space = next in _WHITESPACE
	var prev_punct = prev in _PUNCTUATION
	var next_punct = next in _PUNCTUATION
	var left = not next_space and (not next_punct or prev_space or prev_punct)
	var right = not prev_space and (not prev_punct or next_space or next_punct)
	var can_open = left
	var can_close = right
	if c == "_":
		can_open = left and (not right or prev_punct)
		can_close = right and (not left or next_punct)
	return {"ch":c, "n":run, "open":can_open, "close":can_close, "before":"", "after":""}


## Pairs delimiter runs into tags. Characters left unpaired stay in "n" and render literally;
## tags collect in "before"/"after" so they land on the content side of those characters.
static func _match_emphasis(tokens:Array) -> void:
	for closer_index in range(tokens.size()):
		var closer:Dictionary = tokens[closer_index]
		if not closer.has("ch") or not closer.close:
			continue
		while closer.n > 0:
			var opener_index := closer_index - 1
			while opener_index >= 0:
				var candidate:Dictionary = tokens[opener_index]
				if candidate.has("ch") and candidate.ch == closer.ch and candidate.open and candidate.n > 0:
					break
				opener_index -= 1
			if opener_index < 0:
				break

			var opener:Dictionary = tokens[opener_index]
			var used := 2 if opener.n >= 2 and closer.n >= 2 else 1
			var tag := "s"
			if closer.ch != "~":
				tag = "b" if used == 2 else "i"
			elif used != 2:
				break
			opener.n -= used
			closer.n -= used
			opener.after = "[%s]" % tag + opener.after
			closer.before += "[/%s]" % tag
			# Runs inside the new pair can no longer match anything outside it.
			for between in range(opener_index + 1, closer_index):
				if tokens[between].has("ch"):
					tokens[between].open = false
					tokens[between].close = false


## The link starting at the "[" at [param at]: its label, destination and end offset. Empty when
## the bracket opens no link. The label may nest brackets, as a linked image does.
static func _link_at(text:String, at:int, ctx:Dictionary) -> Dictionary:
	var depth := 0
	var close := -1
	var i := at
	while i < text.length():
		var c := text[i]
		if c == "\\":
			i += 1
		elif c == "[":
			depth += 1
		elif c == "]":
			depth -= 1
			if depth == 0:
				close = i
				break
		i += 1
	if close == -1:
		return {}
	var label := text.substr(at + 1, close - at - 1)

	var dest = _re(_RE_LINK_DEST).search(text, close + 1)
	if dest:
		return {"label":label, "dest":dest.get_string(1).trim_prefix("<").trim_suffix(">"), "end":dest.get_end()}

	var refs:Dictionary = ctx.get(CTX_REFS, {})
	if refs.is_empty():
		return {}
	# "[label][id]", "[label][]" and a bare "[label]" all name a reference definition.
	var end := close + 1
	var id := label
	var reference = _re(r"\G\[([^\]]*)\]").search(text, close + 1)
	if reference:
		end = reference.get_end()
		if reference.get_string(1).strip_edges() != "":
			id = reference.get_string(1)
	id = id.strip_edges().to_lower()
	if not refs.has(id):
		return {}
	return {"label":label, "dest":refs[id], "end":end}


static func _code_bbcode(body:String, ctx:Dictionary) -> String:
	# One space of padding is how a span holds a backtick at its edge; it is not content.
	if body.length() > 2 and body.begins_with(" ") and body.ends_with(" ") and body.strip_edges() != "":
		body = body.substr(1, body.length() - 2)
	var out = "[code]" + body.replace("[", "[lb]") + "[/code]"
	if ctx.has(CTX_CODE_FG):
		out = "[color=%s]%s[/color]" % [ctx[CTX_CODE_FG], out]
	if ctx.has(CTX_CODE_BG):
		# A space each side, so the background does not sit flush against the glyphs.
		out = "[bgcolor=%s] %s [/bgcolor]" % [ctx[CTX_CODE_BG], out]
	return out


## [param label] is finished BBCode. Brackets in the url would end the tag early.
static func _link_bbcode(dest:String, label:String, ctx:Dictionary) -> String:
	var out = "[url=%s]%s[/url]" % [dest.replace("[", "%5B").replace("]", "%5D"), label]
	if ctx.has(CTX_LINK):
		out = "[color=%s]%s[/color]" % [ctx[CTX_LINK], out]
	return out


## Heading text with its inline markers removed, for titles and other plain-text uses.
static func _strip_inline_markers(text:String) -> String:
	text = _re(r"!?\[([^\]]*)\]\([^)]*\)").sub(text, "$1", true)
	text = text.replace("**", "").replace("__", "").replace("~~", "").replace("`", "")
	return text.strip_edges()


static func _re(pattern:String) -> RegEx:
	var re = _re_cache.get(pattern)
	if re == null:
		re = RegEx.create_from_string(pattern)
		_re_cache[pattern] = re
	return re

#endregion

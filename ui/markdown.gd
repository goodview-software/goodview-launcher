extends RefCounted
## Markdown léger -> BBCode (RichTextLabel) : gras, italique, titres, listes, citations, code en ligne, liens.
## Les blocs de code ``` sont séparés par blocks() pour être affichés avec un bouton Copier.


## Découpe en blocs [{type:"text"|"code", lang, text}] ; un bloc non fermé (streaming) est traité comme du code.
static func blocks(src: String) -> Array:
	var out: Array = []
	var cur: PackedStringArray = []
	var in_code := false
	var lang := ""
	for line in src.split("\n"):
		if line.strip_edges(true, false).begins_with("```"):
			if in_code:
				out.append({"type": "code", "lang": lang, "text": "\n".join(cur)})
				cur = []
				in_code = false
			else:
				if not cur.is_empty() and "\n".join(cur).strip_edges() != "":
					out.append({"type": "text", "lang": "", "text": "\n".join(cur)})
				cur = []
				in_code = true
				lang = line.strip_edges().trim_prefix("```").strip_edges()
		else:
			cur.append(line)
	if in_code:
		out.append({"type": "code", "lang": lang, "text": "\n".join(cur), "open": true})
	elif not cur.is_empty() and "\n".join(cur).strip_edges() != "":
		out.append({"type": "text", "lang": "", "text": "\n".join(cur)})
	return out


static func esc(s: String) -> String:
	return s.replace("[", "\u0001").replace("]", "\u0002").replace("\u0001", "[lb]").replace("\u0002", "[rb]")


static func _inline(s: String, accent: String) -> String:
	var parts := s.split("`")
	var out := ""
	for i in parts.size():
		if i % 2 == 1 and i < parts.size() - 1:
			out += "[code]" + esc(parts[i]) + "[/code]"
		elif i % 2 == 1:
			out += "`" + esc(parts[i])  # backtick non fermé
		else:
			out += _fmt(esc(parts[i]), accent)
	return out


static func _fmt(t: String, accent: String) -> String:
	var r := RegEx.new()
	r.compile("\\*\\*(.+?)\\*\\*")
	t = r.sub(t, "[b]$1[/b]", true)
	r.compile("(?<![\\*\\w])\\*(?![\\s\\*])(.+?)(?<![\\s\\*])\\*(?![\\*\\w])")
	t = r.sub(t, "[i]$1[/i]", true)
	r.compile("(?<![\\w])_(?![\\s_])(.+?)(?<![\\s_])_(?![\\w])")
	t = r.sub(t, "[i]$1[/i]", true)
	r.compile("~~(.+?)~~")
	t = r.sub(t, "[s]$1[/s]", true)
	r.compile("\\[lb\\](.+?)\\[rb\\]\\((https?://[^)\\s]+)\\)")
	t = r.sub(t, "[color=#%s][url=$2]$1[/url][/color]" % accent, true)
	return t


## Convertit un bloc de texte Markdown en BBCode.
static func to_bbcode(src: String, accent := "4de1b4") -> String:
	var out: PackedStringArray = []
	for line in src.split("\n"):
		var t := line.strip_edges(false, true)
		var ind := t.length() - t.strip_edges(true, false).length()
		var s := t.strip_edges(true, false)
		if s.begins_with("#"):
			var n := 0
			while n < s.length() and s[n] == "#":
				n += 1
			if n <= 6 and s.length() > n and s[n] == " ":
				var sizes := [0, 24, 21, 19, 17, 16, 16]
				out.append("[font_size=%d][b]%s[/b][/font_size]" % [sizes[n], _inline(s.substr(n + 1), accent)])
				continue
		if s in ["---", "***", "___"]:
			out.append("[color=#55606e]──────────[/color]")
		elif s.begins_with("- ") or s.begins_with("* ") or s.begins_with("+ "):
			out.append(" ".repeat(ind) + "  [color=#%s]•[/color] %s" % [accent, _inline(s.substr(2), accent)])
		elif RegEx.create_from_string("^\\d+[.)] ").search(s) != null:
			var dot := s.find(" ")
			out.append(" ".repeat(ind) + "  [color=#%s]%s[/color] %s" % [accent, esc(s.substr(0, dot)), _inline(s.substr(dot + 1), accent)])
		elif s.begins_with("> "):
			out.append("[color=#8892a0]▍ [i]%s[/i][/color]" % _inline(s.substr(2), accent))
		else:
			out.append(" ".repeat(ind) + _inline(s, accent))
	return "\n".join(out)


## Ajoute le curseur clignotant de streaming (affiché) à la fin du texte.
static func esc_cursor(text: String, live: bool) -> String:
	return text + (" ▍" if live else "")

extends Node
## Orchestration : un assistant répond en streaming et peut en solliciter un autre (outil ask_assistant ;
## repli texte <<ask:Nom>> question <</ask>> si le modèle n'a pas les tools). Exécution séquentielle (un seul
## modèle chargé à la fois), garde-fous : profondeur max, pas d'auto-appel ni de boucle, budget d'appels et de jetons.
##
## Événements (signal event(kind, d)) :
##   speaker {ai, mode}            mode : think | talk | call | listen | idle
##   token {id, text}              id = -1 pour le fil principal, sinon numéro de la carte de délégation
##   card_open {id, parent, from, to, question}   card_done {id, answer}
##   notice {text}                 info discrète (garde-fou, repli texte…)
##   done {text, rate}             fin normale ; error {kind, msg} ; stopped {}

signal event(kind: String, d: Dictionary)

const Ollama := preload("res://core/ollama.gd")
const U := preload("res://ui/universe.gd")
const MAX_DEPTH := 2  # chaîne maximale : A -> B -> C
const MAX_CALLS := 4  # délégations par message utilisateur
const MAX_ROUNDS := 3  # tours d'outils par assistant
const SUB_TOKENS := 700  # jetons max par réponse déléguée
const ANSWER_CAP := 3000  # caractères renvoyés à l'appelant

var ollama: Node
var extra := ""  # consignes personnalisées de l'utilisateur (ajoutées au prompt système)
var allow := true  # réglage « Autoriser les assistants à s'appeler »
var resolve_model := func(_ai: int) -> String: return ""
var opts := {"temperature": 0.7, "num_ctx": 4096}
var running := false
var stopped := false
var calls_used := 0
var next_id := 0
var cards: Array = []  # [{id,parent,from,to,question,answer}]
var current: Ollama.Req


# ------------------------------------------------------------------ Fonctions pures

static func tool_schema(except: Array) -> Array:
	var names: Array = []
	for i in U.count():
		if i not in except:
			names.append(U.get_u(i).name)
	return [{"type": "function", "function": {
		"name": "ask_assistant",
		"description": "Demande à un assistant spécialisé de répondre à une question. Experts : " + U.team_list(-1),
		"parameters": {"type": "object", "properties": {
			"nom": {"type": "string", "enum": names, "description": "Nom de l'assistant sollicité"},
			"question": {"type": "string", "description": "Question complète et autonome (inclure le contexte utile)"}},
			"required": ["nom", "question"]}}}]


## Repli texte : extrait {clean, asks:[{name, question}]} des balises <<ask:Nom>> question <</ask>>.
static func parse_ask(text: String) -> Dictionary:
	var asks: Array = []
	var re := RegEx.create_from_string("(?s)<<ask:\\s*([^>\\s]+?)\\s*>>(.*?)<</ask>>")
	for m in re.search_all(text):
		asks.append({"name": m.get_string(1), "question": m.get_string(2).strip_edges()})
	var clean := re.sub(text, "", true)
	var open := clean.find("<<ask")
	if open >= 0:
		var rest := clean.substr(open)
		var re2 := RegEx.create_from_string("(?s)^<<ask:\\s*([^>\\s]+?)\\s*>>(.*)$")
		var m2 := re2.search(rest)
		if m2 != null and m2.get_string(2).strip_edges() != "":
			asks.append({"name": m2.get_string(1), "question": m2.get_string(2).replace("<</ask>", "").strip_edges()})
		clean = clean.substr(0, open)
	return {"clean": clean.strip_edges(), "asks": asks}


## Texte à afficher pendant le streaming : masque les balises <<ask…>> (même partielles).
static func visible_text(text: String) -> String:
	var i := text.find("<<ask")
	if i >= 0:
		return text.substr(0, i).strip_edges(false, true)
	for k in [4, 3, 2, 1]:
		if text.length() >= k and "<<ask".begins_with(text.substr(text.length() - k)):
			return text.substr(0, text.length() - k).strip_edges(false, true)
	return text


## Garde-fous : renvoie "" si l'appel est permis, sinon la raison du refus.
static func guard(chain: Array, to: int, depth: int, used: int) -> String:
	if to < 0:
		return "Assistant inconnu."
	if chain.is_empty() == false and to == chain.back():
		return "Un assistant ne peut pas s'appeler lui-même."
	if to in chain:
		return "Boucle évitée (%s est déjà dans la chaîne)." % U.get_u(to).name
	if depth >= MAX_DEPTH:
		return "Profondeur maximale atteinte."
	if used >= MAX_CALLS:
		return "Budget d'appels épuisé."
	return ""


# ------------------------------------------------------------------ Exécution

func stop() -> void:
	stopped = true
	if current != null:
		current.cancel()


## history : messages API déjà construits (sans système). ai : assistant principal.
func run(ai: int, history: Array) -> void:
	running = true
	stopped = false
	calls_used = 0
	cards.clear()
	var t0 := Time.get_ticks_msec()
	var res: Dictionary = await _assistant(ai, history, 0, [ai], -1, true)
	running = false
	current = null
	if stopped:
		event.emit("speaker", {"ai": ai, "mode": "idle"})
		event.emit("stopped", {})
	elif res.has("error"):
		event.emit("speaker", {"ai": ai, "mode": "error"})
		event.emit("error", res.error)
	else:
		var secs := maxf(0.1, (Time.get_ticks_msec() - t0) / 1000.0)
		event.emit("speaker", {"ai": ai, "mode": "done"})
		event.emit("done", {"text": res.text, "rate": float(res.tokens) / secs})


## Un tour d'assistant (avec boucle d'outils). Renvoie {text, tokens} ou {error:{kind,msg}}.
func _assistant(ai: int, history: Array, depth: int, chain: Array, sink: int, top: bool) -> Dictionary:
	var model: String = resolve_model.call(ai)
	if model == "":
		return {"error": {"kind": "model_missing", "msg": "Aucun modèle disponible."}}
	var can := allow and depth < MAX_DEPTH
	var sys := U.system_prompt(ai, can)
	if extra.strip_edges() != "":
		sys += extra.strip_edges()
	var msgs: Array = ([{"role": "system", "content": sys}] if sys != "" else []) + history
	var text_mode := not Ollama.supports_tools(model)
	var total := ""
	var tokens := 0
	var u := U.get_u(ai)
	var o := opts.duplicate()
	o["temperature"] = float(opts.get("user_temp_v", u.temp)) if opts.get("user_temp", false) else float(u.temp)
	o.erase("user_temp")
	o.erase("user_temp_v")
	if not top:
		o["num_predict"] = SUB_TOKENS
	if can and text_mode and not msgs.is_empty():
		msgs[0].content += "\nSi tu as besoin d'un collègue, écris exactement : <<ask:Nom>> question complète <</ask>> puis arrête-toi."
	for round_i in MAX_ROUNDS + 1:
		var tools_on := can and calls_used < MAX_CALLS and round_i < MAX_ROUNDS
		event.emit("speaker", {"ai": ai, "mode": "think"})
		var req: Ollama.Req = ollama.chat(model, msgs, o, _tools(chain) if tools_on and not text_mode else [])
		current = req
		var st := {"text": "", "tokens": 0, "calls": []}
		var prefix := total + "\n\n" if total != "" else ""
		req.line.connect(func(d: Dictionary):
			var m: Dictionary = d.get("message", {})
			var c := str(m.get("content", ""))
			if c != "":
				st.text += c
				st.tokens += 1
				var shown: String = Ollama.strip_think(st.text) if "<think>" in st.text else st.text
				if tools_on and text_mode:
					shown = visible_text(shown)
				event.emit("speaker", {"ai": ai, "mode": "talk"})
				event.emit("token", {"id": sink, "text": prefix + shown})
			for tc in m.get("tool_calls", []):
				st.calls.append(tc))
		var r: Array = await req.finished
		tokens += int(st.tokens)
		var text: String = st.text
		var tcalls: Array = st.calls
		if stopped:
			return {"text": total, "tokens": tokens}
		if not r[0]:
			if r[1] == "unsupported" or r[1] == "memory":
				ollama.bad_models.append(model)
				var alt: String = resolve_model.call(ai)
				if alt != "" and alt != model:
					event.emit("notice", {"text": "%s ne se charge pas : bascule sur %s." % [model, alt], "toast": true})
					model = alt
					text_mode = not Ollama.supports_tools(model)
					continue
			if r[1] == "no_tools" and not text_mode:
				text_mode = true
				event.emit("notice", {"text": "Ce modèle n'a pas les tools : repli texte."})
				continue
			return {"error": {"kind": r[1], "msg": r[2]}}
		text = Ollama.strip_think(text)
		var asks: Array = []
		if tools_on and text_mode:
			var pa := parse_ask(text)
			text = pa.clean
			asks = pa.asks
		else:
			for tc in tcalls:
				var f: Dictionary = tc.get("function", {})
				if f.get("name", "") == "ask_assistant":
					var a = f.get("arguments", {})
					if a is String:
						a = JSON.parse_string(a)
					if a is Dictionary:
						asks.append({"name": str(a.get("nom", a.get("name", ""))), "question": str(a.get("question", ""))})
		if text.strip_edges() != "":
			total += ("\n\n" if total != "" else "") + text.strip_edges()
		event.emit("token", {"id": sink, "text": total})
		if asks.is_empty():
			return {"text": total, "tokens": tokens}
		# --- délégations (séquentielles)
		var asst_msg := {"role": "assistant", "content": text}
		if not text_mode:
			asst_msg["tool_calls"] = clean_calls(tcalls)
		msgs.append(asst_msg)
		var answers: PackedStringArray = []
		for a in asks:
			var to := U.find(str(a.name))
			var why := guard(chain, to, depth, calls_used)
			var ans := ""
			if why != "":
				ans = "Refusé : " + why
				event.emit("notice", {"text": ans})
			else:
				calls_used += 1
				ans = await _delegate(ai, to, str(a.question), depth, chain, sink)
				if stopped:
					return {"text": total, "tokens": tokens}
			if text_mode:
				answers.append("Réponse de %s : %s" % [str(a.name), ans])
			else:
				msgs.append({"role": "tool", "content": ans, "tool_name": "ask_assistant"})
		if text_mode:
			msgs.append({"role": "user", "content": "\n".join(answers) + "\nSynthétise maintenant pour l'utilisateur."})
	return {"text": total, "tokens": tokens}


## Ne renvoie à Ollama que name + arguments (l'index relu en nombre flottant fait échouer sa désérialisation).
static func clean_calls(calls: Array) -> Array:
	var out: Array = []
	for tc in calls:
		var f: Dictionary = tc.get("function", {})
		out.append({"function": {"name": f.get("name", ""), "arguments": f.get("arguments", {})}})
	return out


func _tools(chain: Array) -> Array:
	return tool_schema(chain)


func _delegate(from: int, to: int, question: String, depth: int, chain: Array, parent: int) -> String:
	var id := next_id
	next_id += 1
	var card := {"id": id, "parent": parent, "from": from, "to": to, "question": question, "answer": ""}
	cards.append(card)
	event.emit("speaker", {"ai": from, "mode": "call"})
	event.emit("speaker", {"ai": to, "mode": "listen"})
	event.emit("card_open", card.duplicate())
	var sub: Dictionary = await _assistant(to, [{"role": "user", "content": question}], depth + 1, chain + [to], id, false)
	var ans := ""
	if sub.has("error"):
		ans = "(Échec de %s : %s)" % [U.get_u(to).name, sub.error.msg]
	else:
		ans = str(sub.text)
	card.answer = ans
	event.emit("card_done", {"id": id, "answer": ans})
	event.emit("speaker", {"ai": to, "mode": "idle"})
	return ans.left(ANSWER_CAP)

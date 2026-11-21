extends Node
## Client Ollama local (HTTPClient, lu image par image sans bloquer l'UI) : /api/chat en streaming NDJSON,
## /api/tags, /api/pull. Aucune donnée ne quitte le PC (URL par défaut : http://127.0.0.1:11434).

const SELF := preload("res://core/ollama.gd")
const DEFAULT_URL := "http://127.0.0.1:11434"
const CONNECT_TIMEOUT := 6.0
const FIRST_TIMEOUT := 180.0  # chargement d'un gros modèle en mémoire
const IDLE_TIMEOUT := 60.0

var base_url := DEFAULT_URL
var streams: Array = []


## Une requête en cours. Signaux : line(d) pour chaque objet JSON reçu, finished(ok, kind, msg).
## kind : "" | "offline" | "model_missing" | "no_tools" | "timeout" | "http" | "cancel"
class Req extends RefCounted:
	signal line(d: Dictionary)
	signal finished(ok: bool, kind: String, msg: String)
	var http := HTTPClient.new()
	var method := HTTPClient.METHOD_POST
	var path := ""
	var body := ""
	var host := ""
	var port := 80
	var tls := false
	var phase := 0  # 0 connexion, 1 envoi, 2 réponse, 3 fini
	var carry := ""
	var raw := PackedByteArray()
	var code := 0
	var got_any := false
	var t := 0.0
	var idle := 0.0
	var is_done := false
	var errbuf := ""

	func cancel() -> void:
		_end(false, "cancel", "Annulé")

	func _end(ok: bool, kind: String, msg: String) -> void:
		if is_done:
			return
		is_done = true
		http.close()
		if ok and carry.strip_edges() != "":
			_emit_lines([carry])
			carry = ""
		finished.emit(ok, kind, msg)

	func _emit_lines(lines: Array) -> void:
		for l in lines:
			var s := str(l).strip_edges()
			if s == "":
				continue
			var j := JSON.new()
			if j.parse(s) == OK and j.data is Dictionary:
				line.emit(j.data)

	func step(dt: float) -> void:
		if is_done:
			return
		t += dt
		idle += dt
		http.poll()
		var st := http.get_status()
		match st:
			HTTPClient.STATUS_CANT_RESOLVE, HTTPClient.STATUS_CANT_CONNECT, HTTPClient.STATUS_CONNECTION_ERROR, HTTPClient.STATUS_TLS_HANDSHAKE_ERROR:
				_end(false, "offline", "Ollama est injoignable.")
			HTTPClient.STATUS_DISCONNECTED:
				if phase >= 2:
					_finish()
				else:
					_end(false, "offline", "Connexion fermée.")
			HTTPClient.STATUS_CONNECTED:
				if phase == 0:
					phase = 1
					var hs := PackedStringArray(["Content-Type: application/json", "Accept: application/x-ndjson"])
					var e := http.request(method, path, hs, body)
					if e != OK:
						_end(false, "offline", "Requête impossible.")
						return
					idle = 0.0
				elif phase == 2:
					_finish()
			HTTPClient.STATUS_BODY:
				phase = 2
				if code == 0:
					code = http.get_response_code()
				var n := 0
				while http.get_status() == HTTPClient.STATUS_BODY and n < 40:
					http.poll()
					var chunk := http.read_response_body_chunk()
					if chunk.size() == 0:
						break
					got_any = true
					idle = 0.0
					_on_bytes(chunk)
					n += 1
			HTTPClient.STATUS_REQUESTING:
				pass
		if is_done:
			return
		if phase == 0 and t > CONNECT_TIMEOUT:
			_end(false, "offline", "Ollama est injoignable.")
		elif phase >= 1 and idle > (IDLE_TIMEOUT if got_any else FIRST_TIMEOUT):
			_end(false, "timeout", "Délai dépassé.")

	func _finish() -> void:
		if code in [0, 200]:
			_end(true, "", "")
		else:
			var fi := fail_info()
			_end(false, fi[0], fi[1])

	func _on_bytes(chunk: PackedByteArray) -> void:
		if code != 200:
			errbuf += chunk.get_string_from_utf8()
			return
		raw.append_array(chunk)
		# on ne décode que jusqu'au dernier saut de ligne (un caractère UTF-8 peut être coupé)
		var cut := raw.size() - 1
		while cut >= 0 and raw[cut] != 10:
			cut -= 1
		if cut < 0:
			return
		var head := raw.slice(0, cut + 1).get_string_from_utf8()
		raw = raw.slice(cut + 1)
		var r := SELF.split_lines(carry + head)
		carry = r.rest
		_emit_lines(r.lines)

	## Après la fin : message d'erreur HTTP lisible.
	func fail_info() -> Array:
		var msg := errbuf
		var d = JSON.parse_string(errbuf)
		if d is Dictionary and d.has("error"):
			msg = str(d.error)
		var kind := "http"
		if code == 404 or "not found" in msg.to_lower():
			kind = "model_missing"
		elif "does not support tools" in msg.to_lower():
			kind = "no_tools"
		return [kind, msg if msg != "" else "Erreur HTTP %d" % code]


# ------------------------------------------------------------------ Fonctions pures (testables)

## Sépare un tampon NDJSON : {lines: [complètes], rest: fragment incomplet}.
static func split_lines(buf: String) -> Dictionary:
	var parts := buf.split("\n")
	var rest := parts[parts.size() - 1]
	parts.remove_at(parts.size() - 1)
	return {"lines": Array(parts), "rest": rest}


## Parse un lot NDJSON complet en tableau de dictionnaires (lignes invalides ignorées).
static func parse_ndjson(text: String) -> Array:
	var out: Array = []
	for l in text.split("\n"):
		if l.strip_edges() == "":
			continue
		var j := JSON.new()
		if j.parse(l) == OK and j.data is Dictionary:
			out.append(j.data)
	return out


## {host, port, tls, ok} depuis une URL http(s)://hôte[:port].
static func parse_url(url: String) -> Dictionary:
	var u := url.strip_edges().trim_suffix("/")
	var tls := false
	if u.begins_with("https://"):
		tls = true
		u = u.substr(8)
	elif u.begins_with("http://"):
		u = u.substr(7)
	var hp := u.split("/")[0]
	var port := 443 if tls else 80
	var host := hp
	if ":" in hp:
		host = hp.get_slice(":", 0)
		port = hp.get_slice(":", 1).to_int()
	if port == 0:
		port = 11434
	return {"host": host, "port": port, "tls": tls, "ok": host != ""}


## think:false pour les modèles de raisonnement qui l'acceptent (qwen3, deepseek-r1) ; -1 = ne pas envoyer.
static func wants_think_off(model: String) -> bool:
	var m := model.to_lower()
	return "qwen3" in m or "deepseek-r1" in m


static func supports_tools(model: String) -> bool:
	var m := model.to_lower()
	if "vision" in m or "gemma" in m or "coder" in m and "qwen2.5" not in m:
		return false
	for k in ["llama3.1", "llama3.2", "llama3.3", "qwen3", "qwen2.5", "mistral", "mixtral", "command-r", "firefunction", "granite3"]:
		if k in m:
			return true
	return false


## Retire les blocs <think>…</think> (y compris non terminé) d'un texte.
static func strip_think(text: String) -> String:
	var s := text
	while true:
		var a := s.find("<think>")
		if a < 0:
			break
		var b := s.find("</think>", a)
		if b < 0:
			s = s.substr(0, a)
			break
		s = s.substr(0, a) + s.substr(b + 8)
	return s.strip_edges(true, false) if s != text else s


static func fmt_size(bytes: float) -> String:
	if bytes >= 1e9:
		return "%.1f Go" % (bytes / 1e9)
	return "%.0f Mo" % (bytes / 1e6)


# ------------------------------------------------------------------ Requêtes

func _start(method: int, path: String, body: Dictionary) -> Req:
	var r := Req.new()
	var u := parse_url(base_url)
	r.method = method
	r.path = path
	r.body = JSON.stringify(body) if not body.is_empty() else ""
	r.host = u.host
	r.port = u.port
	r.tls = u.tls
	var e := r.http.connect_to_host(r.host, r.port, TLSOptions.client() if r.tls else null)
	streams.append(r)
	if e != OK:
		(func(): r._end(false, "offline", "Ollama est injoignable.")).call_deferred()
	return r


## Conversation en streaming. opts : temperature, num_ctx, num_predict ; tools : Array (optionnel).
func chat(model: String, messages: Array, opts := {}, tools := [], stream := true) -> Req:
	var o := {}
	for k in ["temperature", "num_ctx", "num_predict"]:
		if opts.has(k):
			o[k] = opts[k]
	var b := {"model": model, "messages": messages, "stream": stream, "options": o}
	if wants_think_off(model):
		b["think"] = false
	if not tools.is_empty():
		b["tools"] = tools
	return _wrap(_start(HTTPClient.METHOD_POST, "/api/chat", b))


func tags() -> Req:
	return _wrap(_start(HTTPClient.METHOD_GET, "/api/tags", {}))


func pull(model: String) -> Req:
	return _wrap(_start(HTTPClient.METHOD_POST, "/api/pull", {"model": model, "stream": true}))


## Complète le résultat d'erreur HTTP avant d'émettre finished (le Req émet déjà ; on traduit via un relais).
func _wrap(r: Req) -> Req:
	return r


func _process(dt: float) -> void:
	for r in streams.duplicate():
		var req: Req = r
		req.step(dt)
		if req.is_done:
			streams.erase(r)


## Attend la fin et renvoie [ok, kind, msg, lignes] (pour les appels simples non streamés).
func collect(r: Req) -> Array:
	var lines: Array = []
	r.line.connect(func(d): lines.append(d))
	var res: Array = await r.finished
	return [res[0], res[1], res[2], lines]

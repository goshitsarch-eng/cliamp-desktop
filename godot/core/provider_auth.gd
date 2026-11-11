class_name ProviderAuth
extends RefCounted
## Pure state rules of the browser sign-in flow, from provider_sign_in.dart.
## State dictionary: {state, url, error, cancellable, cancel_requested}.


static func initial() -> Dictionary:
	return {
		"state": "authenticating",
		"url": "",
		"error": "",
		"cancellable": false,
		"cancel_requested": false,
		"code_required": false,
		"prompt": "",
	}


static func is_terminal(state: String) -> bool:
	return state in ["authenticated", "canceled", "failed"]


## Applies a provider.auth.status `auth` object to the flow state.
static func reduce(current: Dictionary, auth: Dictionary) -> Dictionary:
	var s := current.duplicate()
	var code_required: bool = auth.get("code_required") == true or s.get("code_required") == true
	s["code_required"] = code_required
	s["prompt"] = Util.text(auth.get("prompt"), Util.text(s.get("prompt")))
	var next := Util.text(auth.get("state"), s["state"])
	if s["state"] == "submitting_code" and next != "authenticated":
		return s
	if code_required and next in ["idle", "failed", "canceled"] and s["state"] != "authenticated":
		s["state"] = "awaiting_code"
	elif next != "idle" or s["state"] != "authenticating":
		s["state"] = "canceling" if s["cancel_requested"] and next == "authenticating" else next
	s["cancellable"] = auth.get("cancellable") == true
	s["url"] = Util.text(auth.get("url")) if s["state"] == "authenticating" else ""
	if s["state"] == "failed":
		s["error"] = Util.single_line(auth.get("error"), "The provider could not complete sign-in.")
	elif s["state"] == "canceled" or s["state"] == "authenticated":
		s["error"] = ""
	return s


## Only plain http(s) links with a valid host (and no userinfo) are handed to the OS.
static func is_http_url(url: String) -> bool:
	var lower := url.to_lower()
	var rest := ""
	if lower.begins_with("https://"):
		rest = url.substr(8)
	elif lower.begins_with("http://"):
		rest = url.substr(7)
	else:
		return false
	for i in url.length():
		var c := url.unicode_at(i)
		if c <= 32 or c == 127:
			return false
	var end := rest.length()
	for ch in ["/", "?", "#"]:
		var at := rest.find(ch)
		if at >= 0:
			end = mini(end, at)
	var authority := rest.substr(0, end)
	if authority.is_empty() or authority.contains("@") or authority.contains("\\"):
		return false
	var host := authority
	var port := ""
	if authority.begins_with("["):
		var close := authority.find("]")
		if close <= 1:
			return false
		host = authority.substr(1, close - 1)
		var tail := authority.substr(close + 1)
		if not tail.is_empty():
			if not tail.begins_with(":"):
				return false
			port = tail.substr(1)
	elif authority.count(":") > 1:
		return false
	elif authority.contains(":"):
		var idx := authority.find(":")
		host = authority.substr(0, idx)
		port = authority.substr(idx + 1)
		if port.is_empty():
			return false
	if host.is_empty():
		return false
	if not port.is_empty():
		if not port.is_valid_int():
			return false
		var p := port.to_int()
		if p < 1 or p > 65535:
			return false
	return true


static func message(state: String, url: String, prompt := "") -> String:
	match state:
		"authenticated":
			return "You're connected. Your account is ready to browse."
		"failed":
			return "Sign-in could not be completed."
		"canceled":
			return "Sign-in was canceled. You can try again when you're ready."
		"canceling":
			return "Canceling the provider sign-in..."
		"awaiting_code":
			return prompt if not prompt.is_empty() else "Enter the verification code from your provider to finish signing in."
		"submitting_code":
			return "Verifying your sign-in code..."
	if url.is_empty():
		return "Waiting for the provider's sign-in instructions..."
	return "Open the sign-in page, complete the steps in your browser, then return here."

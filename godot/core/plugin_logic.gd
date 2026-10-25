class_name PluginLogic
extends RefCounted
## Pure helpers for plugin management: normalizing the engine's JSON and the
## payloads of Backend.plugin_action. See pluginmgr/desktop.go.

const KEY_FORBIDDEN := " \t\r\n[]=."


## Normalized `plugins` array of a "list" result.
static func parse_plugins(result: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for raw in Util.objects(result.get("plugins")):
		var permissions: Array[String] = []
		var keys: Array[String] = []
		if raw.get("permissions") is Array:
			for p in raw["permissions"]:
				permissions.append(str(p))
		if raw.get("config_keys") is Array:
			for k in raw["config_keys"]:
				keys.append(str(k))
		out.append({
			"id": Util.text(raw.get("id")),
			"name": Util.text(raw.get("name"), Util.text(raw.get("id"))),
			"description": Util.text(raw.get("description")),
			"version": Util.text(raw.get("version")),
			"type": Util.text(raw.get("type")),
			"trust": Util.text(raw.get("trust"), "untrusted"),
			"permissions": permissions,
			"enabled": raw.get("enabled") == true,
			"config_keys": keys,
		})
	return out


## "1.0 - visualizer - trusted" without empty parts.
static func subtitle(plugin: Dictionary) -> String:
	var parts: Array[String] = []
	for k in ["version", "type", "trust"]:
		if not str(plugin[k]).is_empty():
			parts.append(plugin[k])
	return "  ·  ".join(parts)


static func is_trusted(plugin: Dictionary) -> bool:
	return plugin.get("trust") == "trusted"


## Why a setting name is not accepted, or "". The engine rejects the same set.
static func config_key_error(key: String) -> String:
	if key.strip_edges().is_empty():
		return "Enter a setting name."
	if key != key.strip_edges():
		return "Remove spaces around the setting name."
	for c in key:
		if KEY_FORBIDDEN.contains(c):
			return "Setting names cannot contain spaces, dots, brackets or equals signs."
	return ""


## Action and payload that approve a review, echoing exactly what was shown.
static func approval(review: Dictionary) -> Dictionary:
	var permissions: Array = review.get("permissions") if review.get("permissions") is Array else []
	return {
		"action": "apply" if review.get("action") == "install" else "trust",
		"values": {
			"token": review.get("token", ""),
			"source": review.get("source", ""),
			"sha256": review.get("sha256", ""),
			"permissions": permissions,
		},
	}


static func is_valid_review(review: Variant) -> bool:
	if not (review is Dictionary):
		return false
	for k in ["token", "source", "sha256", "name", "code"]:
		if not (review.get(k) is String):
			return false
	return review.get("action") in ["install", "trust"]


## Splits "plugin sub" into [plugin, sub]; missing parts are empty strings.
static func split_command(command: String) -> PackedStringArray:
	var parts := command.strip_edges().split(" ", false)
	var out := PackedStringArray(["", ""])
	if parts.size() > 0:
		out[0] = parts[0]
	if parts.size() > 1:
		out[1] = parts[1]
	return out


## Parses a JSON array of strings: {"args": Array} or {"error": String}.
static func parse_args(text: String) -> Dictionary:
	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		return {"args": []}
	var parsed: Variant = SchemaForm.parse_json(trimmed)
	if not (parsed is Array):
		return {"error": "Arguments must be a JSON array of strings."}
	for item in parsed:
		if not (item is String):
			return {"error": "Arguments must be a JSON array of strings."}
	return {"args": parsed}


## Why a plugin source cannot be installed, "" when it looks usable. Mirrors
## pluginmgr resolveSource so the page can explain it before a round trip.
static func source_error(source: String) -> String:
	var text := source.strip_edges()
	if text.is_empty():
		return "Enter a plugin source: owner/repo, gitlab:owner/repo, codeberg:owner/repo or a link ending in .lua."
	if text.contains(" ") or text.contains("
"):
		return "A plugin source cannot contain spaces."
	if text.begins_with("http://") or text.begins_with("https://"):
		var rest := text.get_slice("://", 1).split("?")[0].split("#")[0]
		var slash := rest.find("/")
		var file := rest.substr(slash + 1).trim_suffix("/").get_file() if slash >= 0 else ""
		if file.trim_suffix(".lua").is_empty():
			return "The link should end in <name>.lua."
		return ""
	var repo := text
	if ":" in text:
		var prefix := text.get_slice(":", 0)
		if not prefix in ["gitlab", "codeberg"]:
			return "Unknown prefix \"%s\". Use gitlab: or codeberg:, or leave it out for GitHub." % prefix
		repo = text.substr(prefix.length() + 1)
	repo = repo.get_slice("@", 0)
	var parts := repo.split("/")
	if parts.size() != 2 or parts[0].is_empty() or parts[1].is_empty():
		return "Use the form owner/repo, for example bjarneo/cliamp-plugin-lastfm."
	return ""

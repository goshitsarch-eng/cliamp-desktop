class_name BackendJob
extends RefCounted
## Progress of one engine operation. It holds operation names and lifecycle data
## only: never parameters, provider credentials, OAuth links or plugin source.

var id := ""
var operation := "operation"
var state := "running"
var created_at := 0.0
var finished_at := 0.0
var cancellable := true
var cancellation_requested := false
var provider := ""


func is_active() -> bool:
	return state == "queued" or state == "running"


## Parses the engine's ISO timestamps. Fractions and offsets are dropped.
static func parse_time(text: Variant, fallback: float) -> float:
	var s := str(text) if text != null else ""
	if s.length() < 19:
		return fallback
	return Time.get_unix_time_from_datetime_string(s.substr(0, 19))

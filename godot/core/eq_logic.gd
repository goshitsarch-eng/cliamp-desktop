class_name EqLogic
extends RefCounted
## Equalizer constants and value mapping from app.dart.

const BANDS := 10
const MIN_DB := -12.0
const MAX_DB := 12.0
const LABELS: PackedStringArray = ["70", "180", "320", "600", "1k", "3k", "6k", "12k", "14k", "16k"]
const PRESETS: PackedStringArray = [
	"Flat", "Rock", "Pop", "Jazz", "Classical", "Bass Boost", "Treble Boost", "Vocal",
	"Electronic", "Acoustic", "Hip-Hop", "R&B", "Loudness", "Late Night", "Podcast",
	"Small Speakers", "Custom",
]


## Ten band gains from the snapshot, padded with zeros.
static func band_values(state: Dictionary) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var raw: Variant = state.get("eq_bands")
	for i in BANDS:
		out.append(Util.number(raw[i]) if raw is Array and i < raw.size() else 0.0)
	return out


## Snaps to the 1 dB steps of the Dart slider (24 divisions) and clamps.
static func snap_db(value: float) -> float:
	return clampf(roundf(value), MIN_DB, MAX_DB)


## Position along a vertical track (0 at top) to dB; top is +12.
static func db_at(y: float, height: float) -> float:
	if height <= 0.0:
		return 0.0
	return snap_db(MAX_DB - clampf(y / height, 0.0, 1.0) * (MAX_DB - MIN_DB))


## dB to y along the track (0 at top).
static func y_of(db: float, height: float) -> float:
	return (MAX_DB - clampf(db, MIN_DB, MAX_DB)) / (MAX_DB - MIN_DB) * height


static func db_text(db: float) -> String:
	return "%d dB" % roundi(db)


static func preset_or_flat(state: Dictionary) -> String:
	var name := str(state.get("eq_preset", ""))
	if name == "Custom" and _is_flat(band_values(state)):
		return "Flat"
	return name if name in PRESETS else "Flat"


static func _is_flat(values: PackedFloat32Array) -> bool:
	for v in values:
		if not is_zero_approx(v):
			return false
	return true

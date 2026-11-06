class_name ViewPresets
extends RefCounted

## Loads and resolves data-driven aperture views:
## aperture (peephole/window/crack/hatch) x environment (porch/yard/room) x visitor.
## One JSON file, no autoload ordering.

const PATH := "res://assets/data/view_presets.json"
const ENABLED := true

static func data() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		push_error("ViewPresets: missing " + PATH)
		return {}
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		push_error("ViewPresets: cannot open " + PATH)
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	if not parsed is Dictionary:
		push_error("ViewPresets: invalid JSON in " + PATH)
		return {}
	return parsed

static func aperture_ids() -> Array:
	return data().get("apertures", {}).keys()

static func environment_ids() -> Array:
	return data().get("environments", {}).keys()

## Merge order: defaults < aperture < environment < anchor < visitor override.
## The anchor is the character placement for this aperture in this environment.
static func resolve(aperture_id: String, environment_id: String, visitor_id: String = "") -> Dictionary:
	var d := data()
	var apertures: Dictionary = d.get("apertures", {})
	var environments: Dictionary = d.get("environments", {})
	var ap: Dictionary = apertures.get(aperture_id, {})
	var env: Dictionary = environments.get(environment_id, {})

	var out: Dictionary = {}
	out.merge(d.get("defaults", {}), true)
	out.merge(ap, true)
	out.merge(env, true)

	var anchors: Dictionary = env.get("anchors", {})
	out["anchor"] = anchors.get(aperture_id, {})
	out["aperture_id"] = aperture_id
	out["environment_id"] = environment_id
	out["aperture_label"] = ap.get("label", aperture_id)
	out["environment_label"] = env.get("label", environment_id)

	if not visitor_id.is_empty():
		var overrides: Dictionary = d.get("visitor_overrides", {})
		out.merge(overrides.get(visitor_id, {}), true)

	return out

static func is_compatible(aperture_id: String, environment_id: String) -> bool:
	var environments: Dictionary = data().get("environments", {})
	var env: Dictionary = environments.get(environment_id, {})
	return aperture_id in env.get("compatible", [])

class_name Portraits
extends RefCounted
## Portraits of commanders for the command panel's cards. Placeholder art for now: a few painted generals in
## assets/portraits, in two uniforms: the Prussian spiked helmet for the German Empire, the peaked cap for every other
## nation. Each commander is given one of his nation's by his name, so he keeps the same face from game to game; every
## commander of every nation gets one. An empty slot (no general, a new army or group) shows a dark silhouette.

const CAPS := ["res://assets/portraits/general_1.jpg", "res://assets/portraits/general_2.jpg", "res://assets/portraits/general_3.jpg"]
const HELMETS := ["res://assets/portraits/german_1.jpg", "res://assets/portraits/german_2.jpg", "res://assets/portraits/german_3.jpg"]
## The portraits by nation tag; a nation not listed wears the cap.
const BY_NATION := {"GER": HELMETS}
const PLACEHOLDER := "res://assets/portraits/placeholder.jpg"

static var _cache := {}


## The portrait of a commander of a nation, by name; null only for no name.
static func for_general(person: String, tag := "") -> Texture2D:
	if person.strip_edges().is_empty():
		return null
	var pool: Array = BY_NATION.get(tag, CAPS)
	return _load(pool[absi(person.hash()) % pool.size()])


## The silhouette of an empty slot.
static func placeholder() -> Texture2D:
	return _load(PLACEHOLDER)


static func _load(path: String) -> Texture2D:
	if not _cache.has(path):
		_cache[path] = load(path)
	return _cache[path]

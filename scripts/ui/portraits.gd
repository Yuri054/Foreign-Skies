class_name Portraits
extends RefCounted
## Portraits of commanders for the command panel's cards. Placeholder art for now: a few painted generals in
## assets/portraits, each commander given one of them by his name, so he keeps the same face from game to game.

const PATHS := ["res://assets/portraits/general_1.jpg", "res://assets/portraits/general_2.jpg", "res://assets/portraits/general_3.jpg"]

static var _cache := {}


## The portrait of a commander by name, or null for none (no name).
static func for_name(person: String) -> Texture2D:
	if person.strip_edges().is_empty():
		return null
	var path: String = PATHS[absi(person.hash()) % PATHS.size()]
	if not _cache.has(path):
		_cache[path] = load(path)
	return _cache[path]


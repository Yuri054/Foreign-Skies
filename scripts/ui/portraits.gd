class_name Portraits
extends RefCounted
## Portraits of commanders for the command panel's cards. Placeholder art for now: a few painted generals in
## assets/portraits, in the uniforms of the great armies: the Prussian spiked helmet for the German Empire, the kepi for
## France, the green Russian cap for Russia, and the khaki peaked cap for every other nation. Each commander is given one of his nation's by his name, so he keeps the same face from game to game; every
## commander of every nation gets one. An army with no general, or a group with no field marshal, shows one of its nation's portraits too (`for_vacancy`); only the cards that make a new army or group keep the dark silhouette.

const CAPS := ["res://assets/portraits/general_1.jpg", "res://assets/portraits/general_2.jpg", "res://assets/portraits/general_3.jpg"]
const HELMETS := ["res://assets/portraits/german_1.jpg", "res://assets/portraits/german_2.jpg", "res://assets/portraits/german_3.jpg"]
const KEPIS := ["res://assets/portraits/french_1.jpg", "res://assets/portraits/french_2.jpg", "res://assets/portraits/french_3.jpg"]
const RUSSIAN := ["res://assets/portraits/russian_1.jpg", "res://assets/portraits/russian_2.jpg"]
## The portraits by nation tag; a nation not listed wears the khaki cap.
const BY_NATION := {"GER": HELMETS, "FRA": KEPIS, "RUS": RUSSIAN}
const PLACEHOLDER := "res://assets/portraits/placeholder.jpg"
## The field marshal of a nation, by nation tag: every marshal of that nation wears this face (for now). A nation not
## listed gives its marshals the face of a general (`for_general`).
const MARSHALS := {
	"FRA": "res://assets/portraits/marshal_fra.jpg",
	"GBR": "res://assets/portraits/marshal_gbr.jpg",
	"RUS": "res://assets/portraits/marshal_rus.jpg",
	"GER": "res://assets/portraits/marshal_ger.jpg",
}

static var _cache := {}


## The portrait of a commander of a nation, by name; null only for no name.
static func for_general(person: String, tag := "") -> Texture2D:
	if person.strip_edges().is_empty():
		return null
	var pool: Array = BY_NATION.get(tag, CAPS)
	return _load(pool[absi(person.hash()) % pool.size()])


## The portrait of a field marshal of a nation: the nation's marshal portrait (the same for all of its marshals), or, for
## a nation without one, the face a general of that name would have.
static func for_marshal(person: String, tag := "") -> Texture2D:
	if MARSHALS.has(tag):
		return _load(MARSHALS[tag])
	return for_general(person, tag)


## A portrait for a card that has no commander yet (an army without a general, a group without a
## field marshal): one of the nation's, chosen by a key (the army's or the group's name) so it keeps its
## face. Never null; the silhouette is left to the + cards that make a new army or group.
static func for_vacancy(key: String, tag := "") -> Texture2D:
	return for_general(key if not key.strip_edges().is_empty() else tag + "?", tag)


## The silhouette of an empty slot.
static func placeholder() -> Texture2D:
	return _load(PLACEHOLDER)


static func _load(path: String) -> Texture2D:
	if not _cache.has(path):
		_cache[path] = load(path)
	return _cache[path]

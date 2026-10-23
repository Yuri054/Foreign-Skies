class_name Cities
extends RefCounted
## How many people a city holds now: its size in the scenario (`pop` in cities.tsv) grown or shrunk
## by what its province has done since the game began (births, deaths, the war's dead; see
## Population). The map's models are built from this, so a city grows as its land does.

const MIN_RATIO := 0.4
const MAX_RATIO := 3.0


static func population(gs: Node, city: Dictionary) -> int:
	var id: int = city.province
	if id < 1 or id >= gs.province_population.size() or id >= gs.province_pop_base.size() or gs.province_pop_base[id] <= 0:
		return int(city.pop)
	var ratio := float(gs.province_population[id]) / float(gs.province_pop_base[id])
	return roundi(float(city.pop) * clampf(ratio, MIN_RATIO, MAX_RATIO))


## How many chimneys the city shows: one for every few factories (civilian or military) in its province, at most six.
static func chimneys(gs: Node, city: Dictionary) -> int:
	var owned: Dictionary = gs.province_buildings[city.province]
	return clampi((int(owned.get("factory", 0)) + int(owned.get("military_factory", 0))) / 3, 0, 6)

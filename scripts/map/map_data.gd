extends Node
## Loads the province bitmap and its tables (see tools/build_map.py).
## Province ids start at 1; 0 means sea and -1 means non-playable background land.

const MAP_DIR := "res://data/map/"
const NATIONS_PATH := "res://data/nations.json"
const SEA := 0
const BACKGROUND := -1
## Ground area of one bitmap pixel (see tools/build_map.py).
const KM2_PER_PX := 0.48
## Bitmap pixels per pixel of the sea zone image.
const ZONE_SCALE := 4
const BACKGROUND_COLOR := Color8(128, 128, 128)

var provinces_image: Image
var map_size: Vector2i
## Indexed by province id; element 0 is an unused placeholder.
var provinces: Array[Dictionary] = [{}]
## tag -> {name: String, color: Color}
var nations: Dictionary = {}
## id -> PackedInt32Array of neighbouring ids (land borders and sea crossings)
var adjacency: Dictionary = {}
## Sea crossings, keyed by Vector2i(lower id, higher id) -> "strait" or "sea".
var sea_links: Dictionary = {}
## Sea zones (see tools/build_sea_zones.py), indexed by zone id; element 0 is an unused
## placeholder. Each is {id, name, seed, center (a water point in bitmap pixels), area}.
var sea_zones: Array[Dictionary] = [{}]
## zone id -> PackedInt32Array of the zones it touches.
var sea_adjacency: Dictionary = {}
## province id -> {zone, zone2}: the zone a coastal province opens on, and a second one (0 if
## none). Coastal provinces whose water is in no zone (the Arctic, the Caspian) have no entry.
var port_zones: Dictionary = {}
## One pixel per ZONE_SCALE bitmap pixels; the red channel is the zone id.
var sea_zones_image: Image
## Zone id -> province ids that open on it.
var _ports_of_zone: Dictionary = {}

var _id_by_rgb: Dictionary = {}


func _init() -> void:
	_load_image()
	_load_provinces()
	_load_coastal()
	_load_adjacencies()
	_load_sea_zones()
	_load_nations()


func _load_image() -> void:
	var path := MAP_DIR + "provinces.png"
	if ResourceLoader.exists(path):
		provinces_image = (load(path) as Texture2D).get_image()
	else:
		provinces_image = Image.load_from_file(ProjectSettings.globalize_path(path))
	provinces_image.convert(Image.FORMAT_RGB8)
	map_size = provinces_image.get_size()


func _load_provinces() -> void:
	for row in read_table(MAP_DIR + "provinces.tsv"):
		var id := int(row.id)
		var rgb := _pack_rgb(int(row.r), int(row.g), int(row.b))
		var p := {
			"id": id,
			"name": row.name,
			"owner": row.owner,  # initial owner from the map file; GameState holds the live one
			"area": int(row.area),
			"center": Vector2(int(row.cx), int(row.cy)),
			"coastal": false,
		}
		while provinces.size() <= id:
			provinces.append({})
		provinces[id] = p
		_id_by_rgb[rgb] = id


## Provinces that touch the sea (see tools/build_coastal.py).
func _load_coastal() -> void:
	for row in read_table(MAP_DIR + "coastal.tsv"):
		provinces[int(row.id)].coastal = true


func _load_adjacencies() -> void:
	for row in read_table(MAP_DIR + "adjacencies.tsv"):
		var a := int(row.id_a)
		var b := int(row.id_b)
		_link(a, b)
		if row.kind != "land":
			sea_links[Vector2i(mini(a, b), maxi(a, b))] = row.kind


func _load_sea_zones() -> void:
	var path := MAP_DIR + "sea_zones.png"
	if ResourceLoader.exists(path):
		sea_zones_image = (load(path) as Texture2D).get_image()
	else:
		sea_zones_image = Image.load_from_file(ProjectSettings.globalize_path(path))
	sea_zones_image.convert(Image.FORMAT_RGB8)
	for row in read_table(MAP_DIR + "sea_zones.tsv"):
		var id := int(row.id)
		while sea_zones.size() <= id:
			sea_zones.append({})
		sea_zones[id] = {
			"id": id,
			"name": row.name,
			"seed": Vector2(int(row.x), int(row.y)),
			"center": Vector2(int(row.cx), int(row.cy)),
			"area": int(row.area),
		}
		sea_adjacency[id] = PackedInt32Array()
	for row in read_table(MAP_DIR + "sea_adjacency.tsv"):
		for pair in [[int(row.id_a), int(row.id_b)], [int(row.id_b), int(row.id_a)]]:
			var list: PackedInt32Array = sea_adjacency[pair[0]]
			list.append(pair[1])
			sea_adjacency[pair[0]] = list
	for row in read_table(MAP_DIR + "ports.tsv"):
		var pid := int(row.id)
		port_zones[pid] = {"zone": int(row.zone), "zone2": int(row.zone2)}
		for z in [int(row.zone), int(row.zone2)]:
			if z > 0:
				var list: PackedInt32Array = _ports_of_zone.get(z, PackedInt32Array())
				list.append(pid)
				_ports_of_zone[z] = list


## Sea zone id at a pixel of the bitmap: 0 on land and on water that belongs to no zone.
func sea_zone_at_pixel(px: Vector2i) -> int:
	if px.x < 0 or px.y < 0 or px.x >= map_size.x or px.y >= map_size.y or province_at_pixel(px) != SEA:
		return 0
	return sea_zones_image.get_pixel(clampi(px.x / ZONE_SCALE, 0, sea_zones_image.get_width() - 1),
			clampi(px.y / ZONE_SCALE, 0, sea_zones_image.get_height() - 1)).r8


## Province ids that open on a sea zone.
func ports_in_zone(zone: int) -> PackedInt32Array:
	return _ports_of_zone.get(zone, PackedInt32Array())


## Zones a coastal province opens on (empty if it has no port).
func zones_of_port(province: int) -> Array[int]:
	var out: Array[int] = []
	var e: Dictionary = port_zones.get(province, {})
	for key in ["zone", "zone2"]:
		if e.get(key, 0) > 0:
			out.append(e[key])
	return out


func _load_nations() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(NATIONS_PATH))
	assert(parsed is Dictionary, "nations.json is invalid")
	for tag in parsed:
		nations[tag] = {"name": parsed[tag].name, "color": Color(parsed[tag].color)}


func _link(a: int, b: int) -> void:
	for pair in [[a, b], [b, a]]:
		var list: PackedInt32Array = adjacency.get(pair[0], PackedInt32Array())
		if not list.has(pair[1]):
			list.append(pair[1])
		adjacency[pair[0]] = list


## Province id at a pixel of the bitmap (SEA, BACKGROUND, or an id >= 1).
func province_at_pixel(px: Vector2i) -> int:
	if px.x < 0 or px.y < 0 or px.x >= map_size.x or px.y >= map_size.y:
		return SEA
	var c := provinces_image.get_pixelv(px)
	var rgb := _pack_rgb(c.r8, c.g8, c.b8)
	if rgb == 0:
		return SEA
	return _id_by_rgb.get(rgb, BACKGROUND)


func get_province(id: int) -> Dictionary:
	return provinces[id] if id > 0 and id < provinces.size() else {}


func _pack_rgb(r: int, g: int, b: int) -> int:
	return r | (g << 8) | (b << 16)


## Reads a tab-separated file with a header row into an array of dictionaries.
func read_table(path: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var f := FileAccess.open(path, FileAccess.READ)
	assert(f != null, "Cannot open %s" % path)
	var header := f.get_line().split("\t")
	while not f.eof_reached():
		var line := f.get_line()
		if line.is_empty():
			continue
		var cols := line.split("\t")
		var row := {}
		for i in header.size():
			row[header[i]] = cols[i] if i < cols.size() else ""
		rows.append(row)
	return rows

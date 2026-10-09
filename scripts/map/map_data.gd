extends Node
## Loads the province bitmap and its tables (see tools/build_map.py).
## Province ids start at 1; 0 means sea and -1 means non-playable background land.

const MAP_DIR := "res://data/map/"
const NATIONS_PATH := "res://data/nations.json"
const SEA := 0
const BACKGROUND := -1
## Ground area of one bitmap pixel (see tools/build_map.py).
const KM2_PER_PX := 0.48
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

var _id_by_rgb: Dictionary = {}


func _init() -> void:
	_load_image()
	_load_provinces()
	_load_coastal()
	_load_adjacencies()
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

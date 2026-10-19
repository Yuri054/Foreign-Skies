class_name SetProductionLine
extends Command
## Opens, changes or closes an equipment production line. line_id 0 opens a new line of
## `category` with `factories` factories; an existing line is given the factories (0 closes it) and
## the category (changing it starts the line's efficiency over). Takes the nation off automatic
## production. A line cannot hold more factories than the nation has free.

var tag: String
var line_id: int
var category: String
var factories: int
## Why it was refused, for the interface.
var reason := ""


func _init(p_tag := "", p_line := 0, p_category := "", p_factories := 0) -> void:
	tag = p_tag
	line_id = p_line
	category = p_category
	factories = p_factories


func execute(gs: Node) -> bool:
	reason = ""
	var n: Nation = gs.nations.get(tag)
	if n == null or factories < 0:
		reason = "Invalid order."
		return false
	if not Military.cfg.equipment.categories.has(category):
		reason = "Unknown equipment."
		return false
	if n.lines_auto:
		n.lines_auto = false
	if line_id == 0:
		if factories < 1:
			reason = "A line needs a factory."
			return false
		if Production.free_factories(n) < factories:
			reason = "Not enough free factories."
			return false
		Production.new_line(n, category, factories)
		return true
	for i in n.production_lines.size():
		var line: Dictionary = n.production_lines[i]
		if line.id != line_id:
			continue
		if factories - line.factories > Production.free_factories(n):
			reason = "Not enough free factories."
			return false
		if factories == 0:
			n.production_lines.remove_at(i)
			return true
		if category != line.category:
			line.days = Production.retained_days(line)
			line.category = category
		line.factories = factories
		return true
	reason = "No such line."
	return false


func to_dict() -> Dictionary:
	return {"type": "SetProductionLine", "tag": tag, "line": line_id, "category": category, "factories": factories}

class_name SetEconomyPolicy
extends Command
## Sets one of a nation's economic policies: "tax_rate" or "mobilization".

var tag: String
var policy: String
var value: float


func _init(p_tag := "", p_policy := "", p_value := 0.0) -> void:
	tag = p_tag
	policy = p_policy
	value = p_value


func execute(gs: Node) -> bool:
	var n: Nation = gs.nations.get(tag)
	if n == null:
		return false
	match policy:
		"tax_rate":
			n.tax_rate = clampf(value, Economy.cfg.min_tax_rate, Economy.cfg.max_tax_rate)
		"mobilization":
			n.mobilization = clampf(value, 0.0, 1.0)
		_:
			return false
	return true


func to_dict() -> Dictionary:
	return {"type": "SetEconomyPolicy", "tag": tag, "policy": policy, "value": value}

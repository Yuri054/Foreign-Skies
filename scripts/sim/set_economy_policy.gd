class_name SetEconomyPolicy
extends Command
## Sets one of a nation's economic policies: "tax_rate", "mobilization", "army_funding" or
## "navy_funding". Mobilization and funding stop at the most the economy law allows (see
## Economy.mobilization_cap and Economy.funding_cap).

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
			n.mobilization = clampf(value, 0.0, Economy.mobilization_cap(gs, n))
		"army_funding":
			n.army_funding = clampf(value, Economy.cfg.funding_min, Economy.funding_cap(n))
		"navy_funding":
			n.navy_funding = clampf(value, Economy.cfg.funding_min, Economy.funding_cap(n))
		_:
			return false
	return true


func to_dict() -> Dictionary:
	return {"type": "SetEconomyPolicy", "tag": tag, "policy": policy, "value": value}

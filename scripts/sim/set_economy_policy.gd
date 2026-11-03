class_name SetEconomyPolicy
extends Command
## Sets one of a nation's policies: "mobilization" or "standing_army" (men kept under arms in peace, Nation.peacetime_army,
## at most Economy.standing_cap: the reserve fills toward it and units can be raised from it). Mobilization stops at
## the most the nation may have now (see Economy.mobilization_range).

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
		"mobilization":
			n.mobilization = clampf(value, 0.0, Economy.mobilization_cap(gs, n))
		"standing_army":
			n.peacetime_army = clampi(int(value), 0, maxi(Economy.standing_cap(gs, n), 0))
			# The reserve follows at once: a smaller army asks no more recruits; a larger one fills over the months.
			Economy.request(gs)
		_:
			return false
	return true


func to_dict() -> Dictionary:
	return {"type": "SetEconomyPolicy", "tag": tag, "policy": policy, "value": value}

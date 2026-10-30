class_name Nation
extends RefCounted
## Runtime state of one nation. Static display data (name, color) lives in MapData.nations.

var tag: String
var display_name: String
var color: Color
var government := ""
var treasury := 0.0          # gold
## Standing among the powers; diplomacy spends and earns it (war support arrives in step 6).
var prestige := 0.0
## Province id of the capital; losing it to an enemy weighs on peace talks (see Capitulation).
var capital := 0
## The capital the nation had before a war moved it (0: the capital has not moved); see Capitulation.
var home_capital := 0
## Has laid down its arms in its present wars (Capitulation); cleared at peace.
var capitulated := false
## Diplomacy points: a stock of diplomatic effort. Only the number exists so far; nothing
## earns or spends it yet.
var diplomacy_points := 0.0
## What a batch of bought diplomacy points costs, as a multiple of the base price: it rises with
## each purchase and eases back each month.
var points_price := 1.0
## How far the people stand behind the war, 0..100 (see WarSupport), and the level it returns
## to in peace. men_lost_month is this month's casualties, counted for WarSupport.
var war_support := 55.0
var war_support_base := 55.0
var men_lost_month := 0.0
## Province ids this nation owns; maintained by GameState.
var provinces: PackedInt32Array = []
var population := 0
## Soldiers killed this month and in all (see Population).
var deaths_month := 0.0
var war_dead := 0.0

# Economy (rules in Economy; constants in data/economy.json).
## Construction points in hand: construction sectors add to them every day, starting a building spends them.
var cp := 0.0
## 0 = peacetime army only, 1 = the whole manpower pool is called up.
var mobilization := 0.0
## The construction queue, in order: {province, type, started, days_total, days_left} (see Economy.new_job). A project
## waits until its province is free and its gold and CP are there; then it is paid for and counts down its days.
var construction: Array[Dictionary] = []
## 0..1 share of port and factory income cut off by enemy naval control (see Blockade).
var blockade := 0.0
## What the enemy's grip on the sea would cut off (0..1), the nations whose ships hold it, and
## the value of `blockade` when the economy was last recomputed (see Blockade).
var blockade_target := 0.0
var blockade_by: Array = []
var blockade_applied := 0.0
## A level (0..1) that overrides the navy, for tests and scenarios that must not depend on the
## fleets; negative means the navy decides.
var blockade_pinned := -1.0
## Soldiers in service at mobilization 0.
var peacetime_army := 0
## Yearly naval cost, gold (a twelfth of it a month): the shore establishment plus the upkeep of the ships (set
## by Navy.refresh_upkeep; the scenario gives the historical figure at the start).
var naval_budget := 0.0
## The part of naval_budget that is not ships: dockyards, bases, sailors ashore.
var naval_overhead := 0.0
## Squadrons lost at sea in all.
var ships_lost := 0
## Squadrons being built, paid for when begun: {type, province, days_left, days_total}.
var shipbuilding: Array[Dictionary] = []
## Reserve recruits not yet in a unit; refilled monthly up to what budget.manpower_max
## allows after the men under arms.
var manpower := 0
## Men in armies and in training; kept up to date by Military.refresh_men.
var men_in_units := 0
## Men in armies on exercise, who cost more upkeep (military.json training cost_share).
var men_exercising := 0
## Units in training: {type, province, days_left}.
var recruiting: Array[Dictionary] = []
## National focus (see Focus): the one being worked on, {id, days_left, days_total} or {}; the
## ones finished; and the summed lasting effects of those (income, cp, diplomacy, army_size).
var focus: Dictionary = {}
var focus_done: Array[String] = []
var focus_fx: Dictionary = {}
## Times each repeatable focus has been finished: focus id -> count.
var focus_count: Dictionary = {}
## Latest figures from Economy.recompute: the month's budget in gold (see Economy.nation_budget).
var budget: Dictionary = {}


func _init(p_tag: String, static_data: Dictionary, scenario_data: Dictionary) -> void:
	tag = p_tag
	display_name = static_data.name
	color = static_data.color
	government = scenario_data.get("government", "")
	treasury = scenario_data.get("treasury", 0.0)
	prestige = scenario_data.get("prestige", 0.0)
	capital = int(scenario_data.get("capital", 0))
	diplomacy_points = scenario_data.get("diplomacy_points", Diplomacy.cfg.points.start)
	war_support = scenario_data.get("war_support", WarSupport.start_value(government))
	war_support_base = war_support
	mobilization = scenario_data.get("mobilization", 0.0)
	peacetime_army = int(scenario_data.get("peacetime_army", 0))
	naval_budget = scenario_data.get("naval_budget", 0.0)
	manpower = peacetime_army


## Everyone in service: the reserve plus the men in armies and training.
func total_men() -> int:
	return manpower + men_in_units


## Takes recruits out of the pool. Returns false (and takes nothing) if there are too few.
func spend_manpower(amount: int) -> bool:
	if amount > manpower:
		return false
	manpower -= amount
	return true

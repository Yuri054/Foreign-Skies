class_name Nation
extends RefCounted
## Runtime state of one nation. Static display data (name, color) lives in MapData.nations.

var tag: String
var display_name: String
var color: Color
var government := ""
var treasury := 0.0          # GBP millions
## Standing among the powers; diplomacy spends and earns it (war support arrives in step 6).
var prestige := 0.0
## Province id of the capital; losing it to an enemy weighs on peace talks.
var capital := 0
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
## Yearly natural increase of the people (see Population), soldiers killed this month and in
## all.
var pop_growth := 0.01
var deaths_month := 0.0
var war_dead := 0.0
## Share of the civilian factories the people's goods take because of the war (see Economy.step_day).
var weariness := 0.0
## True while blockaded imports are too few to feed the nation (see Economy.step_day).
var starving := false

# Economy (rules in Economy; constants in data/economy.json).
## Output multiplier: how productive this nation's economy is relative to the baseline.
var development := 1.0
## Food yield multiplier (farmland quality, techniques).
var agri_yield := 1.0
## Share of GDP taken as tax.
var tax_rate := 0.10
## 0 = peacetime army only, 1 = the whole manpower pool is called up.
var mobilization := 0.0
## Enabled national programs: program id -> true.
var programs: Dictionary = {}
## Buildings under construction, in the order they are served: {province, type, points_total,
## points_left, rate, given, days_total, days_left} (see Economy.new_job). construction_used is
## how many of the day's construction points they took.
var construction: Array[Dictionary] = []
var construction_used := 0.0
## 0..1 share of trade and food imports cut off by enemy naval control (see Blockade).
var blockade := 0.0
## What the enemy's grip on the sea would cut off (0..1), the nations whose ships hold it, and
## the value of `blockade` when the economy was last recomputed (see Blockade).
var blockade_target := 0.0
var blockade_by: Array = []
var blockade_applied := 0.0
## A level (0..1) that overrides the navy, for tests and scenarios that must not depend on the
## fleets; negative means the navy decides.
var blockade_pinned := -1.0
## The economy law in force (see Economy.law_of) and the day it last changed.
var economy_law := "civilian"
var law_changed_day := -1000
## How well the army and the navy are funded (1 = the usual upkeep; the economy law sets the
## most, Economy.funding_cap) and how ready they are: readiness drifts toward the funding a
## little each day (Military.step_readiness) and is what the forces fight with.
var army_funding := 1.0
var navy_funding := 1.0
var army_ready := 1.0
var navy_ready := 1.0
## Soldiers in service at mobilization 0.
var peacetime_army := 0
## Yearly naval cost, GBP millions: the shore establishment plus the upkeep of the ships (set
## by Navy.refresh_upkeep; the scenario gives the historical figure at the start).
var naval_budget := 0.0
## The part of naval_budget that is not ships: dockyards, bases, sailors ashore.
var naval_overhead := 0.0
## Squadrons lost at sea in all.
var ships_lost := 0
## Squadrons being built: {type, province, days_left, days_total}.
var shipbuilding: Array[Dictionary] = []
## Reserve recruits not yet in a unit; refilled monthly up to what budget.manpower_max
## allows after the men under arms.
var manpower := 0
## Men in armies and in training; kept up to date by Military.refresh_men.
var men_in_units := 0
## Units in training: {type, province, days_left}.
var recruiting: Array[Dictionary] = []
## Resource id -> multiplier on this nation's industrial and household demand for it
## (calibrated so the 1913 trade pattern is about right).
var intensity: Dictionary = {}
## Equipment in store, not yet issued to a unit: category id -> amount (see "equipment" in
## data/military.json).
var equipment: Dictionary = {}
## Equipment production lines (see Production): {id, category, factories, days, made, limit}.
## While lines_auto is set the factories are shared out by the rules in Production.
var production_lines: Array[Dictionary] = []
var lines_auto := true
## GBP millions spent on equipment in all (the lines pay out of the treasury each day).
var equipment_spent := 0.0
var next_line_id := 1
## Stockpile of each resource that keeps one (coal and chemicals), in thousand tonnes: resource id
## -> amount. The others are flows (see Flows).
var stock: Dictionary = {}
## How much of its chemicals industry the nation has (a multiplier on what its industry makes).
var chem := 0.5
## Draft animals the army needs, kt a year (kept up to date by Military.refresh_men).
var animal_need := 0.0
## National focus (see Focus): the one being worked on, {id, days_left, days_total} or {}; the
## ones finished; and the summed lasting effects of those (gdp, industry, food, trade, growth,
## diplomacy, construction).
var focus: Dictionary = {}
var focus_done: Array[String] = []
var focus_fx: Dictionary = {}
## Times each repeatable focus has been finished: focus id -> count.
var focus_count: Dictionary = {}
## Latest figures from Economy.recompute (annual GBP millions unless stated).
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
	development = scenario_data.get("development", 1.0)
	agri_yield = scenario_data.get("agri_yield", 1.0)
	tax_rate = scenario_data.get("tax_rate", Economy.cfg.default_tax_rate)
	mobilization = scenario_data.get("mobilization", 0.0)
	economy_law = scenario_data.get("economy_law", "civilian")
	pop_growth = float(scenario_data.get("pop_growth", 0.01))
	peacetime_army = int(scenario_data.get("peacetime_army", 0))
	naval_budget = scenario_data.get("naval_budget", 0.0)
	manpower = peacetime_army
	intensity = scenario_data.get("intensity", {})
	chem = float(scenario_data.get("chemicals", 0.5))
	for r in Economy.resource_ids():
		stock[r] = 0.0
	for cat in Military.equipment_ids():
		equipment[cat] = 0.0


## Everyone in service: the reserve plus the men in armies and training.
func total_men() -> int:
	return manpower + men_in_units


## Takes recruits out of the pool. Returns false (and takes nothing) if there are too few.
func spend_manpower(amount: int) -> bool:
	if amount > manpower:
		return false
	manpower -= amount
	return true

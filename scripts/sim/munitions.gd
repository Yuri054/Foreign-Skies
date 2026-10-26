class_name Munitions
extends RefCounted
## Munitions: what industry makes for the guns, what the guns burn, and what a nation buys abroad (data/economy.json,
## "munitions"). A nation puts `arms_share` of each day's IC into its stockpile before the hulls and buildings are
## served (Economy.step_day); the share also takes that much of the factories from the people's goods, so output falls
## a little (Economy.nation_budget). The stockpile ages and costs money to keep. In battle each army's guns burn
## munitions every day, and an army dug in on a front facing an enemy burns a share of that; a nation that cannot meet
## the day's need fights with its guns weakened by `combat.shell_penalty` times the share missing (Military._fight).
## Static, like Economy; the stock is Nation.munitions, measured in IC (a day's work of one IC makes one unit).


static func cfg() -> Dictionary:
	return Economy.cfg.munitions


## A scenario's start: each nation's arms share and a stockpile of `days` of the general war the scenario sets
## (scenario "munitions": {share, days}).
static func load_scenario(gs: Node) -> void:
	var s: Dictionary = gs.scenario.get("munitions", {})
	for tag: String in gs.nations:
		var n: Nation = gs.nations[tag]
		n.arms_share = clampf(float(s.get("share", cfg().default_share)), 0.0, 1.0)
		n.munitions_used_last = 0.0
		n.munitions_used_month = 0.0
		n.munitions = float(s.get("days", 0.0)) * expected_daily(gs, tag)
		n.shell_ratio = 1.0


## The power of an army's guns (artillery and anything else that burns shells).
static func gun_power(a: Army) -> float:
	return a.power() * a.shelling_share()


## What a nation's armies would burn in a day if every one of them were fighting: the measure of "days of war" a
## stockpile lasts.
static func war_need(gs: Node, tag: String) -> float:
	var guns := 0.0
	for a: Army in Military.armies_of(gs, tag):
		guns += gun_power(a)
	return guns * float(cfg().per_gun_power)


## What a nation can expect to burn a day in a war: what it burnt last month, or (with no war behind it) the share of
## its armies' full need that a war usually keeps in contact (engaged_share).
static func expected_daily(gs: Node, tag: String) -> float:
	var n: Nation = gs.nations[tag]
	return maxf(n.munitions_used_last / 30.0, war_need(gs, tag) * float(cfg().engaged_share))


## How many days of war the stockpile would last at the expected rate (INF with no guns).
static func days_left(gs: Node, tag: String) -> float:
	var need := expected_daily(gs, tag)
	return INF if need <= 0.0 else gs.nations[tag].munitions / need


## The day's making: `arms_share` of the IC goes to the stockpile. Returns the IC it took.
static func produce(n: Nation, pool: float) -> float:
	var made := pool * clampf(n.arms_share, 0.0, 1.0)
	n.munitions += made
	return made


## Monthly: the stockpile ages, and this month's use starts again.
static func step_month(gs: Node) -> void:
	var decay := float(cfg().decay_per_year) / 12.0
	for tag: String in gs.nations:
		var n: Nation = gs.nations[tag]
		n.munitions *= 1.0 - decay
		n.munitions_used_last = n.munitions_used_month
		n.munitions_used_month = 0.0


## What keeping a stockpile costs a year, GBP millions.
static func storage_cost(n: Nation) -> float:
	return n.munitions * float(cfg().storage_cost)


## The day's burning, before the fighting (Military._fight): every army in battle (in `fighting`) burns its guns' need,
## and every army of a nation at war that stands next to an enemy army (a line facing another) burns idle_share of it.
## `at` is province -> the armies there. Each nation draws what it
## can from its stockpile; returns tag -> the share of the day's need it met (1 where it needed nothing), which is also
## kept in Nation.shell_ratio for the screens and the forecasts.
static func burn(gs: Node, fighting: Dictionary, at: Dictionary) -> Dictionary:
	var c := cfg()
	var need := {}
	for a: Army in fighting:
		need[a.tag] = float(need.get(a.tag, 0.0)) + gun_power(a) * float(c.per_gun_power)
	for a: Army in gs.armies.values():
		if fighting.has(a) or a.embarked() or gs.wars_of(a.tag).is_empty() or not _facing(gs, a, at):
			continue
		need[a.tag] = float(need.get(a.tag, 0.0)) + gun_power(a) * float(c.per_gun_power) * float(c.idle_share)
	var ratios := {}
	for tag: String in gs.nations:
		var n: Nation = gs.nations[tag]
		var want: float = need.get(tag, 0.0)
		if want <= 0.0:
			# Guns that are not firing are not short.
			ratios[tag] = 1.0
			n.shell_ratio = 1.0
			continue
		var used := minf(want, n.munitions)
		n.munitions -= used
		n.munitions_used_month += used
		ratios[tag] = used / want
		n.shell_ratio = ratios[tag]
	return ratios


## Whether an enemy army stands in a province next to `a`.
static func _facing(gs: Node, a: Army, at: Dictionary) -> bool:
	for p: int in Military.neighbors(a.province):
		for b: Army in at.get(p, []):
			if gs.at_war(a.tag, b.tag):
				return true
	return false


## The fighting power of an army whose nation met `ratio` of the day's need: its guns lose shell_penalty of their
## power for the share missing.
static func power_factor(a: Army, ratio: float) -> float:
	var missing := clampf(1.0 - ratio, 0.0, 1.0)
	return 1.0 - a.shelling_share() * float(Military.cfg.combat.shell_penalty) * missing


## What `amount` GBP millions buy abroad, after the blockade's cut.
static func bought_for(n: Nation, amount: float) -> float:
	return amount / float(cfg().import_price) * (1.0 - n.blockade)


## In words, for the screens: the stockpile and how long it lasts.
static func line(gs: Node, tag: String) -> String:
	var n: Nation = gs.nations[tag]
	var days := days_left(gs, tag)
	var span := "no guns to feed" if days == INF else ("%d days of war" % roundi(days) if days < 3650 else "years of war")
	return "Munitions: %s IC in store, %s." % [Fmt.thousands(roundi(n.munitions)), span]

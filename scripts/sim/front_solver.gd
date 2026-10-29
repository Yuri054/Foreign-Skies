class_name FrontSolver
extends RefCounted
## Spreads the divisions of the armies on a front along its line (docs/FRONTLINES.md). For a front with `spread` on,
## each army deploys as detachments: stacks of its own divisions, one to a province of the line, that keep its general,
## group and symbol (Army.parent_id). Each day, for each army on the front:
##   1. the line is put in order along its length (order_line) and each province weighed by the threat to it (weights);
##   2. the army's divisions are dealt to the provinces of the line in proportion to the weights (deal);
##   3. where a province has more than its share, the surplus goes to the nearest province short of it, no farther along
##      the line than the front's cohesion allows, splitting off a detachment for it (redeploy).
## Detachments whose army has left the front march back to it and merge (regroup). A stack sent somewhere by hand is
## pinned (Army.pin): it is left alone until it gets there. Constants are in data/military.json "fronts".


static func cfg() -> Dictionary:
	return Military.cfg.get("fronts", {})


# ------------------------------------------------------------------ the line

## The provinces of a line in order along it: from the end that has the fewest neighbours on the line (westmost on a
## tie), always on to the nearest unvisited neighbour on the line, and across a gap to the nearest unvisited province
## when a piece ends.
static func order_line(provinces: Array[int]) -> Array[int]:
	var left := {}
	for p in provinces:
		left[p] = true
	var out: Array[int] = []
	if provinces.is_empty():
		return out
	var start := provinces[0]
	var start_key := Vector2(INF, INF)
	for p in provinces:
		var on_line := 0
		for n: int in Military.neighbors(p):
			if left.has(n):
				on_line += 1
		var key := Vector2(on_line, _centre(p).x)
		if key.x < start_key.x or (key.x == start_key.x and key.y < start_key.y):
			start_key = key
			start = p
	var here := start
	while true:
		out.append(here)
		left.erase(here)
		if left.is_empty():
			break
		var next := 0
		var best := INF
		for n: int in Military.neighbors(here):
			if left.has(n) and _centre(here).distance_to(_centre(n)) < best:
				best = _centre(here).distance_to(_centre(n))
				next = n
		if next == 0:
			for p: int in left:
				if _centre(here).distance_to(_centre(p)) < best:
					best = _centre(here).distance_to(_centre(p))
					next = p
		here = next
	return out


## How much each province of an ordered line should draw, in its order: 1, plus enemy divisions next to it (the threat,
## by `enemy_weight` a division, rounded so that small changes do not shuffle the front), plus a little for forts.
static func weights(gs: Node, tag: String, line: Array[int]) -> Array[float]:
	var c := cfg()
	var out: Array[float] = []
	for p in line:
		var enemy := 0
		for n: int in Military.neighbors(p):
			for b: Army in Military.armies_at(gs, n):
				if gs.at_war(tag, b.tag):
					enemy += b.units.size()
		var w := 1.0 + roundf(float(enemy) * float(c.get("enemy_weight", 0.25)))
		w += float(c.get("fort_weight", 0.15)) * float(gs.province_buildings[p].get("fortification", 0))
		out.append(w)
	return out


## Deals `count` divisions over provinces by weight, largest remainder first: whole numbers that add up to `count`.
static func deal(count: int, w: Array[float]) -> Array[int]:
	var out: Array[int] = []
	out.resize(w.size())
	out.fill(0)
	var total := 0.0
	for x in w:
		total += x
	if total <= 0.0 or count <= 0:
		return out
	var rests: Array = []
	var given := 0
	for i in w.size():
		var share := float(count) * w[i] / total
		out[i] = int(floor(share))
		given += out[i]
		rests.append([share - floor(share), -i])
	rests.sort()
	rests.reverse()
	for k in count - given:
		out[-int(rests[k][1])] += 1
	return out


# ------------------------------------------------------------------ armies and their detachments

## The army a stack belongs to: itself, or the army it was detached from.
static func root_of(gs: Node, a: Army) -> Army:
	if a.parent_id == 0:
		return a
	return gs.armies.get(a.parent_id)


## Every stack of an army: the army itself and its detachments.
static func stacks_of(gs: Node, root: Army) -> Array[Army]:
	var out: Array[Army] = [root]
	for b: Army in gs.armies.values():
		if b.parent_id == root.id:
			out.append(b)
	return out


## Splits `count` divisions off a stack into a new detachment of its army, in the same province. The divisions taken
## are the last of the stack's list, so its first (and its flag) stay.
static func detach(gs: Node, from: Army, count: int) -> Army:
	var root := root_of(gs, from)
	var d := Military.new_army(gs, from.tag, from.display_name if from.parent_id != 0 else "%s, detachment" % from.display_name, from.province)
	d.parent_id = root.id
	_follow(d, root)
	for i in count:
		d.units.push_front(from.units.pop_back())
	d.still_days = from.still_days
	return d


## A detachment takes its army's general (his skill and name, not the man), symbol and group.
static func _follow(d: Army, root: Army) -> void:
	d.general_name = root.general_name
	d.general_skill = root.general_skill
	d.icon = root.icon
	d.group_id = root.group_id


# ------------------------------------------------------------------ the daily step

## Deals and moves the divisions of every army on a spreading front (Military.step_fronts calls it for such fronts).
## `routes_left` is the day's budget of route searches, shared with the other fronts; returns what is left of it.
static func step(gs: Node, f: Front, routes_left: int) -> int:
	if f.dirty or f.order.is_empty() or f.order.size() != f.provinces.size():
		f.order = order_line(f.provinces)
		f.dirty = false
		f.weights_day = -1
	if f.weights_day < 0 or Clock.days_elapsed - f.weights_day >= int(cfg().get("reweigh_days", 7)):
		f.weights = weights(gs, f.tag, f.order)
		f.weights_day = Clock.days_elapsed
	var roots: Array[Army] = []
	for id in f.army_ids:
		var root: Army = gs.armies.get(id)
		if root != null:
			roots.append(root)
	var sectors := sectors_of(gs, f.order, f.weights, roots)
	f.sectors = {}
	var fallback := f.is_fallback(gs)
	for root in roots:
		var span: Vector2i = sectors[root.id]
		f.sectors[root.id] = span
		var line: Array[int] = f.order.slice(span.x, span.y)
		var w: Array[float] = f.weights.slice(span.x, span.y)
		# A launched spearhead has the army's stacks in hand; the sector waits for them.
		if not Offensives.controls(gs, root):
			routes_left = _redeploy(gs, f, root, line, w, routes_left)
		if fallback:
			for s in stacks_of(gs, root):
				s.prepared = s.path.is_empty() and line.has(s.province)
	return routes_left


## Cuts an ordered line into one contiguous sector per army (a broad front): each army's share of the line's weight is
## its share of the divisions, and the armies take sectors in the order they stand along the line (the mean place of
## their stacks), so sectors never cross and the divisions of two armies never mix. Returns army id -> Vector2i(first
## index, one past the last) into the line. With more armies than provinces, armies share the province their share
## falls in.
static func sectors_of(gs: Node, line: Array[int], w: Array[float], roots: Array[Army]) -> Dictionary:
	var out := {}
	if roots.is_empty() or line.is_empty():
		return out
	var index := {}
	for i in line.size():
		index[line[i]] = i
	var placed: Array = []
	var total_units := 0
	for root in roots:
		var sum := 0.0
		var n := 0
		var units := 0
		for s in stacks_of(gs, root):
			units += s.units.size()
			var at: int = s.path.back() if not s.path.is_empty() else s.province
			sum += float(index[at]) if index.has(at) else float(_nearest_index(line, at))
			n += 1
		placed.append([sum / maxf(n, 1.0), root.id, root, maxi(units, 1)])
		total_units += maxi(units, 1)
	placed.sort()
	var total_w := 0.0
	for x in w:
		total_w += x
	var start := 0
	var done_units := 0
	var cumulative := 0.0
	var i := 0
	for k in placed.size():
		var root: Army = placed[k][2]
		done_units += int(placed[k][3])
		var boundary := total_w * float(done_units) / float(total_units)
		var end := start
		while end < line.size() and (cumulative + w[end] * 0.5 <= boundary or end == start):
			cumulative += w[end]
			end += 1
		# Leave at least one province for each army still to come, while there are enough.
		end = mini(end, maxi(start + 1, line.size() - (placed.size() - k - 1)))
		if k == placed.size() - 1:
			end = line.size()
		if start >= line.size():
			# More armies than provinces: share the last one.
			out[root.id] = Vector2i(line.size() - 1, line.size())
			continue
		out[root.id] = Vector2i(start, maxi(end, start + 1))
		start = maxi(end, start + 1)
		i += 1
	return out


## The index of the province of the line nearest to a province off it.
static func _nearest_index(line: Array[int], p: int) -> int:
	var best := 0
	var best_d := INF
	for i in line.size():
		var d := _centre(p).distance_to(_centre(line[i]))
		if d < best_d:
			best_d = d
			best = i
	return best


## Moves an army's surplus divisions to the provinces of its stretch of line that are short of them.
static func _redeploy(gs: Node, f: Front, root: Army, line: Array[int], w: Array[float], routes_left: int) -> int:
	var stacks := stacks_of(gs, root)
	var total := 0
	for s in stacks:
		total += s.units.size()
	var want := deal(total, w)
	var index := {}
	for i in line.size():
		index[line[i]] = i
	# What each province of the line has, counting stacks on their way there; and the stacks that may give.
	var have: Array[int] = []
	have.resize(line.size())
	have.fill(0)
	var idle := {}
	for s in stacks:
		if s.embarked():
			continue
		var at: int = s.path.back() if not s.path.is_empty() else s.province
		if s.pin != 0:
			at = s.pin
		if index.has(at):
			have[index[at]] += s.units.size()
		if s.path.is_empty() and s.pin == 0 and not s.fighting:
			if not idle.has(s.province):
				idle[s.province] = []
			idle[s.province].append(s)
	# Every province has its share (counting those on their way): the army is in place, and from now on the cohesion
	# limit holds. Until then it deploys along the whole line.
	var placed := true
	for i in line.size():
		placed = placed and have[i] >= want[i]
	if placed:
		f.deploying.erase(root.id)
	# Stacks off the line give all they have.
	var reach := -1 if f.deploying.has(root.id) else _reach(f)
	for p: int in idle:
		var surplus: int = 0
		if index.has(p):
			surplus = have[index[p]] - want[index[p]]
		else:
			for s: Army in idle[p]:
				surplus += s.units.size()
		while surplus > 0 and routes_left > 0:
			# A garrison's provinces are not a line: what is short is found by distance, anywhere.
			var to := _nearest_short(line, want, have, -1 if f.kind == "garrison" else index.get(p, -1), p, -1 if f.kind == "garrison" else reach)
			if to < 0:
				break
			var stack := _giver(idle[p], surplus)
			if stack == null:
				break
			var count := mini(mini(surplus, want[to] - have[to]), stack.units.size())
			if Clock.days_elapsed < f.retry.get(stack.id, -1):
				break
			routes_left -= 1
			var route := Military.find_path(gs, stack.tag, stack.speed(), stack.province, line[to])
			if route.is_empty() or Military._route_blocked(gs, stack, route):
				f.retry[stack.id] = Clock.days_elapsed + 10
				break
			var mover := stack
			if count < stack.units.size():
				mover = detach(gs, stack, count)
			else:
				idle[p].erase(stack)
			mover.path = route
			mover.move_days_left = Military.move_days(gs, mover.tag, mover.speed(), mover.province, route[0])
			mover.still_days = 0
			have[to] += count
			surplus -= count
			if index.has(p):
				have[index[p]] -= count
	return routes_left


## How far along the line (in provinces) a division may be sent, by the front's cohesion; -1 for anywhere.
static func _reach(f: Front) -> int:
	match f.cohesion:
		"rigid":
			return int(cfg().get("rigid_hops", 2))
		"flexible":
			return -1
	return int(cfg().get("balanced_hops", 6))


## The province of the line (its index) nearest to `from_index` that has fewer divisions than its share, within
## `reach` provinces along the line; -1 if none. A stack off the line (`from_index` -1) looks by distance and may go
## anywhere.
static func _nearest_short(line: Array[int], want: Array[int], have: Array[int], from_index: int, from: int, reach: int) -> int:
	var best := -1
	var best_d := INF
	for i in line.size():
		if have[i] >= want[i]:
			continue
		var d: float
		if from_index >= 0:
			d = absf(i - from_index)
			if reach >= 0 and d > reach:
				continue
			# A shortfall of one is not worth a march when the giver has only one to spare; nearer first.
		else:
			d = _centre(from).distance_to(_centre(line[i]))
		if d < best_d:
			best_d = d
			best = i
	return best


## The stack in a province that should give `surplus` divisions: the one whose size is nearest to it (a whole
## detachment that can go as it is, before splitting the army's own stack).
static func _giver(stacks: Array, surplus: int) -> Army:
	var best: Army = null
	for s: Army in stacks:
		if s.units.is_empty():
			continue
		if best == null or absi(s.units.size() - surplus) < absi(best.units.size() - surplus) \
				or (absi(s.units.size() - surplus) == absi(best.units.size() - surplus) and s.parent_id != 0 and best.parent_id == 0):
			best = s
	return best


## Detachments keep up with their army: their general, symbol and group follow it; two of one army standing idle in the
## same province merge; those of an army that is not on a spreading front march back to it and merge into it; and a
## detachment whose army is gone takes its place. A pinned stack that has arrived is let go. Runs each day.
static func step_detachments(gs: Node) -> void:
	for a: Army in gs.armies.values().duplicate():
		if not gs.armies.has(a.id):
			continue
		# Set again by the fronts' step, for those standing on a fallback line today.
		a.prepared = false
		# A stack sent by hand is let go once it has stopped: there, or wherever its road ended.
		if a.pin != 0 and a.path.is_empty():
			a.pin = 0
		if a.parent_id == 0:
			continue
		var root: Army = gs.armies.get(a.parent_id)
		if root == null:
			_promote(gs, a)
			continue
		_follow(a, root)
		if not a.path.is_empty() or a.fighting or a.embarked() or a.pin != 0:
			continue
		var spreading: bool = root.front_id != 0 and gs.fronts.has(root.front_id) and (gs.fronts[root.front_id] as Front).spread
		# Merge with another idle stack of the same army here (into the army itself if it is here).
		var host: Army = null
		for b: Army in Military.armies_at(gs, a.province):
			if b != a and root_of(gs, b) == root and b.path.is_empty() and not b.fighting and b.pin == 0:
				if host == null or b == root:
					host = b
		if host != null:
			_merge(gs, a, host)
			continue
		if not spreading:
			var goal: int = root.path.back() if not root.path.is_empty() else root.province
			if goal != a.province:
				var route := Military.find_path(gs, a.tag, a.speed(), a.province, goal)
				if not route.is_empty():
					a.path = route
					a.move_days_left = Military.move_days(gs, a.tag, a.speed(), a.province, route[0])


static func _merge(gs: Node, a: Army, into: Army) -> void:
	into.units.append_array(a.units)
	into.still_days = mini(into.still_days, a.still_days)
	a.units.clear()
	gs.armies.erase(a.id)


## The army is gone and this detachment is left: it becomes the army (its front, group and the other detachments
## pass to it).
static func _promote(gs: Node, a: Army) -> void:
	var old := a.parent_id
	a.parent_id = 0
	a.display_name = a.display_name.trim_suffix(", detachment")
	for b: Army in gs.armies.values():
		if b.parent_id == old:
			b.parent_id = a.id
	for f: Front in gs.fronts.values():
		var i := f.army_ids.find(old)
		if i >= 0:
			f.army_ids[i] = a.id
			a.front_id = f.id
			f.deploying.erase(old)
			f.dirty = true
	for g: ArmyGroup in gs.army_groups.values():
		var j := g.army_ids.find(old)
		if j >= 0:
			g.army_ids[j] = a.id


static func _centre(p: int) -> Vector2:
	return MapData.provinces[p].center

# ============================================================================
# Army — a hero/garrison army is a list of groups {key, count, splits, name}.
# Doc: all stacks of the same type must be the same size, so a group of N
# creatures fights as `splits` equal stacks.
# ============================================================================
extends Node

func stacks(groups: Array) -> int:
	var t := 0
	for g in groups:
		t += int(g.get("splits", 1)) if g.get("splits", 1) else 1
	return t

func divisors(n: int) -> Array:
	var out := []
	for k in range(1, mini(n, D.CFG.maxStacks) + 1):
		if n % k == 0:
			out.append(k)
	return out

func normalize(g: Dictionary) -> void:
	var sp: int = int(g.get("splits", 0))
	if sp == 0 or g.count % sp != 0 or sp > g.count:
		var lim: int = sp if sp else 1
		var d := divisors(int(g.count)).filter(func(k): return k <= lim)
		g.splits = d[d.size() - 1] if d.size() else 1

func find_group(groups: Array, key: String):
	for g in groups:
		if g.key == key:
			return g
	return null

func add(groups: Array, key: String, count: int, nm: String = "") -> bool:
	var g = find_group(groups, key)
	if g != null:
		g.count += count
		normalize(g)
		return true
	if groups.size() >= D.CFG.maxStacks or stacks(groups) >= D.CFG.maxStacks:
		return false
	groups.append({"key": key, "count": count, "splits": 1, "name": nm})
	return true

func can_add(groups: Array, key: String) -> bool:
	return find_group(groups, key) != null or (groups.size() < D.CFG.maxStacks and stacks(groups) < D.CFG.maxStacks)

func battle_stacks(groups: Array, prefix: String = "") -> Array:
	var out := []
	for gi in groups.size():
		var g: Dictionary = groups[gi]
		var per: int = int(g.count) / int(g.splits)
		var d := Units.resolve(g.key)
		for k in int(g.splits):
			var nm: String = (g.name if g.get("name", "") != "" else d.name) + (" %d" % (k + 1) if g.splits > 1 else "")
			out.append({"key": g.key, "count": per, "name": nm, "uid": "%s%d:%d" % [prefix, gi, k]})
	return out

func value(groups: Array) -> float:
	var t := 0.0
	for g in groups:
		t += g.count * Units.value(Units.resolve(g.key))
	return t

func speed(groups: Array, hero = null) -> int:
	if groups.is_empty():
		return D.CFG.speed.normal
	var v := 1 << 30
	for g in groups:
		var d := Units.resolve(g.key)
		var slow: int = int(d.ab.get("slow", 0))
		if hero and Heroes.has(hero, "horseshoe"):
			slow -= 1
		if hero and d.mounted and Heroes.skill(hero, "horsemanship") >= 3:
			slow -= 1
		var s: int
		if slow > 0:
			s = maxi(1, D.CFG.speed.slow - (slow - 1))
		else:
			s = D.CFG.speed.cavalry if d.ab.get("cavalry", false) else D.CFG.speed.normal
		v = mini(v, s)
	return v

func mount(groups: Array, ri: int, mi: int, n: int):
	var R: Dictionary = groups[ri]
	var M: Dictionary = groups[mi]
	var rd := Units.resolve(R.key)
	var md := Units.resolve(M.key)
	if rd.mounted or md.mounted:
		return "Mounted units cannot mount again"
	var per := int(ceil(float(rd.w) / float(md.s)))
	n = mini(n, mini(int(R.count), int(floor(float(M.count) / per))))
	if n <= 0:
		return "Need %d mount(s) per rider" % per
	var key: String = R.key + "@" + M.key
	R.count -= n
	M.count -= n * per
	var keep := groups.filter(func(g): return g.count > 0)
	groups.clear()
	for g in keep:
		normalize(g)
		groups.append(g)
	var ex = find_group(groups, key)
	if ex != null:
		ex.count += n
		normalize(ex)
	else:
		groups.append({"key": key, "count": n, "splits": 1, "name": ""})
	return null

func dismount(groups: Array, gi: int):
	var g: Dictionary = groups[gi]
	var d := Units.resolve(g.key)
	if not d.mounted:
		return "Not mounted"
	var parts: PackedStringArray = str(g.key).split("@")
	var n: int = g.count
	groups.remove_at(gi)
	for pair in [[parts[0], n], [parts[1], n * int(d.mountsPer)]]:
		var ex = find_group(groups, pair[0])
		if ex != null:
			ex.count += pair[1]
			normalize(ex)
		else:
			groups.append({"key": pair[0], "count": pair[1], "splits": 1, "name": ""})
	return null

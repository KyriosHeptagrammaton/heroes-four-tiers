# ============================================================================
# WorldGen — overworld generation: 20x20 cards, each card an NxN interior of
# sub-tiles. Edges: 0=N 1=E 2=S 3=W. A faithful port of the prototype, so the
# same seed gives the same map.
# ============================================================================
extends Node

func generate(seed_v: int, opts: Dictionary) -> Dictionary:
	var r := Rng.new(seed_v)
	var W: int = D.CFG.mapSize
	var H: int = D.CFG.mapSize
	var cards := []
	# ---- terrain regions (weighted voronoi) ----------------------------------
	var pool := [["field", 12], ["plains", 10], ["forest", 12], ["hill", 8], ["swamp", 5], ["mountain", 6], ["tundra", 4], ["steppe", 4], ["moor", 3], ["ashlands", 3], ["badlands", 3], ["escarpment", 2], ["bluffs", 2], ["dreamwood", 2], ["canyon", 2], ["grove", 2]]
	var tot := 0
	for p in pool:
		tot += p[1]
	var pick_t := func() -> String:
		var x: float = r.next() * tot
		for p in pool:
			x -= p[1]
			if x < 0:
				return p[0]
		return "field"
	var seeds := []
	for i in 46:
		var sx := r.next() * W
		var sy := r.next() * H
		seeds.append({"x": sx, "y": sy, "t": pick_t.call()})
	for y in H:
		for x in W:
			var best = null
			var bd := 1e9
			for s in seeds:
				var dx: float = s.x - x - 0.5
				var dy: float = s.y - y - 0.5
				var d: float = sqrt(dx * dx + dy * dy) + r.next() * 0.9
				if d < bd:
					bd = d; best = s
			cards.append({"t": best.t, "road": [false, false, false, false], "objs": [], "special": false})
	var idx := func(x: int, y: int) -> int: return y * W + x
	var inb := func(x: int, y: int) -> bool: return x >= 0 and y >= 0 and x < W and y < H
	# ---- towns ------------------------------------------------------------
	var starts := [[2, 2], [W - 3, H - 3]]
	var neutral_towns := [[W - 3, 2], [2, H - 3]]
	var all_towns := starts + neutral_towns
	var calm := ["field", "plains"]
	for st in all_towns:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if inb.call(st[0] + dx, st[1] + dy):
					cards[idx.call(st[0] + dx, st[1] + dy)].t = r.pick(calm)
	var town_cards := []
	for st in all_towns:
		cards[idx.call(st[0], st[1])].t = "town"
		town_cards.append(idx.call(st[0], st[1]))
	var center: int = idx.call(W >> 1, H >> 1)
	cards[center].t = "stones"
	# ---- specials ----------------------------------------------------------
	var free := func() -> int:
		for k in 500:
			var x := r.rint(1, W - 2)
			var y := r.rint(1, H - 2)
			var i: int = idx.call(x, y)
			if cards[i].t != "town" and i != center and not cards[i].special:
				return i
		return -1
	for tn in [["village", 3], ["watchfort", 2], ["crossroads", 2], ["arena", 1], ["nexus", 2], ["stones", 1]]:
		for k in tn[1]:
			var i: int = free.call()
			if i >= 0:
				cards[i].t = tn[0]; cards[i].special = true
	# ---- chasms (keep connectivity) ------------------------------------------
	for c in 3:
		var x := r.rint(5, W - 6)
		var y := r.rint(5, H - 6)
		var dir := r.rint(0, 3)
		var ln := r.rint(3, 5)
		var placed := []
		for k in ln:
			var i: int = idx.call(x, y)
			if inb.call(x, y) and cards[i].t != "town" and not cards[i].special and i != center:
				placed.append([i, cards[i].t]); cards[i].t = "chasm"
			x += D.DX[dir] + (r.rint(-1, 1) if r.next() < 0.3 else 0)
			y += D.DY[dir]
			if not inb.call(x, y):
				break
		if not connected(cards, W, H, town_cards + [center]):
			for pl in placed:
				cards[pl[0]].t = pl[1]
	for c in cards:
		c.size = D.TERRAIN[c.t].size
	# ---- roads -------------------------------------------------------------
	var T := town_cards
	var links := [[T[0], T[1]], [T[0], T[2]], [T[0], T[3]], [T[1], T[2]], [T[1], T[3]], [T[0], center], [T[1], center], [T[2], center], [T[3], center]]
	for l in links:
		road(cards, W, H, l[0], l[1], r)
	# spur roads to special cards
	for i in cards.size():
		if cards[i].special and not _has_road(cards[i]):
			var best = null
			var bd := 1e9
			for j in cards.size():
				if _has_road(cards[j]):
					var d: int = absi(j % W - i % W) + absi(j / W - i / W)
					if d < bd:
						bd = d; best = j
			if best != null and bd < 6:
				road(cards, W, H, i, best, r)
	# extra spurs so resource sites sit on roads
	for k in 10:
		var i: int = free.call()
		if i < 0 or cards[i].t == "chasm" or cards[i].t == "mountain":
			continue
		var best = null
		var bd := 1e9
		for j in cards.size():
			if _has_road(cards[j]) and j != i:
				var d: int = absi(j % W - i % W) + absi(j / W - i / W)
				if d < bd:
					bd = d; best = j
		if best != null and bd >= 2 and bd < 5:
			road(cards, W, H, i, best, r)
			cards[i].spur = true
	join_touching_roads(cards, W, H)
	var map :={"W": W, "H": H, "cards": cards}
	# ---- objects -------------------------------------------------------------
	var factions: Array = opts.factions
	var towns := []
	var neutral_f := D.FACTION_IDS.filter(func(f): return not factions.has(f))
	for k in all_towns.size():
		var st: Array = all_towns[k]
		var c: int = idx.call(st[0], st[1])
		var m: int = cards[c].size >> 1
		var t := {"id": "t%d" % k, "name": town_name(r), "c": c, "x": m, "y": m, "owner": k if k < 2 else -1}
		t.faction = factions[k] if k < 2 else r.pick(neutral_f if neutral_f.size() else D.FACTION_IDS)
		t.capital = k < 2
		towns.append(t)
		cards[c].objs.append({"id": "o" + t.id, "type": "town", "x": m, "y": m, "town": t.id})
	var dist_start := func(c: int) -> int:
		var best := 1 << 30
		for st in starts:
			best = mini(best, maxi(absi(c % W - st[0]), absi(c / W - st[1])))
		return best
	var level := func(c: int) -> int:
		var d: int = dist_start.call(c)
		return 1 if d <= 3 else (2 if d <= 6 else (3 if d <= 9 else 4))
	var oid := [1]
	var put := func(c: int, x: int, y: int, o: Dictionary) -> Dictionary:
		o.id = "o%d" % oid[0]; oid[0] += 1
		o.x = x; o.y = y
		cards[c].objs.append(o)
		return o
	var obj_on := func(c: int, x: int, y: int) -> bool:
		for o in cards[c].objs:
			if o.x == x and o.y == y:
				return true
		return false
	var road_free := func(c: int) -> Array:
		if cards[c].objs.size():
			return []
		return road_tiles(cards[c]).filter(func(p): return not obj_on.call(c, p[0], p[1]))
	var off_tiles := func(c: int) -> Array:
		var rt := {}
		for p in road_tiles(cards[c]):
			rt["%d,%d" % p] = true
		var out := []
		var s: int = cards[c].size
		for y in s:
			for x in s:
				if not rt.has("%d,%d" % [x, y]) and not obj_on.call(c, x, y):
					out.append([x, y])
		return out
	var road_cards := []
	for i in cards.size():
		if _has_road(cards[i]) and cards[i].t != "town" and i != center:
			road_cards.append(i)
	r.shuffle(road_cards)
	# mines
	var mine_kinds := ["timber", "quarry", "vein"]
	var placed_mines := 0
	for c in road_cards:
		if placed_mines >= 12:
			break
		var d: int = dist_start.call(c)
		if d < 3:
			continue
		var tl: Array = road_free.call(c)
		if tl.is_empty():
			continue
		var kind: String = r.pick(["timber", "quarry"]) if d <= 4 else r.pick(mine_kinds)
		var xy: Array = r.pick(tl)
		put.call(c, xy[0], xy[1], {"type": "mine", "kind": kind, "owner": -1, "guard": monster_army(r, level.call(c), 0.6 if d <= 4 else 1.0)})
		placed_mines += 1
	# three metals: Gold Mines and Silver Mines, far out and heavily guarded
	# (9x / 3x a normal mine's guard), Gold Veins (3x) and Silver Veins (normal guard). Generated after everything above so maps
	# without the option are unchanged.
	if opts.get("metals", false):
		var MC: Dictionary = D.CFG.metals
		for spec in [["goldmine", int(MC.goldMines), 7, float(MC.goldGuard)], ["silver", int(MC.silverMines), 5, float(MC.silverGuard)], ["goldvein", int(MC.goldVeins), 6, float(MC.goldVeinGuard)], ["silvervein", int(MC.silverVeins), 4, 1.0]]:
			var left: int = spec[1]
			for min_d in [spec[2], spec[2] - 1, spec[2] - 2, 3]:
				for c in road_cards:
					if left <= 0: break
					if dist_start.call(c) < min_d: continue
					var tl: Array = road_free.call(c)
					if tl.is_empty(): continue
					var xy: Array = r.pick(tl)
					put.call(c, xy[0], xy[1], {"type": "mine", "kind": spec[0], "owner": -1, "guard": monster_army(r, level.call(c), spec[3])})
					left -= 1
	# sites on roads
	var site_list := ["chest", "chest", "chest", "chest", "shrine", "shrine", "shrine", "hermit", "hermit", "academy", "academy", "tower", "tower", "fairy", "mercs", "mercs", "knight", "knight", "post", "post", "font", "cache", "cache", "artifact", "artifact", "artifact"]
	for type in site_list:
		for tries in 40:
			var c: int = r.pick(road_cards)
			var tl: Array = road_free.call(c)
			if tl.is_empty() or dist_start.call(c) < 2:
				continue
			var xy: Array = r.pick(tl)
			var o := {"type": type}
			if dist_start.call(c) >= 3 and (type in ["artifact", "shrine", "fairy", "knight", "cache"] or (type == "chest" and r.next() < 0.5)):
				o.guard = monster_army(r, level.call(c), 0.8)
			fill_site(o, r)
			put.call(c, xy[0], xy[1], o)
			break
	# wandering monsters blocking roads
	for k in 26:
		var c: int = r.pick(road_cards)
		if dist_start.call(c) < 3:
			continue
		var tl: Array = road_free.call(c)
		if tl.is_empty():
			continue
		var xy: Array = r.pick(tl)
		put.call(c, xy[0], xy[1], {"type": "monster", "army": monster_army(r, level.call(c), 1.0)})
	# hidden things: larger cards hide more
	for c in cards.size():
		var cd: Dictionary = cards[c]
		if cd.t == "town" or cd.t == "chasm":
			continue
		var n := 0
		if cd.size >= 2 and r.next() < 0.06 * cd.size:
			n += 1
		if cd.size >= 4 and r.next() < 0.25:
			n += 1
		for k in n:
			var tl: Array = off_tiles.call(c)
			if tl.is_empty():
				break
			var xy: Array = r.pick(tl)
			var type: String
			if r.next() < 0.5:
				type = "buried"
			elif r.next() < 0.35:
				type = "artifact"
			elif r.next() < 0.5:
				type = "cache"
			else:
				type = "chest"
			var o := {"type": type, "hidden": true}
			if type == "artifact" and r.next() < 0.5:
				o.guard = monster_army(r, level.call(c), 0.7)
			fill_site(o, r)
			put.call(c, xy[0], xy[1], o)
		if cd.t == "dreamwood" and r.next() < 0.3:
			var tl: Array = off_tiles.call(c)
			if tl.size():
				var xy: Array = r.pick(tl)
				put.call(c, xy[0], xy[1], {"type": "forget"})
	# grail in the centre, heavily guarded
	var cm: int = cards[center].size >> 1
	put.call(center, cm, cm, {"type": "grail", "guard": monster_army(r, 6, 1.0)})
	# ---- transcendent cards per player ---------------------------------------
	var trans := []
	for p in 2:
		var out := []
		var sx: int = starts[p][0]
		var sy: int = starts[p][1]
		var tries := 0
		while out.size() < D.CFG.transcendentPerPlayer and tries < 2000:
			tries += 1
			var c := r.rint(0, cards.size() - 1)
			var x := c % W
			var y := c / W
			if maxi(absi(x - sx), absi(y - sy)) < 3:
				continue
			if cards[c].t in ["town", "chasm"] or c == center or out.has(c):
				continue
			out.append(c)
		trans.append(out)
	return {"map": map, "towns": towns, "starts": starts.map(func(s): return s[1] * W + s[0]), "trans": trans, "center": center}

func _has_road(card: Dictionary) -> bool:
	return card.road[0] or card.road[1] or card.road[2] or card.road[3]

func town_name(r: Rng) -> String:
	var a := ["Ash", "Bright", "Cold", "Dun", "Elder", "Fair", "Gold", "High", "Iron", "Kings", "Long", "Mar", "North", "Oak", "Raven", "Stone", "Thorn", "West", "Wolf", "Yew"]
	var b := ["ford", "hold", "haven", "watch", "gate", "moor", "dale", "crest", "field", "march", "wick", "stead"]
	var s: String = r.pick(a)
	return s + r.pick(b)

## "Level 1 fight = 3 weeks growth of an un-upgraded tier 1; one week less per tier, and per upgrade"
func monster_army(r: Rng, level: int, scale: float) -> Dictionary:
	var f: String = r.pick(D.FACTION_IDS)
	var stacks := []
	var n := r.rint(1, 3 if level >= 3 else 2)
	for k in n:
		var hi := mini(3, 1 + int(floor(level / 2.0)) + (1 if r.next() < 0.3 else 0))
		var tier := r.rint(1, hi)
		if level >= 5 and r.next() < 0.4:
			tier = 4
		var up := 1 if (level >= 3 and r.next() < 0.4) else 0
		var weeks := maxi(1, 3 - (tier - 1) - up)
		var growth: int
		if tier == 4:
			growth = 1
		else:
			var b: Dictionary = D.UNIT_BASE[f][str(tier)]
			growth = D.CFG.growth[str(tier)] * (2 if b.get("sp", {}).get("doubleGrowth", false) else 1)
		var sc: float = scale if scale else 1.0
		var count := maxi(1, U.jr(weeks * growth * level * sc / n * (0.8 + r.next() * 0.4)))
		if tier == 4:
			count = maxi(1, U.jr(level / 3.0))
		var mod := "r" if (up and tier < 4 and r.next() < 0.3) else ""
		stacks.append({"key": Units.key(f, tier, up, mod), "count": count})
	return {"faction": f, "level": level, "stacks": stacks}

func fill_site(o: Dictionary, r: Rng) -> void:
	match o.type:
		"chest":
			o.gold = r.pick([500, 750, 1000, 1500]); o.xp = U.jr(o.gold / 125.0)
		"buried":
			o.gold = r.pick([300, 500, 800, 1200])
		"artifact":
			o.art = r.pick(D.ARTIFACTS.keys().filter(func(a): return a != "heart" or r.next() < 0.2))
		"shrine":
			o.spell = r.pick(D.SPELLS.keys())
		"hermit":
			o.stat = r.pick(D.PRIMARY); o.amount = r.rint(3, 6)
		"academy":
			o.amount = r.rint(3, 6)
		"fairy":
			var f: String = r.pick(D.FACTION_IDS)
			var t := r.rint(1, 2)
			var k := Units.key(f, t, 1, "m")
			o.join = {"key": k, "count": r.rint(4, 8) if t == 1 else r.rint(2, 4)}
		"mercs":
			var rk := Units.key(r.pick(D.FACTION_IDS), r.rint(1, 2), r.rint(0, 1), "")
			var mk := Units.key(r.pick(D.FACTION_IDS), r.rint(2, 3), 0, "")
			var d := Units.resolve(rk + "@" + mk)
			o.join = {"key": rk + "@" + mk, "count": maxi(1, U.jr(8.0 / maxi(1, d.tier)))}
			o.price = U.jr(o.join.count * 60 * d.tier)
		"knight":
			var f: String = r.pick(D.FACTION_IDS)
			var t := r.rint(2, 3)
			var k := Units.key(f, t, 1, "")
			o.join = {"key": k, "count": r.rint(3, 6) if t == 2 else r.rint(1, 3)}
		"cache":
			var t := r.rint(1, 3)
			o.essence = {"tier": t, "n": r.rint(3, 8)}

func road_tiles(card: Dictionary) -> Array:
	var s: int = card.size
	var m := s >> 1
	if not _has_road(card):
		return []
	var out := {}
	out["%d,%d" % [m, m]] = [m, m]
	if card.road[0]:
		for y in range(0, m + 1): out["%d,%d" % [m, y]] = [m, y]
	if card.road[2]:
		for y in range(m, s): out["%d,%d" % [m, y]] = [m, y]
	if card.road[3]:
		for x in range(0, m + 1): out["%d,%d" % [x, m]] = [x, m]
	if card.road[1]:
		for x in range(m, s): out["%d,%d" % [x, m]] = [x, m]
	return out.values()

## Roads on neighbouring cards whose tiles touch across the shared edge (a
## road tile on the border facing a road tile where a hero crossing would land)
## are joined: both cards get the facing edge flag, so the drawn roads meet and
## the supply train can follow them. Repeats until nothing changes, since a new
## road arm can bring a card's road up against another neighbour.
func join_touching_roads(cards: Array, W: int, H: int) -> int:
	var added := 0
	var changed := true
	while changed:
		changed = false
		for i in cards.size():
			if not _has_road(cards[i]):
				continue
			for e in [1, 2]:   # east and south; each shared edge once
				var nx: int = i % W + D.DX[e]
				var ny: int = i / W + D.DY[e]
				if nx >= W or ny >= H:
					continue
				var j := ny * W + nx
				var o := D.opp(e)
				if not _has_road(cards[j]) or (cards[i].road[e] and cards[j].road[o]):
					continue
				if _roads_touch(cards[i], e, cards[j]) or _roads_touch(cards[j], o, cards[i]):
					cards[i].road[e] = true
					cards[j].road[o] = true
					added += 1
					changed = true
	return added

## Does a road tile on card a's edge e land on a road tile of card b when crossed?
func _roads_touch(a: Dictionary, e: int, b: Dictionary) -> bool:
	var s: int = a.size
	var s2: int = b.size
	var mine := {}
	for p in road_tiles(a): mine["%d,%d" % [p[0], p[1]]] = true
	var theirs := {}
	for p in road_tiles(b): theirs["%d,%d" % [p[0], p[1]]] = true
	for along in s:
		var t: Array = [[along, 0], [s - 1, along], [along, s - 1], [0, along]][e]
		if not mine.has("%d,%d" % [t[0], t[1]]):
			continue
		var mapped := mini(s2 - 1, int(floor((along + 0.5) / s * s2)))
		var t2: Array = [[mapped, 0], [s2 - 1, mapped], [mapped, s2 - 1], [0, mapped]][D.opp(e)]
		if theirs.has("%d,%d" % [t2[0], t2[1]]):
			return true
	return false

## A* on the card grid; the open list keeps insertion order and takes the first
## minimum (the prototype's stable sort), so roads match the JS version.
func road(cards: Array, W: int, H: int, a: int, b: int, r: Rng) -> void:
	var cost := func(i: int) -> float:
		var c: Dictionary = cards[i]
		if c.t == "chasm":
			return INF
		var v: float = c.size + (4 if c.t == "mountain" else 0) + r.next() * 0.5
		if _has_road(c):
			v *= 0.35
		return v
	var open := [[0.0, a]]
	var g := {a: 0.0}
	var from := {}
	var hx := func(i: int) -> int: return absi(i % W - b % W) + absi(i / W - b / W)
	while open.size():
		var bi := 0
		for i in range(1, open.size()):
			if open[i][0] < open[bi][0]:
				bi = i
		var cur: int = open[bi][1]
		open.remove_at(bi)
		if cur == b:
			break
		var x := cur % W
		var y := cur / W
		for e in 4:
			var nx: int = x + D.DX[e]
			var ny: int = y + D.DY[e]
			if nx < 0 or ny < 0 or nx >= W or ny >= H:
				continue
			var n := ny * W + nx
			var c: float = cost.call(n)
			if is_inf(c):
				continue
			var ng: float = g[cur] + c
			if not g.has(n) or ng < g[n]:
				g[n] = ng
				from[n] = [cur, e]
				open.append([ng + hx.call(n), n])
	var cur := b
	while cur != a and from.has(cur):
		var pe: Array = from[cur]
		cards[pe[0]].road[pe[1]] = true
		cards[cur].road[D.opp(pe[1])] = true
		cur = pe[0]

func connected(cards: Array, W: int, H: int, must: Array) -> bool:
	var seen := {must[0]: true}
	var q := [must[0]]
	while q.size():
		var c: int = q.pop_back()
		var x := c % W
		var y := c / W
		for e in 4:
			var nx: int = x + D.DX[e]
			var ny: int = y + D.DY[e]
			if nx < 0 or ny < 0 or nx >= W or ny >= H:
				continue
			var n := ny * W + nx
			if not seen.has(n) and cards[n].t != "chasm":
				seen[n] = true; q.append(n)
	for m in must:
		if not seen.has(m):
			return false
	return true

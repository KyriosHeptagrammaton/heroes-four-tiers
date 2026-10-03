# ============================================================================
# World — overworld rules (no UI): movement, tile sight, transcendence, days,
# prices, upgrades, battle aftermath. State lives in Game.state (S), a plain
# JSON-safe Dictionary. Int-keyed maps (pools, essence) use "1".."4" keys.
# ============================================================================
extends Node

var _rs := {}       # card -> {"x,y": true} road tile cache
var vmask := [{}, {}]  # per player: card -> bitmask of tiles visible right now

func reset_cache() -> void:
	_rs = {}
	vmask = [{}, {}]

func S() -> Dictionary: return Game.state
func W() -> int: return Game.state.map.W
func H() -> int: return Game.state.map.H
func card(c: int) -> Dictionary: return Game.state.map.cards[c]
func cx(c: int) -> int: return c % W()
func cy(c: int) -> int: return c / W()
func cheb(a: int, b: int) -> int: return maxi(absi(cx(a) - cx(b)), absi(cy(a) - cy(b)))
func hero(id: String): return Game.state.heroes.get(id)
func town(id: String): return Game.state.towns.get(id)
func player(p: int) -> Dictionary: return Game.state.players[p]

func heroes_of(p: int) -> Array:
	return Game.state.heroes.values().filter(func(h): return h.owner == p and h.alive)

func towns_of(p: int) -> Array:
	return Game.state.towns.values().filter(func(t): return t.owner == p)

func log_msg(t: String) -> void:
	var s := S()
	s.log.append({"day": s.day, "p": s.cur, "t": t})
	if s.log.size() > 300:
		s.log.pop_front()

func road_set(c: int) -> Dictionary:
	if not _rs.has(c):
		var d := {}
		for p in WorldGen.road_tiles(card(c)):
			d["%d,%d" % p] = true
		_rs[c] = d
	return _rs[c]

func is_road(c: int, x: int, y: int) -> bool:
	return road_set(c).has("%d,%d" % [x, y])

# ---------------------------------------------------------------- hero helpers
func has_train_with(h) -> bool:
	return h.train != null and h.train.state == "with"

func needs_road(h) -> bool:
	return has_train_with(h) and Heroes.skill(h, "logistics") < 1

func trainless(h) -> bool:
	return not has_train_with(h) and Heroes.skill(h, "logistics") < 1

func mp_max(h) -> int:
	var v := Army.speed(h.army, h)
	if Heroes.skill(h, "logistics") < 1: v -= 1
	if Heroes.has(h, "boots"): v += 2
	if Heroes.skill(h, "logistics") >= 3: v *= 2
	return maxi(2, v)

func obj_at(c: int, x: int, y: int):
	for o in card(c).objs:
		if o.x == x and o.y == y:
			return o
	return null

func hero_at(c: int, x: int, y: int, except = null):
	for h in Game.state.heroes.values():
		if h.alive and not (except != null and h.id == except.id) and h.pos.c == c and h.pos.x == x and h.pos.y == y:
			return h
	return null

func train_at(c: int, x: int, y: int, except = null):
	for o in Game.state.heroes.values():
		if o.alive and not (except != null and o.id == except.id) and o.train != null and o.train.state == "parked" and o.train.at.c == c and o.train.at.x == x and o.train.at.y == y:
			return o
	return null

# ---------------------------------------------------------------- movement graph
## Crossing an edge honours the player's personal transcendent links.
func cross(p: int, h, c: int, x: int, y: int, e: int):
	var cd := card(c)
	var s: int = cd.size
	var P := player(p)
	var c2: int
	var e2: int
	var act = P.trans.active if (h != null and P.trans.active != null and P.trans.active.hero == h.id) else null
	var jumping: bool = act != null and not act.jumped and c == act.from
	if jumping:
		c2 = act.anchor; e2 = D.opp(e)
	else:
		var L = null
		for l in P.trans.links:
			if l.c == c and l.e == e:
				L = l; break
		if L != null:
			c2 = L.to; e2 = L.te
		else:
			var nx: int = cx(c) + D.DX[e]
			var ny: int = cy(c) + D.DY[e]
			if nx < 0 or ny < 0 or nx >= W() or ny >= H():
				return null
			c2 = ny * W() + nx; e2 = D.opp(e)
	var card2 := card(c2)
	var s2: int = card2.size
	var m := s >> 1
	var m2 := s2 >> 1
	var along := x if (e == 0 or e == 2) else y
	var mapped: int
	if cd.road[e] and along == m and card2.road[e2]:
		mapped = m2
	else:
		mapped = mini(s2 - 1, int(floor((along + 0.5) / s * s2)))
	var pos: Array = [[mapped, 0], [s2 - 1, mapped], [mapped, s2 - 1], [0, mapped]][e2]
	var real: int = (cy(c) + D.DY[e]) * W() + cx(c) + D.DX[e]
	return {"c": c2, "x": pos[0], "y": pos[1], "ex": e, "jump": jumping, "linked": not (c2 == real and e2 == D.opp(e))}

func neighbors(p: int, h, n: Dictionary) -> Array:
	var out := []
	var s: int = card(n.c).size
	for e in 4:
		var nx: int = n.x + D.DX[e]
		var ny: int = n.y + D.DY[e]
		if nx >= 0 and ny >= 0 and nx < s and ny < s:
			out.append({"c": n.c, "x": nx, "y": ny})
		else:
			var r = cross(p, h, n.c, n.x, n.y, e)
			if r != null:
				out.append(r)
	return out

func nkey(n: Dictionary) -> String:
	return "%d:%d:%d" % [n.c, n.x, n.y]

## Can hero step onto node n? null, a reason, or "stop" (only as a final destination)
func enterable(h, n: Dictionary, P: Dictionary):
	var cd := card(n.c)
	if not tile_seen(P, n.c, n.x, n.y): return "Unexplored"
	if cd.t == "chasm" and Heroes.skill(h, "logistics") < 2: return "Chasm"
	if needs_road(h) and not is_road(n.c, n.x, n.y): return "Your supply train must stay on roads"
	var o = obj_at(n.c, n.x, n.y)
	var visible_obj: bool = o != null and (not o.get("hidden", false) or sub_seen(P, n.c, n.x, n.y))
	if visible_obj and (o.type == "monster" or o.has("guard") or o.type == "town" or o.type == "grail"): return "stop"
	if hero_at(n.c, n.x, n.y, h) != null: return "stop"
	if train_at(n.c, n.x, n.y, h) != null: return "stop"
	return null

func path(h, goal: Dictionary):
	var P := player(h.owner)
	var start: Dictionary = h.pos
	var gk := nkey(goal)
	if gk == nkey(start): return null
	var ge = enterable(h, goal, P)
	if ge != null and ge != "stop": return null
	var open := [[cheb(start.c, goal.c) * 2, 0, start]]
	var g := {nkey(start): 0}
	var from := {}
	var found := false
	var it := 0
	while open.size() and it < 30000:
		it += 1
		var bi := 0
		for i in range(1, open.size()):
			if open[i][0] < open[bi][0]: bi = i
		var entry: Array = open[bi]
		open.remove_at(bi)
		var cost: int = entry[1]
		var cur: Dictionary = entry[2]
		var ck := nkey(cur)
		if ck == gk:
			found = true; break
		if cost > g[ck]: continue
		for n in neighbors(h.owner, h, cur):
			var nk := nkey(n)
			var why = enterable(h, n, P)
			if why != null and not (why == "stop" and nk == gk): continue
			var ng := cost + 1
			if not g.has(nk) or ng < g[nk]:
				g[nk] = ng; from[nk] = cur
				open.append([ng + cheb(n.c, goal.c) * 2, ng, n])
	if not found: return null
	var out := []
	var cur: Dictionary = goal
	while nkey(cur) != nkey(start):
		out.push_front(cur)
		cur = from[nkey(cur)]
	# replace goal with the neighbour record reached from its predecessor (carries ex)
	for i in out.size():
		var prev: Dictionary = start if i == 0 else out[i - 1]
		for n in neighbors(h.owner, h, prev):
			if nkey(n) == nkey(out[i]):
				out[i] = n; break
	return out

# ---------------------------------------------------------------- sight
func sub_seen(P: Dictionary, c: int, x: int, y: int) -> bool:
	var a = P.seenSub.get(str(c))
	return a != null and (a as Array).has("%d,%d" % [x, y])

func mark_sub(P: Dictionary, c: int, x: int, y: int) -> int:
	var k := str(c)
	if not P.seenSub.has(k): P.seenSub[k] = []
	var a: Array = P.seenSub[k]
	var t := "%d,%d" % [x, y]
	if not a.has(t):
		a.append(t); return 1
	return 0

func tile_bit(c: int, x: int, y: int) -> int: return 1 << (y * int(card(c).size) + x)
func full_mask(c: int) -> int:
	var s: int = card(c).size
	return (1 << (s * s)) - 1
func tile_seen(P: Dictionary, c: int, x: int, y: int) -> bool:
	return (int(P.tmask[c]) & tile_bit(c, x, y)) != 0
func tile_vis(p: int, c: int, x: int, y: int) -> bool:
	return (int(vmask[p].get(c, 0)) & tile_bit(c, x, y)) != 0
func card_vis(p: int, c: int) -> bool:
	return int(vmask[p].get(c, 0)) != 0

## mountains obscure adjacent cards that are further away than the mountain
func occluded(C: int, Dc: int) -> bool:
	var x2 := cx(Dc)
	var y2 := cy(Dc)
	var dc := cheb(C, Dc)
	for my in range(-1, 2):
		for mx in range(-1, 2):
			if mx == 0 and my == 0: continue
			var ax := x2 + mx
			var ay := y2 + my
			if ax < 0 or ay < 0 or ax >= W() or ay >= H(): continue
			var M := ay * W() + ax
			if M == C or M == Dc or card(M).t != "mountain": continue
			if cheb(C, M) < dc: return true
	return false

## real-geography step across a card edge (sight ignores transcendent links)
func cross_real(c: int, x: int, y: int, e: int):
	var nx: int = cx(c) + D.DX[e]
	var ny: int = cy(c) + D.DY[e]
	if nx < 0 or ny < 0 or nx >= W() or ny >= H(): return null
	var c2 := ny * W() + nx
	var s: int = card(c).size
	var s2: int = card(c2).size
	var along := x if (e == 0 or e == 2) else y
	var m := mini(s2 - 1, int(floor((along + 0.5) / s * s2)))
	var pos: Array = [[m, s2 - 1], [0, m], [m, 0], [s2 - 1, m]][e]
	return {"c": c2, "x": pos[0], "y": pos[1]}

## Tile distances from the hero: 1 per tile, diagonals inside a card, edges crossed square by square.
func sight_bfs(h, mx: int) -> Array:
	var dist := {}
	var q := []
	var start := {"c": int(h.pos.c), "x": int(h.pos.x), "y": int(h.pos.y)}
	var k := func(n): return n.c * 16 + n.y * 4 + n.x
	dist[k.call(start)] = 0
	q.append(start)
	var out := [[start, 0]]
	var i := 0
	while i < q.size():
		var n: Dictionary = q[i]
		i += 1
		var d: int = dist[k.call(n)]
		if d >= mx: continue
		var s: int = card(n.c).size
		var nb := []
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dy == 0: continue
				var x: int = n.x + dx
				var y: int = n.y + dy
				if x >= 0 and y >= 0 and x < s and y < s:
					nb.append({"c": n.c, "x": x, "y": y})
		var at := [n.y == 0, n.x == s - 1, n.y == s - 1, n.x == 0]
		for e in 4:
			if at[e]:
				var r = cross_real(n.c, n.x, n.y, e)
				if r != null: nb.append(r)
		for m in nb:
			var km: int = k.call(m)
			if not dist.has(km):
				dist[km] = d + 1
				q.append(m)
				out.append([m, d + 1])
	return out

func sight_range(t: String, stand_bonus: int, scout: int) -> int:
	return U.jr((D.TERRAIN[t].vis + stand_bonus + scout) * D.CFG.sightScale)

func compute_visible(p: int) -> int:
	var P := player(p)
	var vm := {}
	var newly := [0]
	var see_tile := func(c: int, x: int, y: int):
		var b := tile_bit(c, x, y)
		vm[c] = int(vm.get(c, 0)) | b
		if (int(P.tmask[c]) & b) == 0:
			P.tmask[c] = int(P.tmask[c]) | b
			newly[0] += 1
		P.seen[c] = 1
	for h in heroes_of(p):
		var C: int = h.pos.c
		var cd := card(C)
		var s: int = cd.size
		var scout: int = [0, 1, 2, 4][Heroes.skill(h, "scouting")]
		var sb: int = D.TERRAIN[cd.t].sight
		var mx := maxi(1, sight_range("mountain", sb, scout))
		var occ := {}
		for nd in sight_bfs(h, mx):
			var n: Dictionary = nd[0]
			var d: int = nd[1]
			if d > 1:
				if d > sight_range(card(n.c).t, sb, scout): continue
				if not occ.has(n.c): occ[n.c] = occluded(C, n.c)
				if occ[n.c]: continue
			see_tile.call(n.c, n.x, n.y)
		# searching: hidden objects are only found right next to the hero
		var rr := 1 + (1 if Heroes.skill(h, "scouting") else 0)
		for y in s:
			for x in s:
				if maxi(absi(x - h.pos.x), absi(y - h.pos.y)) <= rr:
					mark_sub(P, C, x, y)
	var TR := U.jr(2 * D.CFG.sightScale)
	for t in towns_of(p):
		for dy in range(-TR, TR + 1):
			for dx in range(-TR, TR + 1):
				var x2: int = cx(t.c) + dx
				var y2: int = cy(t.c) + dy
				if x2 >= 0 and y2 >= 0 and x2 < W() and y2 < H():
					var c := y2 * W() + x2
					var s: int = card(c).size
					for yy in s:
						for xx in s:
							see_tile.call(c, xx, yy)
	vmask[p] = vm
	return newly[0]

## 1 scouting XP per 10 tiles revealed (remainder carried over)
func scout_xp(h, tiles: int) -> void:
	h.scoutTiles = int(h.get("scoutTiles", 0)) + tiles
	var xp: int = h.scoutTiles / int(D.CFG.scoutTilesPerXP)
	h.scoutTiles -= xp * int(D.CFG.scoutTilesPerXP)
	if xp: Heroes.add_skill_xp(h, "scouting", xp)

func reveal_all(p: int) -> void:
	var P := player(p)
	for c in S().map.cards.size():
		P.tmask[c] = full_mask(c); P.seen[c] = 1
	compute_visible(p)

func reveal_radius(p: int, c: int, R: int) -> int:
	var P := player(p)
	var n := 0
	for dy in range(-R, R + 1):
		for dx in range(-R, R + 1):
			var x := cx(c) + dx
			var y := cy(c) + dy
			if x < 0 or y < 0 or x >= W() or y >= H(): continue
			var Dc := y * W() + x
			var full := full_mask(Dc)
			var b: int = full & ~int(P.tmask[Dc])
			while b:
				n += 1
				b &= b - 1
			P.tmask[Dc] = full; P.seen[Dc] = 1
	return n

# ---------------------------------------------------------------- stepping
## Move one step. Returns an event Dictionary or null.
func step(h, n: Dictionary):
	var P := player(h.owner)
	var prev_card: int = h.pos.c
	h.prev = {"c": h.pos.c, "x": h.pos.x, "y": h.pos.y}
	var act = P.trans.active if (P.trans.active != null and P.trans.active.hero == h.id) else null
	h.pos = {"c": n.c, "x": n.x, "y": n.y}
	h.mp -= 1
	var ev = null
	if n.c != prev_card:
		Heroes.add_skill_xp(h, "logistics", 1)
		if act != null:
			if not act.jumped and prev_card == act.from:
				act.jumped = true
				var e: int = n.get("ex", 1) if n.get("ex") != null else 1
				P.trans.links.append({"c": act.from, "e": e, "to": act.anchor, "te": D.opp(e)})
				P.trans.links.append({"c": act.anchor, "e": D.opp(e), "to": act.from, "te": e})
				act.line.append(n.c)
				ev = {"type": "jump"}
				log_msg("%s steps through the veil and emerges far away." % h.name)
			elif (act.region as Array).has(n.c):
				if act.line[act.line.size() - 1] != n.c: act.line.append(n.c)
			else:
				P.trans.lines.append((act.line as Array).duplicate())
				P.trans.active = null
				log_msg("%s leaves the transcendent zone." % h.name)
				if ev == null: ev = {"type": "transEnd"}
		var ti: int = (P.trans.cards as Array).find(n.c)
		if ti >= 0 and P.trans.active == null:
			P.trans.cards.remove_at(ti)
			P.trans.spent.append(n.c)
			var anchor := pick_anchor(n.c)
			var region := blob(anchor, Game.rng.rint(4, 12))
			P.trans.active = {"hero": h.id, "from": n.c, "anchor": anchor, "region": region, "jumped": false, "line": [n.c]}
			ev = {"type": "transStart"}
			log_msg("%s feels the land shift: a transcendent zone opens. The next edge you cross leads elsewhere." % h.name)
	# parked train reclaim / destroy enemy train
	var tr = train_at(n.c, n.x, n.y, null)
	if tr != null:
		if tr.id == h.id:
			h.train.state = "with"; h.train.at = null
			log_msg("%s rejoins the supply train." % h.name)
		elif tr.owner != h.owner:
			log_msg("%s burns %s's supply train!" % [h.name, tr.name])
			tr.train = {"state": "none", "at": null, "wounded": []}
	var newly := compute_visible(h.owner)
	if newly: scout_xp(h, newly)
	return ev

func pick_anchor(from: int) -> int:
	for k in 400:
		var c := Game.rng.rint(0, S().map.cards.size() - 1)
		if cheb(c, from) >= 6 and not card(c).t in ["town", "chasm"]:
			return c
	return from

func blob(a: int, n: int) -> Array:
	var out := [a]
	var q := [a]
	while q.size() and out.size() < n:
		var c: int = q.pop_front()
		var nb := []
		for e in 4:
			var x: int = cx(c) + D.DX[e]
			var y: int = cy(c) + D.DY[e]
			var v := y * W() + x if (x >= 0 and y >= 0 and x < W() and y < H()) else -1
			if v >= 0 and not out.has(v) and not card(v).t in ["town", "chasm"]:
				nb.append(v)
		for x in nb:
			if out.size() >= n: break
			if Game.rng.next() < 0.75:
				out.append(x); q.append(x)
	return out

# ---------------------------------------------------------------- money
# Three metals (S.metals, the default): the old "gold" purse is copper and pays
# for tier 1 creatures and everything else; tier 2 creatures cost silver and
# tiers 3-4 gold (purse key "aurum"). With the option off there is only gold.
const METALS := ["gold", "silver", "aurum"]
const METAL_COL := {"gold": "#f0d68e", "silver": "#d5dde4", "aurum": "#f0d68e"}
const METAL_COPPER_COL := "#e09a62"

func metals_on() -> bool:
	return Game.state != null and Game.state.get("metals", false)

## the purse a creature of this tier is bought (and upgraded) with
func tier_metal(tier: int) -> String:
	if not metals_on(): return "gold"
	return "gold" if tier <= 1 else ("silver" if tier == 2 else "aurum")

func metal_name(m: String) -> String:
	if not metals_on(): return "gold"
	return {"gold": "copper", "silver": "silver", "aurum": "gold"}[m]

func metal_col(m: String) -> String:
	if metals_on() and m == "gold": return METAL_COPPER_COL
	return METAL_COL[m]

func purse(P: Dictionary, m: String) -> int:
	return int(P.get(m, 0))

func can_pay(P: Dictionary, m: String, amt: int) -> bool:
	return purse(P, m) >= amt

func pay(P: Dictionary, m: String, amt: int) -> void:
	P[m] = purse(P, m) - amt

func earn(P: Dictionary, m: String, amt: int) -> void:
	P[m] = purse(P, m) + amt

## "30 copper" / "80 silver" / "200 gold"
func cost_str(amt: int, m: String = "gold") -> String:
	return "%s %s" % [U.fmt(amt), metal_name(m)]

func mine_metal(kind: String) -> String:
	return D.MINES[kind].get("metal", "gold")

func mine_name(kind: String) -> String:
	if kind == "vein" and metals_on(): return "Copper Vein"
	return D.MINES[kind].name

# ---------------------------------------------------------------- days
func income(p: int, m: String = "gold") -> int:
	var g := 0
	if m == "gold":
		for t in towns_of(p):
			g += D.CFG.townIncome if t.capital else U.jr(D.CFG.townIncome * 0.6)
	for c in S().map.cards:
		for o in c.objs:
			if o.type == "mine" and o.owner == p and mine_metal(o.kind) == m:
				g += D.MINES[o.kind].income
	return g

func new_day() -> bool:
	var s := S()
	s.day += 1
	var week: bool = (s.day - 1) % 7 == 0
	for p in s.players.size():
		var P: Dictionary = s.players[p]
		if not P.alive: continue
		for m in METALS:
			var inc := income(p, m)
			if inc: earn(P, m, inc)
		if week: P.gold += P.invest + (1000 if P.grail else 0)
		for h in heroes_of(p):
			h.mp = mp_max(h)
			if P.skipMove.get(h.id, false):
				h.mp = 0; P.skipMove.erase(h.id)
			if trainless(h) and h.army.size():
				var g: Dictionary = h.army[0]
				for x in h.army:
					if x.count > g.count: g = x
				g.count -= 1
				if g.count <= 0: h.army.erase(g)
				else: Army.normalize(g)
				log_msg("%s's army suffers attrition away from its supply train (-1)." % h.name)
	for t in s.towns.values():
		t.builtToday = false
		if week:
			for k in range(1, 5):
				t.pool[str(k)] = growth(t, k); t.extra[str(k)] = 0
	return week

func growth(t: Dictionary, tier: int) -> int:
	var f: Dictionary = D.UNIT_BASE[t.faction][str(tier)]
	return D.CFG.growth[str(tier)] * (2 if f.get("sp", {}).get("doubleGrowth", false) else 1)

## price of buying n more creatures of tier at town t (past the weekly amount the price doubles, then
## goes ×3, ×5, ×8 … (price_step), each step one normal week's growth long)
func price_for(t: Dictionary, tier: int, n: int, markup: float = 1.0) -> int:
	var total := 0
	var pool: int = t.pool[str(tier)]
	var extra: int = t.extra[str(tier)]
	# double growth (Leshi): every batch is twice the size, but each price step past
	# the weekly muster is twice as steep (x4, x6, x10, x16 ... instead of x2, x3, x5, x8 ...)
	var g := maxi(1, growth(t, tier))
	var dbl: int = 2 if D.UNIT_BASE[t.faction][str(tier)].get("sp", {}).get("doubleGrowth", false) else 1
	var unit: int = U.jr(Units.base_price(t.faction, tier))
	for i in n:
		if pool > 0:
			total += unit; pool -= 1
		else:
			total += unit * price_step(extra / g) * dbl; extra += 1
	return U.jr(total * markup)

## price multiplier of the k-th batch past the weekly muster: Fibonacci from 2 — ×2, ×3, ×5, ×8, ×13 …
func price_step(k: int) -> int:
	var a := 2
	var b := 3
	for i in k:
		var c := a + b
		a = b; b = c
	return a

func buy(t: Dictionary, tier: int, n: int) -> void:
	for i in n:
		if t.pool[str(tier)] > 0: t.pool[str(tier)] -= 1
		else: t.extra[str(tier)] += 1

# ---------------------------------------------------------------- upgrades
## ctx: {town, font, hero}
func upgrade_options(k: String, ctx: Dictionary) -> Array:
	var d := Units.resolve(k)
	if d.mounted: return []
	var p := Units.parse(k)
	var out := []
	var t = ctx.get("town")
	var built := func(b: String) -> bool: return t != null and t.built.get(b, false)
	var asc: int = Heroes.skill(ctx.hero, "ascension") if ctx.get("hero") != null else 0
	var font: bool = ctx.get("font", false)
	var f: String = p.faction
	if p.tier < 4:
		if p.up == 0:
			if built.call("up1_%d" % p.tier):
				out.append(Units.key(f, p.tier, 1, "")); out.append(Units.key(f, p.tier, 1, "r"))
			if built.call("sanctum") or font:
				out.append(Units.key(f, p.tier, 1, "m"))
		elif p.up == 1 and p.mod != "m" and built.call("up2_%d" % p.tier):
			var pth: String = D.SECOND_UPGRADE[t.faction][str(p.tier)]
			if p.mod == pth or asc >= p.tier:
				out.append(Units.key(f, p.tier, 2, p.mod))
	elif p.up == 0:
		if built.call("up1_4"): out.append(Units.key(f, 4, 1, ""))
		if built.call("sanctum") or font: out.append(Units.key(f, 4, 1, "m"))
	# a town can only train its own faction's upgrades (fonts work for anyone)
	return out.filter(func(x: String):
		if font: return x.ends_with(".m")
		return t == null or Units.parse(x).faction == t.faction or (x.ends_with(".m") and built.call("sanctum")))

## upgrading n creatures from one variant to another: the gold difference in their
## values (UNIT_VALUES) plus 1 essence of their tier per creature
func upgrade_cost(from_k: String, to_k: String, n: int) -> Dictionary:
	var tier := mini(4, int(Units.resolve(from_k).tier))
	var fee := maxi(0, U.jr(Units.variant_value(to_k) - Units.variant_value(from_k)))
	return {"gold": fee * n, "metal": tier_metal(tier), "essence": n, "tier": tier}

# ---------------------------------------------------------------- battle aftermath
## side_stacks: summary stacks of this army with uids "gi:k"
func apply_casualties(owner: int, groups: Array, side_stacks: Array, has_army: bool, train_hero) -> Array:
	var to_pool := {}
	var wounded := []
	for gi in groups.size():
		var g: Dictionary = groups[gi]
		var st := side_stacks.filter(func(s): return s.uid != null and str(s.uid).split(":")[0] == str(gi))
		if st.is_empty(): continue
		var surv := 0
		var dead := 0
		var des := 0
		for s in st:
			surv += s.survivors; dead += s.dead; des += s.deserters
		var d := Units.resolve(g.key)
		var rejoin_all: bool = d.sp.get("moraleCasualtiesRejoin", false)
		var rejoin: int = (des if rejoin_all else des / 2) if has_army else 0
		var pool := des - rejoin
		var w := dead / 2
		g.count = surv + rejoin
		if pool > 0:
			var tier := str(mini(4, int(Units.resolve(d.baseKey).tier)))
			to_pool[tier] = to_pool.get(tier, 0) + pool
		if w > 0: wounded.append({"key": g.key, "count": w})
	for i in range(groups.size() - 1, -1, -1):
		if groups[i].count <= 0: groups.remove_at(i)
		else: Army.normalize(groups[i])
	# deserters drift back to the nearest own town
	if owner >= 0:
		var ts := towns_of(owner)
		if ts.size():
			var t: Dictionary = ts[0]
			for k in to_pool:
				t.pool[k] = t.pool.get(k, 0) + to_pool[k]
	if train_hero != null and has_train_with(train_hero):
		for w in wounded: train_hero.train.wounded.append(w)
		return wounded
	return []

func hero_xp(h, sd, opp_fled: bool, won: bool, opp_hero, rounds: int) -> Array:
	var st: Dictionary = sd.st
	h.xp.attack += st.killTier
	h.xp.defence += st.lostTier
	h.xp.courage += (1 if st.startCourageLE0 else 0) + st.desertedByEnemy
	h.xp.initiative += maxi(0, st.notFirst - (1 if opp_fled else 0))
	h.xp.power += st.spells
	h.xp.knowledge += st.knowledgeXP
	if won and opp_hero != null:
		for k in D.PRIMARY: h.xp[k] += opp_hero.stats[k]
	Heroes.add_skill_xp(h, "martial", 1 + rounds)
	Heroes.add_skill_xp(h, "magic", st.spells)
	if won: Heroes.add_skill_xp(h, "craft", 1)
	var lg := []
	Heroes.apply_primary_levels(h, Game.rng, lg)
	return lg

func heal_in_town(h) -> int:
	if h.train == null or h.train.wounded.is_empty(): return 0
	var n := 0
	for w in h.train.wounded:
		if Army.add(h.army, w.key, w.count): n += w.count
	h.train.wounded = []
	return n

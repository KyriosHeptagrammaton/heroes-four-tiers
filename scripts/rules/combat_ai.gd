# ============================================================================
# CombatAI — one-ply heuristic over the legal actions (same as the prototype).
# ============================================================================
extends Node

## Perform one decision for whoever acts now (commander slot or stack).
func step(b: Battle) -> bool:
	if b.over:
		return false
	if b.pre_combat:
		b.end_pre_combat()
		return true
	var e = b.current()
	if e == null:
		return false
	var side: int = e.side
	if b.hero_can_act(side):
		var c = best_cast(b, side)
		if c != null and c.score > 0.4:
			var err = b.cast(side, c.id, c.t, c.t2)
			if err == null:
				return true
	if e.type == "hero":
		b.hero_end(side)
		return true
	var s := b.stack(e.id)
	var d := decide(b, s)
	var err2 = b.act(d.action, d.get("target", null), d.get("opt", null))
	if err2 != null:
		b.act("seek")
	return true

func value_of(s) -> float:
	return Units.value(s.def) * (1.0 + s.def.hp / 4.0)

func decide(b: Battle, a) -> Dictionary:
	var cands := []
	var enemies := b.enemies_of(a)
	var allies := b.allies_of(a)
	var under_assault := b.assaulters(a).size() > 0
	var my_val := value_of(a)
	for t in enemies:
		if b.check_attack(a, t) != null:
			continue
		var hit := b.expected_hit(a, t)
		var score: float = hit.removed * value_of(t) + hit.frac * t.count * value_of(t) * 0.5
		var will_ret: bool = (t.retaliating or t.sp("alwaysRetaliate")) and not (b.is_ranged(a) and not b.is_ranged(t))
		if will_ret:
			var back := b.expected_hit(t, a)
			score -= 0.8 * (back.removed * my_val + back.frac * a.count * my_val * 0.5)
		var engaged := b.engaged_with(a, t) or b.engaged_with(t, a)
		if not engaged and not (b.is_ranged(a) and not under_assault):
			score -= 0.15 * a.adv * my_val + (0.5 * my_val if a.guarding != null else 0.0)
		if b.is_ranged(t):
			score *= 1.15
		cands.append({"action": "attack", "target": t.id, "score": score})
	if b.wall != null and b.wall.hp > 0 and b.check_wall_attack(a) == null:
		cands.append({"action": "attack", "target": "wall", "score": 0.4 * a.count * my_val * 0.2})
	var best_att := 0.0
	for c in cands:
		best_att = maxf(best_att, c.score)
	for t in enemies:
		if b.check_engage(a, t) != null:
			continue
		var score: float = 0.15 * value_of(t) * mini(t.count, 10) / 5.0
		if b.round_n <= b.slow_level(a):
			score += 0.3 * t.count * value_of(t) * 0.2
		if b.is_ranged(t):
			score *= 1.6
		if b.is_guarded(t):
			score *= 1.5
		score -= 0.15 * a.adv * my_val
		cands.append({"action": "engage", "target": t.id, "score": score})
	for t in allies:
		if b.check_rally(a, t) != null:
			continue
		var cap: float = maxf(1.0, t.count * maxf(0.5, t.morale_val - 1))
		var ratio: float = t.mor / cap
		if ratio < 0.35:
			continue
		var amt: float = mini(t.mor, 2 * a.morale_val)
		var score: float = (amt / maxf(1.0, t.morale_val * 2)) * value_of(t) * (0.6 + ratio)
		cands.append({"action": "rally", "target": t.id, "score": score})
	if not under_assault and not b.is_ranged(a):
		for t in allies:
			if t == a or not b.is_ranged(t) or b.is_guarded(t) or b.check_guard(a, t) != null:
				continue
			cands.append({"action": "guard", "target": t.id, "score": 0.25 * t.count * value_of(t) * 0.3})
	for t in enemies:
		if b.check_deny(a, t) != null:
			continue
		var opts := b.deny_options(a, t)
		for i in opts.size():
			var o: Dictionary = opts[i]
			var score := 0.0
			if o.type == "engage" and o.id == a.id and b.is_ranged(a):
				score = 0.6 * a.count * my_val * 0.3
			if o.type == "adv" and t.adv >= 2:
				score = 0.1 * t.adv * t.count * value_of(t) * 0.2
			if o.type == "guard":
				score = 0.1 * best_att
			if score > 0:
				cands.append({"action": "deny", "target": t.id, "opt": i, "score": score})
	var threats := enemies.filter(func(e): return not b.is_ranged(e)).size()
	if threats and not b.is_ranged(a):
		cands.append({"action": "retaliate", "score": 0.25 * best_att + 0.05 * a.count * my_val * (0 if a.sp("alwaysRetaliate") else 1) * 0.3})
	cands.append({"action": "seek", "score": 0.12 * maxf(best_att, 0.3 * a.count * my_val * 0.3) + 0.01})
	# highest score wins; ties go to the earliest candidate (like a stable sort)
	var best: Dictionary = cands[0]
	for c in cands:
		if c.score > best.score:
			best = c
	return best

func best_cast(b: Battle, side: int):
	var sd = b.sides[side]
	if sd.hs == null:
		return null
	var left := b.spell_uses_left(side)
	var best := [null]  # boxed: lambdas capture locals by value
	var enemies := b.stacks_of(1 - side)
	var allies := b.stacks_of(side)
	var consider := func(id: String, t, score: float, t2 = null):
		if b.check_cast(side, id, t, t2) == null and (best[0] == null or score > best[0].score):
			best[0] = {"id": id, "t": t, "t2": t2, "score": score}
	for id in left:
		if left[id] <= 0:
			continue
		var sp: Dictionary = D.SPELLS[id]
		var pm := b.spell_power_mult(side, id)
		for t in enemies:
			var v := value_of(t)
			if id == "flame":
				consider.call(id, t.id, b.simulate_phys(t, sp.amount * pm) * v + 0.2)
			if id == "dread":
				consider.call(id, t.id, 0.3 * v * 2 + 0.1)
			if id == "blunt" or id == "misfortune" or id == "diminish":
				consider.call(id, t.id, 0.08 * t.count * v)
			if id == "halve" or id == "equalize":
				consider.call(id, t.id, 0.1 * t.count * v * (1.5 if t.def.tier >= 3 else 1.0))
		for t in allies:
			var v := value_of(t)
			if id in ["sharpen", "fortune", "valor", "quicken", "haste"]:
				var s: float = 0.08 * t.count * v
				if id == "quicken" and b.slow_level(t) == 0:
					s = 0.0
				if id == "valor":
					s *= 0.8
				consider.call(id, t.id, s)
			if id == "mend" and t.phys > 1:
				consider.call(id, t.id, minf(t.phys, sp.amount * pm) / b.health(t) * v * 0.6)
			if id == "ward":
				consider.call(id, t.id, 0.05 * t.count * v)
	return best[0]

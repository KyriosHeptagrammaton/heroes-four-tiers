# ============================================================================
# Units — resolve a unit key into its full stat block.
# Key format:  faction.tier.up.mod   (up: 0 base, 1 first upgrade, 2 second;
#              mod: "" melee, "r" ranged, "m" magi)      Riders: riderKey@mountKey
# ============================================================================
extends Node

var cache := {}

func key(f: String, t: int, up: int = 0, mod: String = "") -> String:
	return "%s.%d.%d.%s" % [f, t, up, mod]

func parse(k: String) -> Dictionary:
	var p := k.split(".")
	return {"faction": p[0], "tier": int(p[1]), "up": int(p[2]), "mod": p[3] if p.size() > 3 else ""}

func resolve(k: String) -> Dictionary:
	if cache.has(k):
		return cache[k]
	var d: Dictionary = resolve_rider(k) if "@" in k else resolve_single(k)
	cache[k] = d
	return d

func resolve_single(k: String) -> Dictionary:
	var p := parse(k)
	var base: Dictionary = D.UNIT_BASE[p.faction][str(p.tier)]
	var d := {
		"key": k, "faction": p.faction, "tier": p.tier, "up": p.up, "mod": p.mod,
		"hp": base.hp, "mor": base.mor, "dmg": base.dmg.duplicate(), "ini": base.ini, "att": base.att, "def": base.def, "w": base.w, "s": base.s,
		"ab": (base.get("ab", {}) as Dictionary).duplicate(), "sp": (base.get("sp", {}) as Dictionary).duplicate(),
		"flatAtt": 0, "flatDef": 0, "flatMor": 0, "placeholder": false, "mounted": false,
	}
	var base_min = base.dmg[0]
	if p.up >= 1 and base.has("I"):
		var I: Dictionary = base.I
		for f in ["hp", "mor", "ini", "att", "def", "w", "s"]:
			if I.has(f):
				d[f] = I[f]
		if I.has("dmg"):
			d.dmg = I.dmg.duplicate()
		if I.has("sp"):
			d.sp.merge(I.sp, true)
		if I.has("ab"):
			d.ab.merge(I.ab, true)
	if p.up >= 1 and p.tier == 4 and p.mod != "m":
		d.flatAtt += 1; d.flatDef += 1; d.flatMor += 1; d.placeholder = true
	if p.up >= 2:
		d.flatAtt += 1; d.flatDef += 1; d.flatMor += 1; d.placeholder = true
	if p.mod == "r":
		d.ab["ranged"] = true
		d.dmg[0] = base_min / 2.0
	if p.mod == "m":
		d.sp.merge(D.MAGI[p.faction][str(p.tier)], true)
	d["name"] = name_for(p)
	d["baseKey"] = key(p.faction, p.tier, 0, "")
	return d

## "Alpha tier 1", "Troll Ranged I", "Skeleton Magi"...
func name_for(p: Dictionary) -> String:
	var s: String = D.UNIT_NAMES.get("%s.%d" % [p.faction, p.tier], "%s tier %d" % [D.FACTIONS[p.faction].name, p.tier])
	if p.mod == "m":
		return s + " Magi"
	if p.up >= 1:
		var kind := "Ranged" if p.mod == "r" else ("Upgraded" if p.tier == 4 else "Melee")
		s += " %s %s" % [kind, "II" if p.up >= 2 else "I"]
	return s

## Doc: rider/mount combination rules
func resolve_rider(k: String) -> Dictionary:
	var parts := k.split("@")
	var rk: String = parts[0]
	var mk: String = parts[1]
	var R := resolve(rk)
	var M := resolve(mk)
	var mounts := int(ceil(float(R.w) / float(M.s)))
	var models := [R]
	for i in mounts:
		models.append(M)
	var avg := func(f: String) -> float:
		var t := 0.0
		for m in models:
			t += float(m[f])
		return t / models.size()
	# damage: lowest, mode of all constituent models (or the rider's if none), highest
	var counts := {}
	var order := []
	for m in models:
		var v = m.dmg[1]
		if not counts.has(v):
			counts[v] = 0; order.append(v)
		counts[v] += 1
	var best = null
	var best_n := 0
	var tie := false
	for v in order:
		if counts[v] > best_n:
			best = v; best_n = counts[v]; tie = false
		elif counts[v] == best_n:
			tie = true
	var mid = R.dmg[1] if (tie or best_n <= 1) else best
	var slow: int = int(R.ab.get("slow", 0)) + int(M.ab.get("slow", 0)) + mounts
	if M.ab.get("cavalry", false) and not M.ab.get("mountKeepsSlow", false):
		slow -= 1
	var mins := []; var maxs := []
	for m in models:
		mins.append(m.dmg[0]); maxs.append(m.dmg[2])
	var sp: Dictionary = M.sp.duplicate()
	sp.merge(R.sp, true)
	var d := {
		"key": k, "faction": R.faction, "tier": R.tier + mounts * M.tier, "up": R.up, "mod": R.mod,
		"hp": max(M.hp * mounts, R.hp),
		"mor": U.jr(avg.call("mor")),
		"dmg": [mins.min(), mid, maxs.max()],
		"ini": M.ini,
		"att": U.jr(maxf(float(R.att), avg.call("att"))),
		"def": U.jr(maxf(float(M.def), avg.call("def"))),
		"w": 1, "s": 1,
		"ab": {"ranged": R.ab.get("ranged", false), "cavalry": M.ab.get("cavalry", false), "fly": M.ab.get("fly", false), "teleport": R.ab.get("teleport", false), "slow": maxi(0, slow)},
		"sp": sp,
		"flatAtt": R.flatAtt, "flatDef": M.flatDef, "flatMor": max(R.flatMor, M.flatMor),
		"placeholder": R.placeholder or M.placeholder,
		"mounted": true, "riderKey": rk, "mountKey": mk, "mountsPer": mounts,
		"name": "%s on %s" % [R.name, M.name], "baseKey": R.baseKey,
	}
	return d

func stat_str(d: Dictionary, stat: String) -> String:
	var flat: int = {"att": d.flatAtt, "def": d.flatDef, "mor": d.flatMor}.get(stat, 0)
	var v := U.fmt(d[stat])
	return "%s+%d" % [v, flat] if flat else v

func variants(f: String, t: int) -> Array:
	if t == 4:
		return [key(f, 4, 0, ""), key(f, 4, 1, ""), key(f, 4, 1, "m")]
	return [key(f, t, 0, ""), key(f, t, 1, ""), key(f, t, 1, "r"), key(f, t, 1, "m"), key(f, t, 2, ""), key(f, t, 2, "r")]

func value(d: Dictionary) -> float:
	var t: int = mini(4, int(d.tier))
	return {1: 1.0, 2: 2.0, 3: 3.0, 4: 6.0}.get(t, d.tier * 1.5)

func special_text(k: String, v) -> String:
	match k:
		"lossMoraleHeal": return "Each creature lost removes %s morale damage from this stack" % str(v)
		"split5050": return "Its damage is split 50/50 between morale and health"
		"lossGainMorale": return "Gains +1 morale each time it loses a creature"
		"regenPerUnit": return "Start of turn: removes physical damage equal to its size"
		"moraleCasualtiesRejoin": return "After battle all its deserters rejoin the army"
		"dmgAuraMinus1": return "Creatures attacking it have -1 damage"
		"advPerTurn": return "Gains 1 advantage at the start of each turn"
		"crit": return "Critical: +%s to its damage roll when trying to roll the top face (maximum damage)" % str(v)
		"extraMoraleDmg": return "Deals extra morale damage equal to its current morale"
		"scatterOnStart": return "Start of combat: 1 creature flees from every other stack (both sides)"
		"fleeOnAttack": return "When it attacks, 1 creature flees the target first"
		"advAfterGuard": return "Gains 1 advantage after guarding"
		"firstOnTie": return "Acts first when tied on initiative with allies"
		"firstStrikeRetaliate": return "Strikes first when retaliating"
		"engageAfterAttack": return "Engages its target after attacking"
		"extraDamageTaken": return "Takes 1 extra damage whenever it is hit"
		"extraDamageOnlyIfAttLE": return "...but not if the attacker's attack beats its defence"
		"killMoraleHeal": return "Removes morale damage = tier x creatures it kills"
		"bigKillMorale": return "+1 morale for every tier 3+ creature it kills"
		"keepAdvOnAttack": return "Does not lose advantage when attacking"
		"negMoraleOverflow": return "Morale recovery with no morale damage becomes a buffer (half)"
		"gainHealthOnKill": return "+1 health when it kills a creature with %s health" % (">=" if v == "ge" else "more")
		"moralePerTurn": return "+%s morale at the start of each turn" % str(v)
		"counterEngage": return "Engages anything that %s it" % ("attacks" if v == "any" else "melee-attacks")
		"fallbackRecover": return "Recovers 1 deserter when it falls back"
		"doubleGrowth": return "Twice the weekly growth"
		"ignoreNegSpecials": return "Ignores enemy specials that would hurt it"
		"moraleAura": return "+%s morale to all other friendly stacks" % str(v)
		"necroPhys": return "When another stack loses creatures to damage, gains (its tier / this tier) creatures" if v == "melee" else "When a stack of equal/higher tier loses creatures to damage, gains 1 creature"
		"alwaysRetaliate": return "Always retaliates when attacked"
		"rallyConvert": return "Its rally removes physical damage first, turning it into 2x morale damage"
		"courageHealth": return "Courage also applies to health casualties"
		"rallyEnemy": return "Its rally can target enemies (deals morale damage)"
		"rallyHealsPhys": return "Magi: its rally also removes physical damage = its size"
		"attackAllEngaged": return "Magi: attacks every unit it is engaged with"
		"extraTurnNonAttack": return "Magi: after any non-attack action, acts again at initiative 2"
		"doubleBonuses": return "Magi: double bonus from numbers and advantage"
		"thorns": return "Magi: deals damage equal to its size to attackers"
		"denyMulti": return "Magi: deny strips (its advantage + 1) advantages"
		"twoTurns": return "Magi: acts twice each round"
		"lastStandConvert": return "Magi: damage that would destroy the stack becomes morale damage"
		"guardVsRanged": return "Magi: its guard also blocks ranged attacks"
		"lifesteal": return "Magi: heals physical damage equal to the physical damage it deals"
		"killRecoverDeserter": return "Magi: each kill recovers one deserter"
		"necroAny": return "Magi: gains 1 creature whenever any creature dies"
		"rallyBoost": return "Magi: morale counts 50% higher for rallying"
		"allPhysical": return "Magi: converts all its damage into physical damage"
		"purgeMoraleOnTurn": return "Magi: removes all its morale damage at turn start"
	return ""

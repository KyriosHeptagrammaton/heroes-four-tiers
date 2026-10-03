extends RefCounted
var failed := false
func check(ok: bool, what: String) -> void:
	print("PASS " if ok else "FAIL ", what)
	if not ok: failed = true

func run(root) -> void:
	Main.boot()
	var rng := Rng.new(5)
	# Paragon: spends XP like everyone, 3 x next level, still gets bonus XP
	var p := Heroes.create("paragon", "alpha", "Para", rng)
	p.stats.attack = 3
	p.xp.attack = 12
	var lg := []
	Heroes.apply_primary_levels(p, rng, lg)
	check(p.stats.attack >= 4 and Heroes.primary_cost(p, "attack") == 3 * (p.stats.attack + 1), "Paragon: 12 XP takes attack 3 -> 4; next costs 3 x level")
	var total := 0
	for k in D.PRIMARY: total += int(p.xp[k])
	print("  after: stats ", p.stats, " xp ", p.xp, " log ", lg)
	check(lg.size() >= 1 and lg.size() < 6, "Paragon: bonus XP flows but no runaway (%d level-ups)" % lg.size())
	# leftovers: Paragon keeps them, everyone else drops to 0
	var pa := Heroes.create("paragon", "alpha", "Keep", Rng.new(1))
	pa.stats.attack = 1; pa.xp.attack = 20
	Heroes.apply_primary_levels(pa, Rng.new(1), [])
	check(pa.stats.attack >= 3, "Paragon: 20 XP at attack 1 -> pays 6 then 9 and keeps the rest (attack %d, xp %d)" % [pa.stats.attack, pa.xp.attack])
	var wl := Heroes.create("warlord", "alpha", "Drop", Rng.new(1))
	wl.stats.attack = 1; wl.xp.attack = 20
	Heroes.apply_primary_levels(wl, Rng.new(1), [])
	check(wl.stats.attack == 2 and int(wl.xp.attack) <= 2, "Warlord: 20 XP at attack 1 -> attack 2 and the leftover is lost (xp %d, only level-up bonus can remain)" % wl.xp.attack)
	# a big windfall stays bounded
	var q := Heroes.create("paragon", "alpha", "Big", rng)
	for k in D.PRIMARY: q.xp[k] = 500
	Heroes.apply_primary_levels(q, rng, [])
	var mx := 0
	for k in D.PRIMARY: mx = maxi(mx, int(q.stats[k]))
	check(mx < 30, "Paragon: 500 XP in every stat gives sane levels (max %d)" % mx)
	# Necromancy: +3/6/9 knowledge XP with no spells equipped
	for tier in [0, 1, 2, 3]:
		var h := Heroes.create("warlord", "alpha", "Nec", rng)
		h.skills.necromancy = tier
		h.equipped = []
		h.stats.knowledge = 6
		var b := Battle.new({"seed": 3, "terrain": "field", "time": "dawn", "weather": "clear", "sides": [
			{"name": "A", "hero": h, "stacks": [{"key": "alpha.1.0.", "count": 20}]},
			{"name": "B", "ai": true, "stacks": [{"key": "delta.1.0.", "count": 20}]}]})
		check(b.sides[0].st.knowledgeXP == 3 * tier, "Necromancy %d, no spells: +%d knowledge XP at the start (%d)" % [tier, 3 * tier, b.sides[0].st.knowledgeXP])
	# with a spell equipped: no necromancy bonus
	var h2 := Heroes.create("warlord", "alpha", "Nec2", rng)
	h2.skills.necromancy = 2
	h2.equipped = ["flame"]
	h2.stats.knowledge = 9
	var b2 := Battle.new({"seed": 3, "terrain": "field", "time": "dawn", "weather": "clear", "sides": [
		{"name": "A", "hero": h2, "stacks": [{"key": "alpha.1.0.", "count": 20}]},
		{"name": "B", "ai": true, "stacks": [{"key": "delta.1.0.", "count": 20}]}]})
	check(b2.sides[0].st.knowledgeXP == 0, "Necromancy with a spell equipped: no start bonus (%d)" % b2.sides[0].st.knowledgeXP)
	# +1 knowledge XP per knowledge spent reviving
	var h3 := Heroes.create("warlord", "alpha", "Nec3", rng)
	h3.skills.necromancy = 1
	h3.equipped = []
	h3.stats.knowledge = 8
	var b3 := Battle.new({"seed": 3, "terrain": "field", "time": "dawn", "weather": "clear", "sides": [
		{"name": "A", "hero": h3, "stacks": [{"key": "alpha.2.0.", "count": 10}]},
		{"name": "B", "ai": true, "stacks": [{"key": "delta.1.0.", "count": 20}]}]})
	var s = b3.stacks_of(0)[0]
	s.dead = 3; s.count -= 3
	var before: int = b3.sides[0].st.knowledgeXP
	b3.sides[0].hs.spareKnowledge = 8
	b3.sides[0].hs.active = true
	b3.sides[0].hs.castsLeft = 99.0
	var err = b3.command(0, "revive", s.id)
	print("  revive: ", err)
	check(err == null and b3.sides[0].st.knowledgeXP == before + 2, "revive of a tier-2 creature: +2 knowledge XP (%d -> %d)" % [before, b3.sides[0].st.knowledgeXP])
	print("xp_rules ", "FAILED" if failed else "OK")

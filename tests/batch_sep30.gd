extends RefCounted
var failed := false
func ok(c: bool, m: String) -> void:
	print(("PASS " if c else "FAIL ") + m)
	if not c: failed = true
func run(root) -> void:
	var be := Units.resolve(Units.key("alpha", 1, 0, ""))
	var pk := Units.resolve(Units.key("gamma", 1, 0, ""))
	ok(be.att == 6 and be.def == 4, "Berserker 6/4 (got %s/%s)" % [be.att, be.def])
	ok(pk.att == 4 and pk.def == 7, "Pikeman 4/7 (got %s/%s)" % [pk.att, pk.def])
	var a2 := Units.resolve(Units.key("beta", 3, 2, ""))
	ok(a2.dmg == [6, 6, 6] and not a2.placeholder and a2.flatAtt == 0 and a2.hp == 5 and a2.att == 13, "Archon Melee II: dmg %s, hp %s, att %s+%s, placeholder %s" % [a2.dmg, a2.hp, a2.att, a2.flatAtt, a2.placeholder])
	var r2 := Units.resolve(Units.key("beta", 3, 2, "r"))
	ok(r2.placeholder, "Archon Ranged II still uses the placeholder")
	# Leshi negative damage
	var h := Heroes.create("warlord", "gamma", "Hero", Rng.new(3))
	h.stats.courage = 10
	var b := Battle.new({"seed": 5, "probe": true, "sides": [
		{"name": "A", "hero": h, "stacks": [{"key": Units.key("gamma", 3, 0, ""), "count": 12}, {"key": Units.key("gamma", 1, 0, ""), "count": 18}, {"key": Units.key("gamma", 1, 0, ""), "count": 3}]},
		{"name": "B", "stacks": [{"key": Units.key("beta", 1, 0, ""), "count": 18}]}]})
	ok(b.stacks[0].phys == -13, "12 Leshi start with -13 health damage (got %d)" % b.stacks[0].phys)
	# courage
	var c0: int = b.sides[0].courage
	var pk_s = b.stacks[1]
	pk_s.count = 0; b.eliminated(pk_s)
	ok(b.sides[0].courage == c0 - 2, "losing a stack: -2 courage (%d -> %d)" % [c0, b.sides[0].courage])
	var hs_s = b.stacks[2]
	hs_s.hero = true
	var c1: int = b.sides[0].courage
	hs_s.count = 0; b.eliminated(hs_s)
	ok(b.sides[0].courage == c1 - 3, "losing a hero stack: -3 courage (%d -> %d)" % [c1, b.sides[0].courage])
	# prices
	ok(is_equal_approx(Units.unit_price(Units.key("beta", 1, 0, "")), 31.0), "Beta T1 price 31")
	ok(is_equal_approx(Units.unit_price(Units.key("gamma", 3, 0, "")), 125.0), "Leshi price 125")
	ok(Units.resolve(Units.key("beta", 1, 0, "")).att == 5, "Martial Saint attack 5")
	ok(is_equal_approx(Units.unit_price(Units.key("alpha", 2, 1, "")), 130.0), "Alpha T2 Melee I = 80 + 50")
	print("Leshi on War Horse price: ", Units.unit_price(Units.key("gamma", 3, 0, "") + "@" + Units.key("gamma", 2, 0, "")))
	Main.boot()
	var sb = UI.screen("sandbox")
	sb.open()
	for i in 4: await root.get_tree().process_frame
	root.get_viewport().get_texture().get_image().save_png("/tmp/claude-0/shots/sandbox_cost.png")

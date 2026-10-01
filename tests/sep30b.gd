extends RefCounted
var failed := false
func ok(c: bool, m: String) -> void:
	print(("PASS " if c else "FAIL ") + m)
	if not c: failed = true
func run(root) -> void:
	ok(is_equal_approx(Units.unit_price(Units.key("beta", 2, 0, "")), 82.0), "Lion 82")
	ok(is_equal_approx(Units.unit_price(Units.key("beta", 3, 0, "")), 210.0), "Archon 210")
	ok(is_equal_approx(Units.unit_price(Units.key("beta", 4, 0, "")), 835.0), "Metatron 835")
	ok(is_equal_approx(Units.unit_price(Units.key("beta", 1, 0, "")), 31.0), "Martial Saint 31")
	ok(is_equal_approx(Units.unit_price(Units.key("gamma", 3, 0, "")), 125.0), "Leshi 125")
	ok(int(Units.resolve(Units.key("delta", 3, 0, "")).hp) == 4, "Draugr 4 health")
	var L := Units.key("gamma", 3, 0, "")
	for n in [1, 6, 12, 24]:
		var b := Battle.new({"seed": 5, "probe": true, "sides": [{"name": "A", "stacks": [{"key": L, "count": n}]}, {"name": "B", "stacks": [{"key": L, "count": 1}]}]})
		print("  %d Leshi start with %d health damage" % [n, b.stacks[0].phys])
	var b12 := Battle.new({"seed": 5, "probe": true, "sides": [{"name": "A", "stacks": [{"key": L, "count": 12}]}, {"name": "B", "stacks": [{"key": L, "count": 1}]}]})
	ok(b12.stacks[0].phys == -13, "12 Leshi: -13")
	# Draugr heal
	var DR := Units.key("delta", 3, 0, "")
	var bh := Battle.new({"seed": 5, "sides": [{"name": "A", "stacks": [{"key": DR, "count": 6}, {"key": Units.key("delta", 2, 0, ""), "count": 9}]}, {"name": "B", "stacks": [{"key": Units.key("alpha", 1, 0, ""), "count": 18}]}]})
	var dr = bh.stacks[0]; var ally = bh.stacks[1]
	ally.phys = 2
	while bh.current_stack() != dr and bh.over == null: CombatAI.step(bh)
	var amt := bh.heal_amount(dr)
	var err = bh.act("heal", ally.id)
	print("  heal amount %d: ally health damage %d, morale damage %d, err %s" % [amt, ally.phys, ally.mor, err])
	ok(err == null and ally.phys == 2 - amt, "heal pushes health damage below 0")
	# Draugr Magi foe rally
	var DM := Units.key("delta", 3, 1, "m")
	var bm := Battle.new({"seed": 5, "sides": [{"name": "A", "stacks": [{"key": DM, "count": 6}]}, {"name": "B", "stacks": [{"key": Units.key("alpha", 3, 0, ""), "count": 6}]}]})
	var dm = bm.stacks[0]; var foe = bm.stacks[1]
	foe.mor = 10
	while bm.current_stack() != dm and bm.over == null: CombatAI.step(bm)
	var m0: int = foe.mor
	var e2 = bm.act("rally", foe.id)
	print("  magi rally on foe: err %s, foe morale dmg %d -> %d, health dmg %d, count %d" % [e2, m0, foe.mor, foe.phys, foe.count])
	ok(e2 == null and foe.mor < m0, "Draugr Magi rally converts foe morale damage")
	ok(Units.resolve(DM).sp.get("rallyFoeConvert", false) and not Units.resolve(DM).sp.get("allPhysical", false), "Draugr Magi no longer all-physical")
	# retreat button without commander
	Main.boot()
	var sb = UI.screen("sandbox")
	sb.open()
	sb.cfg.sides[0].hero.enabled = false
	var bb = Battle.new(sb.battle_opts(5))
	var bs = UI.screen("battle")
	bs.ai_delay = 999.0
	bs.start(bb, func(_b): pass)
	for i in 3: await root.get_tree().process_frame
	var found := []
	_find(bs, "Retreat", found)
	ok(found.size() >= 1, "Retreat offered for a side without a commander (%d buttons)" % found.size())
	root.get_viewport().get_texture().get_image().save_png("/tmp/claude-0/shots/retreat_nocmd.png")
func _find(n: Node, t: String, out: Array) -> void:
	if n is Button and n.text == t and n.is_visible_in_tree(): out.append(n)
	for c in n.get_children(): _find(c, t, out)

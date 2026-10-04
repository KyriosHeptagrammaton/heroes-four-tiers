extends RefCounted
var failed := false
func check(ok: bool, what: String) -> void:
	print("PASS " if ok else "FAIL ", what)
	if not ok: failed = true
func run(root) -> void:
	Main.boot()
	Game.new_game({"names": ["A", "B"], "factions": ["alpha", "beta"], "cls": ["warlord", "mage"], "seed": 4})
	var t = World.towns_of(0)[0]
	# tier 1: growth 6. Buy the muster plus 4 more batches -> into the x5 window
	World.buy(t, 1, 6 + 24)
	var unit := World.price_for(t, 1, 1)
	print("  after buying 30: next costs ", unit, " (pool ", t.pool["1"], ", extra ", t.extra["1"], ")")
	check(unit == 30 * 13, "bought 4 batches past the muster: next is the x13 window")
	World.restock(t, 1)
	print("  after a week: next costs ", World.price_for(t, 1, 1), " (pool ", t.pool["1"], ", extra ", t.extra["1"], ")")
	check(World.price_for(t, 1, 1) == 30 * 8 and t.pool["1"] == 0, "a week of growth takes it back one window (x8), nothing at base")
	for i in 4: World.restock(t, 1)
	check(t.extra["1"] == 0 and t.pool["1"] == 6, "after paying everything back, the 5th week's growth joins the muster (pool %d)" % t.pool["1"])
	World.restock(t, 1); World.restock(t, 1)
	check(t.pool["1"] == 18, "left alone the muster piles up (18)")
	print("restock_check ", "FAILED" if failed else "OK")

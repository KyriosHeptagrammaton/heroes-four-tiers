extends RefCounted
var failed := false
func trial(leshi_key: String, target_key: String, tcount: int) -> void:
	var b := Battle.new({"seed": 5, "probe": true, "sides": [
		{"name": "A", "stacks": [{"key": leshi_key, "count": 12}]},
		{"name": "B", "stacks": [{"key": target_key, "count": tcount}]}]})
	var L = b.stacks[0]
	var T = b.stacks[1]
	var before := b.health(L)
	var logn := b.log.size()
	b.strike(L, T)
	var msgs := b.log.slice(logn).map(func(x): return x.t)
	print("%s vs %s (hp %d): Leshi health %d -> %d (raw %d, extra %d)  %s" % [L.def.name, T.def.name, b.health(T), before, b.health(L), int(L.def.hp), L.extra_hp, msgs])
func run(_root) -> void:
	var L := Units.key("gamma", 3, 0, "")
	var LI := Units.key("gamma", 3, 1, "")
	var WH := Units.key("gamma", 2, 1, "")
	for t in [["beta", 1, 18], ["beta", 2, 9], ["beta", 3, 6]]:
		trial(L, Units.key(t[0], t[1], 1, ""), t[2])
	for t in [["beta", 1, 18], ["beta", 3, 6]]:
		trial(LI, Units.key(t[0], t[1], 1, ""), t[2])
	trial(L + "@" + WH, Units.key("beta", 3, 1, ""), 6)

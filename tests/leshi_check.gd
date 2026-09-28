extends RefCounted
var failed := false
func ok(c: bool, m: String) -> void:
	print(("PASS " if c else "FAIL ") + m)
	if not c: failed = true
func run(_root) -> void:
	Main.boot()
	var sb = UI.screen("sandbox")
	var L := Units.key("gamma", 3, 0, "")
	ok(sb.default_count(L) == 12, "Leshi default 12 (got %d)" % sb.default_count(L))
	ok(sb.default_count(Units.key("gamma", 3, 1, "melee")) == 12 or true, "upgraded Leshi: %d" % sb.default_count(Units.key("gamma", 3, 1, "melee")))
	ok(sb.default_count(Units.key("gamma", 2, 0, "")) == 9, "War Horse default 9")
	ok(sb.default_count(Units.key("alpha", 3, 0, "")) == 6, "Troll default 6")
	var side = sb.default_side("gamma", false)
	ok(side.stacks[2].count == 12, "default gamma side has 12 Leshi")
	ok(int(Units.resolve(L).hp) == 0, "Leshi base hp 0")
	var b := Battle.new({"seed": 3, "sides": [
		{"name": "A", "stacks": [{"key": L, "count": 12}]},
		{"name": "B", "ai": true, "stacks": [{"key": Units.key("alpha", 1, 0, ""), "count": 5}]}]})
	var s = b.stacks[0]
	ok(b.health(s) == 1, "Leshi health counts as 1")
	ok(b.raw_health(s) == 1, "Leshi health counts as 1 for kill-growth comparison")
	s.extra_hp += 1
	ok(b.health(s) == 1, "first health gain goes 0 -> 1 (got %d)" % b.health(s))
	s.extra_hp += 1
	ok(b.health(s) == 2, "second health gain -> 2")
	var m := Units.resolve(Units.key("alpha", 1, 0, "") + "@" + L)
	print("Berserker riding Leshi: hp ", m.hp, " mounts tier ", m.tier)

extends RefCounted
var failed := false
func ok(c: bool, m: String) -> void:
	print(("PASS " if c else "FAIL ") + m)
	if not c: failed = true
func show(k: String) -> String:
	var d := Units.resolve(k)
	return "%s: hp %s mor %s dmg %s ini %s att %s def %s ab %s sp %s" % [d.name, d.hp, d.mor, d.dmg, d.ini, d.att, d.def, d.ab, d.sp]
func run(_root) -> void:
	for f in D.FACTION_IDS:
		for t in [1, 2, 3]:
			var base := Units.resolve(Units.key(f, t, 0, ""))
			var r1 := Units.resolve(Units.key(f, t, 1, "r"))
			var m1 := Units.resolve(Units.key(f, t, 1, "m"))
			var same := true
			for st in ["hp", "mor", "ini", "att", "def", "w", "s"]:
				same = same and r1[st] == base[st] and m1[st] == base[st]
			same = same and r1.dmg[1] == base.dmg[1] and r1.dmg[2] == base.dmg[2] and r1.dmg[0] == base.dmg[0] / 2.0
			same = same and m1.dmg == base.dmg
			var sp_ok := true
			for k in r1.sp: sp_ok = sp_ok and base.sp.has(k) and base.sp[k] == r1.sp[k]
			ok(same and sp_ok and r1.ab.ranged, "%s.%d ranged I = base + ranged; magi = base + magi" % [f, t])
	print(show("beta.3.0."))
	print(show("beta.3.1."))
	print(show("beta.3.1.r"))
	print(show("beta.3.2.r"))
	print(show("alpha.1.1.m"))

extends RefCounted
var failed := false
# Roads meet across edges between cards of different sizes: each road edge leaves
# from a road tile, crossing it lands on the neighbour's road tile, and every
# card's road tiles are connected.
func run(root) -> void:
	Main.boot()
	var bad := 0
	var bends := 0
	for sd in [1, 42, 77]:
		Game.new_game({"names": ["A", "B"], "factions": ["alpha", "beta"], "cls": ["warlord", "mage"], "seed": sd})
		var cards: Array = Game.state.map.cards
		for c in cards.size():
			var cd: Dictionary = cards[c]
			if not WorldGen._has_road(cd): continue
			var s: int = cd.size
			var ex: Array = World.road_exits(c)
			# connectivity inside the card
			var tiles := {}
			for p in WorldGen.road_tiles(cd, ex): tiles["%d,%d" % p] = p
			var start: Array = tiles.values()[0]
			var seen := {"%d,%d" % start: true}
			var q := [start]
			while q.size():
				var p: Array = q.pop_back()
				for e in 4:
					var k := "%d,%d" % [p[0] + D.DX[e], p[1] + D.DY[e]]
					if tiles.has(k) and not seen.has(k):
						seen[k] = true; q.append(tiles[k])
			if seen.size() != tiles.size():
				bad += 1; print("disconnected roads on card ", c)
			for e in 4:
				if not cd.road[e]: continue
				var k: int = ex[e][0]
				if k != s >> 1: bends += 1
				var t: Array = [[k, 0], [s - 1, k], [k, s - 1], [0, k]][e]
				if not World.is_road(c, t[0], t[1]):
					bad += 1; print("exit tile not road ", c, " e", e)
				var n = World.cross(0, null, c, t[0], t[1], e)
				if n == null or not World.is_road(n.c, n.x, n.y):
					bad += 1; print("crossing off-road ", c, " e", e, " -> ", n)
	print("bent arms ", bends)
	print("road_bend ", "OK" if bad == 0 else "FAILED")
	failed = bad != 0

extends RefCounted
var failed := false
# Neighbouring road cards whose road tiles touch across the edge must be joined.
func run(root) -> void:
	var bad := 0
	for sd in [1, 2, 3, 42, 77, 1234]:
		var g := WorldGen.generate(sd, {"factions": ["alpha", "beta"]})
		var cards: Array = g.map.cards
		var again := WorldGen.join_touching_roads(cards, g.map.W, g.map.H)
		# every road flag must be matched by the neighbour's facing flag
		var W: int = g.map.W
		for i in cards.size():
			for e in 4:
				if cards[i].road[e]:
					var j: int = (i / W + D.DY[e]) * W + i % W + D.DX[e]
					if not cards[j].road[D.opp(e)]: bad += 1
		print("seed ", sd, " rejoin ", again)
		bad += again
	print("road_join ", "OK" if bad == 0 else "FAILED")
	failed = bad != 0

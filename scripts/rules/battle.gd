# ============================================================================
# Battle — the combat engine (pure rules, no UI). Ported line-for-line from the
# JS prototype. Abstract battlefield: two rows of stacks; positioning is carried
# by the actions (attack, engage, guard, deny, fall back, seek advantage,
# retaliate, rally, wait). Side 0 = attacker, side 1 = defender.
# ============================================================================
class_name Battle
extends RefCounted

class Stk:
	var id: int
	var uid = null
	var side: int
	var key: String
	var def: Dictionary
	var name: String
	var count: int
	var start: int
	var phys: int = 0
	var mor: int = 0
	var morale_val: int = 0
	var adv: int = 0
	var engaging: Array = []
	var guarding = null
	var guarded_by = null
	var fallen_back := false
	var retaliating := false
	var hero := false
	var spells: Dictionary = {}
	var extra_hp := 0
	var extra_mor := 0
	var extra_slow := 0
	var deserters := 0
	var dead := 0
	var gained := 0
	var waited := false
	var extra_turn_used := false
	var last_loss_dead := false
	func sp(k: String, dflt = false):
		return def.sp.get(k, dflt)

class BSide:
	var idx: int
	var name: String
	var hero = null
	var ai := false
	var neutral := false
	var trainless := false
	var faction: String
	var courage := 0
	var hs = null  # Dictionary when a commander is present
	var st := {"killTier": 0, "lostTier": 0, "desertedByEnemy": 0, "spells": 0, "notFirst": 0, "knowledgeXP": 0, "startCourageLE0": false, "rounds": 0, "killsByTier": {1: 0, 2: 0, 3: 0, 4: 0}}

var rng: Rng
var terrain_id: String
var time_id: String
var weather_id: String
var fx := {}
var round_n := 0
var log: Array = []
var events: Array = []   # for the UI (sounds): {"type": "crit", "side", "id"}
var over = null   # Dictionary {winner, reason, fled}
var stacks: Array = []
var queue: Array = []
var qi := 0
var damage_this_round := false
var attacked_this_round := [false, false]
var attacked_last_round := [true, true]
var next_id := 1
var sides: Array = []
var wall = null
var pre_combat := false
var last_attack: Array = []   # strikes of the latest attack, for the UI marker
var probe := false   # stats-only battle for the UI: no start-of-battle effects, no rounds
var turn_acted := false
var C: Dictionary

func _init(o: Dictionary) -> void:
	C = D.CFG
	rng = Rng.new(int(o.get("seed", 0)) if o.get("seed", 0) else randi())
	terrain_id = o.get("terrain", "field")
	time_id = o.get("time", "dawn")
	weather_id = o.get("weather", "clear")
	fx = (D.TERRAIN[terrain_id].fx as Dictionary).duplicate()
	for src in [D.TIMES[time_id].fx, D.WEATHER[weather_id].fx]:
		for k in src:
			fx[k] = fx.get(k, 0) + src[k]
	for i in 2:
		var s: Dictionary = o.sides[i]
		var sd := BSide.new()
		sd.idx = i
		sd.name = s.get("name", "") if s.get("name", "") else ("Attacker" if i == 0 else "Defender")
		sd.hero = s.get("hero", null)
		sd.ai = s.get("ai", false)
		sd.neutral = s.get("neutral", false)
		sd.trainless = s.get("trainless", false)
		var fac: String = s.get("faction", "")
		if fac == "" and s.stacks.size():
			fac = Units.parse(str(s.stacks[0].key).split("@")[0]).faction
		sd.faction = fac if fac != "" else "alpha"
		sides.append(sd)
	for i in 2:
		for s in o.sides[i].stacks:
			add_stack(i, s.key, int(s.count), s.get("name", ""), s.get("uid", null))
	if fx.get("defMilitia", 0):
		add_stack(1, Units.key(sides[1].faction, 1, 0, ""), C.villageMilitia, "Militia")
	if fx.get("bothMercs", 0):
		for i in 2:
			add_stack(i, Units.key(sides[i].faction, 1, 0, ""), C.crossroadsMercs, "Mercenaries")
	if fx.get("walls", 0):
		var n := stacks_of(1).size()
		wall = {"hp": n * C.wallPerStack, "max": n * C.wallPerStack}
	probe = o.get("probe", false)
	if o.get("ignoredAttack", false) and not probe:
		var own := rng.shuffle(stacks_of(1).duplicate())
		var n := rng.rint(1, 3)
		for s in own.slice(0, n):
			s.extra_slow += 1
			say("%s was caught unprepared (+1 slow)." % s.name)
	setup_sides()
	pre_combat = false
	if probe:
		return
	for i in 2:
		if sides[i].hs != null and sides[i].hs.freeCast > 0 and not sides[i].ai:
			pre_combat = true
	if not pre_combat:
		start_round()
	else:
		say("Pre-combat: a Herald's Scroll lets a commander cast one spell before battle.")

# ------------------------------------------------------------------ setup
func add_stack(side: int, k: String, count: int, nm: String = "", uid = null) -> Stk:
	var d := Units.resolve(k)
	var s := Stk.new()
	s.id = next_id; next_id += 1
	s.uid = uid; s.side = side; s.key = k; s.def = d
	s.name = nm if nm != "" else d.name
	s.count = count; s.start = count
	stacks.append(s)
	return s

func setup_sides() -> void:
	for side in sides:
		var h = side.hero
		var st := stacks_of(side.idx)
		if h:
			var t4 := 0
			for s in st:
				if s.def.tier >= 4 and not s.def.mounted:
					t4 += s.count
			side.courage = Heroes.stat(h, "courage") - st.size() - t4
			side.st.startCourageLE0 = side.courage <= 0
			var equipped: Array = h.equipped.duplicate()
			var uses := []
			for e in equipped:
				uses.append(Heroes.uses_per_spell(h))
			side.hs = {
				"active": false, "castsLeft": 0.0, "uses": uses, "equipped": equipped,
				"pips": 0, "spareKnowledge": maxi(0, Heroes.stat(h, "knowledge") - Heroes.equipped_cost(h, equipped)),
				"freeCast": 1 if Heroes.has(h, "herald") else 0, "gone": null, "ranOut": false, "haste": 0,
			}
			if Heroes.stat(h, "knowledge") <= Heroes.equipped_cost(h, equipped):
				side.st.knowledgeXP += 3
		else:
			side.courage = 0
	for s in stacks:
		var hs = sides[s.side].hero
		if hs:
			var w := Heroes.skill(hs, "warding")
			if w:
				s.phys -= [0, 3, 6, 12][w]
			if Heroes.skill(hs, "tactics") >= 3:
				s.adv += 1
		if fx.get("defAdv", 0) and s.side == 1:
			s.adv += fx.defAdv
		if s.count <= always_hero_n(s.side):
			s.hero = true
		recalc_morale(s)
	# Beta T4 (Titan): at start of combat 1 creature flees from every other tier 1-3 stack
	for b in stacks.filter(func(x): return x.sp("scatterOnStart") and not probe):
		for o in stacks:
			if o != b and o.count > 0 and o.def.tier <= 3 and not o.sp("ignoreNegSpecials"):
				o.count -= 1; o.deserters += 1
				say("%s loses 1 creature fleeing from %s." % [o.name, b.name])
				if o.count <= 0:
					eliminated(o)

func end_pre_combat() -> void:
	pre_combat = false
	for sd in sides:
		if sd.hs != null:
			sd.hs.freeCast = 0
	start_round()

# ------------------------------------------------------------------ queries
func say(t: String, cls: String = "") -> void:
	log.append({"r": round_n, "t": t, "cls": cls})

func stack(id) -> Stk:
	if id == null:
		return null
	for s in stacks:
		if s.id == id:
			return s
	return null

func stacks_of(side: int) -> Array:
	return stacks.filter(func(s): return s.side == side and s.count > 0)

func enemies_of(s: Stk) -> Array:
	return stacks.filter(func(o): return o.side != s.side and o.count > 0)

func allies_of(s: Stk) -> Array:
	return stacks.filter(func(o): return o.side == s.side and o.count > 0)

func any_has(art: String) -> bool:
	for sd in sides:
		if sd.hero and Heroes.has(sd.hero, art):
			return true
	return false

func hero_skill(side: int, k: String) -> int:
	var h = sides[side].hero
	return Heroes.skill(h, k) if h else 0

func hero_stat(side: int, k: String) -> int:
	var h = sides[side].hero
	if not h:
		return 0
	var v := Heroes.stat(h, k)
	if k == "power" and fx.get("doublePower", 0):
		v *= 2
	return v

func ign(s: Stk) -> bool:
	return s.sp("ignoreNegSpecials")

func current():
	return queue[qi] if qi < queue.size() else null

func current_stack() -> Stk:
	var e = current()
	return stack(e.id) if e and e.type == "stack" else null

func assaulters(s: Stk) -> Array:
	return stacks.filter(func(o): return o.count > 0 and o.side != s.side and o.engaging.has(s.id))

func engaged_with(a: Stk, t: Stk) -> bool:
	return a.engaging.has(t.id)

func protector_of(t: Stk) -> Stk:
	var p := stack(t.guarded_by) if t.guarded_by != null else null
	return p if p and p.count > 0 else null

func is_guarded(t: Stk) -> bool:
	return protector_of(t) != null

func wall_protected(t: Stk) -> bool:
	if wall == null or t.side != 1 or wall.hp <= 0:
		return false
	var defs := stacks_of(1)
	var k := int(ceil(float(wall.hp) / C.wallPerStack))
	return defs.find(t) < k  # bottom stacks lose protection first

func eff_count(s: Stk) -> int:
	var n: int = s.count - int(s.spells.get("diminish", 0))
	if s.spells.get("halve", 0):
		n = U.jr(n / 2.0)
	return maxi(0, n)

func is_ranged(s: Stk) -> bool:
	var r: bool = s.def.ab.get("ranged", false) or fx.get("allRanged", 0) or (fx.get("defRanged", 0) and s.side == 1) or (fx.get("defHalfRanged", 0) and s.side == 1)
	if fx.get("noRanged", 0):
		r = false
	return r

func half_ranged_only(s: Stk) -> bool:
	return fx.get("defHalfRanged", 0) and s.side == 1 and not s.def.ab.get("ranged", false) and not fx.get("allRanged", 0) and not fx.get("defRanged", 0)

func is_cavalry(s: Stk) -> bool:
	var c: bool = s.def.ab.get("cavalry", false) or fx.get("allCavalry", 0) or (fx.get("attCavalry", 0) and s.side == 0)
	if fx.get("noCavalry", 0):
		c = false
	if fx.get("attNoCavR1", 0) and s.side == 0 and round_n <= 1:
		c = false
	return c

func can_fly(s: Stk) -> bool:
	return s.def.ab.get("fly", false)

func slow_level(s: Stk) -> int:
	var v: int = int(s.def.ab.get("slow", 0)) + s.extra_slow + int(fx.get("slowMod", 0)) - int(s.spells.get("quicken", 0))
	if fx.get("slowModNonRanged", 0) and not is_ranged(s):
		v += fx.slowModNonRanged
	if fx.get("rangedSlow", 0) and is_ranged(s):
		v += maxi(1, fx.rangedSlow)
	var h = sides[s.side].hero
	if h and Heroes.has(h, "horseshoe"):
		v -= 1
	if h and s.def.mounted and Heroes.skill(h, "horsemanship") >= 3:
		v -= 1
	return maxi(0, v)

func health(s: Stk) -> int:
	var h = sides[s.side].hero
	return maxi(1, int(s.def.hp) + s.extra_hp + (1 if h and Heroes.has(h, "heart") else 0))

## health without the hero's heart; 0 health still counts as 1 (only gaining health
## starts from the true 0, via extra_hp)
## effective numbers shown in brackets next to the base stats (HoMM style)
func eff_stats(s: Stk) -> Dictionary:
	return {"hp": health(s), "mor": s.morale_val, "dmg": dmg_triple(s), "ini": initiative(s), "att": attack(s), "def": defence(s)}

## effective stats of armies before any fighting. `o` is a Battle.new options dict
## (a missing second side gets a token enemy). Returns, per side, one eff dict per
## input stack, in order.
static func probe_stats(o: Dictionary) -> Array:
	var opts := o.duplicate()
	opts.probe = true
	opts.seed = 1
	var sides_in: Array = opts.sides.duplicate()
	while sides_in.size() < 2:
		sides_in.append({"name": "-", "stacks": [{"key": Units.key("alpha", 1, 0, ""), "count": 1}]})
	opts.sides = sides_in
	var b := Battle.new(opts)
	var out := []
	for i in 2:
		var st := b.stacks.filter(func(x): return x.side == i)
		var n: int = sides_in[i].stacks.size()
		out.append(st.slice(0, n).map(func(x): return b.eff_stats(x)))
	return out

## How much damage one creature soaks before the stack starts losing creatures.
## Doc rule: value − 1 (count × (health − 1)). The "full threshold" test option in
## Options → Battle uses the whole value (count × health) for both health and morale;
## deserters then also shed a full health of damage.
static var _full = null
static func full_threshold() -> bool:
	if _full == null:
		var cf := ConfigFile.new()
		_full = cf.get_value("rules", "full_threshold", false) if cf.load("user://settings.cfg") == OK else false
	return _full

static func set_full_threshold(on: bool) -> void:
	_full = on
	var cf := ConfigFile.new()
	cf.load("user://settings.cfg")
	cf.set_value("rules", "full_threshold", on)
	cf.save("user://settings.cfg")

static func cap(v: int) -> int:
	return v if full_threshold() else v - 1

func raw_health(s: Stk) -> int:
	return maxi(1, int(s.def.hp) + s.extra_hp)

func count_bonus(s: Stk, per: String) -> float:
	if per == "ad" and any_has("banner"):
		return 0.0
	if per == "mor" and any_has("stoic"):
		return 0.0
	var b: float = C.perUnitMoraleBonus if per == "mor" else C.perUnitAttDefBonus
	return b * eff_count(s) * (2 if s.sp("doubleBonuses") else 1)

func attack(s: Stk) -> int:
	if fx.get("attDef10", 0) or s.spells.get("equalize", 0):
		return 10
	var h = sides[s.side].hero
	var v: float = float(s.def.att) * (1.0 + count_bonus(s, "ad")) + s.def.flatAtt + s.adv * (2 if s.sp("doubleBonuses") else 1)
	if h:
		v += Heroes.stat(h, "attack")
	if s.hero:
		v += C.heroUnitBonus.att
	if h and s.def.mounted:
		v += [0, 1, 2, 2][Heroes.skill(h, "horsemanship")]
	return U.jr(v)

func defence(s: Stk) -> int:
	if fx.get("attDef10", 0) or s.spells.get("equalize", 0):
		return 10
	var h = sides[s.side].hero
	var v: float = float(s.def.def) * (1.0 + count_bonus(s, "ad")) + s.def.flatDef + s.adv * (2 if s.sp("doubleBonuses") else 1)
	if h:
		v += Heroes.stat(h, "defence")
	if s.hero:
		v += C.heroUnitBonus.def
	if h and s.def.mounted:
		v += [0, 1, 2, 2][Heroes.skill(h, "horsemanship")]
	return U.jr(v)

func recalc_morale(s: Stk) -> int:
	var h = sides[s.side].hero
	var v: float = float(s.def.mor) * (1.0 + count_bonus(s, "mor")) + s.def.flatMor + s.extra_mor + int(s.spells.get("valor", 0))
	if s.hero:
		v += C.heroUnitBonus.mor
	if h:
		v += [0, 1, 2, 4][Heroes.skill(h, "inspiration")]
	for o in allies_of(s):
		if o != s and o.sp("moraleAura", 0):
			v += o.def.sp.moraleAura
	if fx.get("defMoraleX", 0) and s.side == 1:
		v *= fx.defMoraleX
	if fx.get("moraleHalf", 0):
		v *= 0.5
	var sd: BSide = sides[s.side]
	if sd.hero and sd.trainless:
		v -= 1
	s.morale_val = maxi(0, U.jr(v))
	return s.morale_val

func dmg_triple(s: Stk, target = null) -> Array:
	var add: int = int(s.spells.get("sharpen", 0)) - int(s.spells.get("blunt", 0)) + (C.heroUnitBonus.dmg if s.hero else 0)
	if target != null and target.sp("dmgAuraMinus1") and not ign(s):
		add -= 1
	var out := []
	for x in s.def.dmg:
		out.append(maxf(0.0, float(x) + add))
	return out

func initiative(s: Stk) -> int:
	var v: int = int(s.def.ini) + int(s.spells.get("haste", 0))
	if fx.get("attackerInit", 0) and s.side == 0:
		v += fx.attackerInit
	return v

func hero_init(side: int) -> float:
	var h = sides[side].hero
	var hs = sides[side].hs
	var v: float = (Heroes.stat(h, "initiative") - hs.pips + hs.haste * 3) / 3.0
	if fx.get("attackerInit", 0) and side == 0:
		v += fx.attackerInit
	return v

func always_hero_n(side: int) -> int:
	return [C.heroUnitAlways, 3, 6, 12][hero_skill(side, "heroics")]

func hero_frac(side: int) -> float:
	return 0.5 if hero_skill(side, "heroics") else C.heroUnitFraction

func strength(side: int) -> float:
	var t := 0.0
	for s in stacks_of(side):
		t += s.count * Units.value(s.def) * (1.0 + maxf(1.0, s.def.hp) / 4.0)
	return t

# ------------------------------------------------------------------ rounds & turns
func start_round() -> void:
	if over:
		return
	round_n += 1
	attacked_last_round = attacked_this_round.duplicate()
	if round_n == 1:
		attacked_last_round = [true, true]
	attacked_this_round = [false, false]
	damage_this_round = false
	say("— Round %d —" % round_n, "round")
	if fx.get("physPerRound", 0) or fx.get("moraleDmgPerRound", 0):
		for s in stacks.filter(func(x): return x.count > 0):
			var t: int = mini(4, int(s.def.tier))
			deal_damage(s, U.jr(float(fx.get("physPerRound", 0)) / t), U.jr(float(fx.get("moraleDmgPerRound", 0)) / t), {"kind": "terrain"})
		if check_end():
			return
	for sd in sides:
		if sd.ai and sd.neutral and C.monsterFlee and round_n >= 2 and ai_should_flee(sd.idx):
			say("%s flee the field!" % sd.name, "big")
			over = {"winner": 1 - sd.idx, "reason": "fled", "fled": sd.idx}
			return
	for sd in sides:
		if sd.hs != null:
			sd.hs.active = false
			sd.hs.castsLeft = Heroes.casts_per_round(sd.hero)
	var q := []
	for i in stacks.size():
		var s: Stk = stacks[i]
		if s.count <= 0:
			continue
		s.waited = false; s.extra_turn_used = false
		q.append({"type": "stack", "id": s.id, "side": s.side, "init": float(initiative(s)), "tie": 1 if s.sp("firstOnTie") else 0, "pos": i})
		if s.sp("twoTurns"):
			q.append({"type": "stack", "id": s.id, "side": s.side, "init": initiative(s) - 0.5, "tie": 0, "pos": i, "second": true})
	for sd in sides:
		if sd.hs != null and not sd.hs.gone:
			q.append({"type": "hero", "side": sd.idx, "init": hero_init(sd.idx), "tie": 2, "pos": -1})
	q.sort_custom(_queue_before)
	queue = q; qi = 0
	for sd in sides:
		if sd.hs != null and not sd.hs.gone and not (q[0].type == "hero" and q[0].side == sd.idx):
			sd.st.notFirst += 1
	begin_turn()

## JS comparator (b.init-a.init) || (a.side-b.side) || (b.tie-a.tie) || (a.pos-b.pos) as a strict order
func _queue_before(a, b) -> bool:
	if a.init != b.init: return a.init > b.init
	if a.side != b.side: return a.side < b.side
	if a.tie != b.tie: return a.tie > b.tie
	if a.pos != b.pos: return a.pos < b.pos
	return a.get("second", false) == false and b.get("second", false) == true

func begin_turn() -> void:
	if over:
		return
	while qi < queue.size():
		var e0 = queue[qi]
		if e0.type == "stack":
			var s0 := stack(e0.id)
			if s0 and s0.count > 0:
				break
		if e0.type == "hero" and sides[e0.side].hs != null and not sides[e0.side].hs.gone:
			break
		qi += 1
	if qi >= queue.size():
		end_round()
		return
	var e = queue[qi]
	turn_acted = false
	if e.type == "hero":
		sides[e.side].hs.active = true
		return
	var s := stack(e.id)
	if e.get("second", false):
		say("%s acts again." % s.name)
	if e.get("resumed", false):
		return
	s.fallen_back = false; s.retaliating = false
	var prior := s.mor
	if s.sp("purgeMoraleOnTurn"):
		s.mor = mini(0, s.mor)
	elif prior > 0:
		s.mor = maxi(0, prior - s.morale_val)
	elif s.sp("negMoraleOverflow"):
		s.mor = prior - U.jr(s.morale_val / 2.0)
	if s.sp("regenPerUnit") and s.phys > 0:
		s.phys = maxi(0, s.phys - s.count)
	if s.sp("moralePerTurn", 0):
		s.extra_mor += s.def.sp.moralePerTurn
	if s.sp("advPerTurn"):
		s.adv += 1
	recalc_morale(s)

func end_turn(action_kind: String) -> void:
	var e = current()
	if check_end():
		return
	if e and e.type == "stack":
		var s := stack(e.id)
		if s and s.count > 0 and s.sp("extraTurnNonAttack") and action_kind != "attack" and action_kind != "wait" and not s.extra_turn_used:
			s.extra_turn_used = true
			var entry := {"type": "stack", "id": s.id, "side": s.side, "init": 2.0, "tie": 0, "pos": 99, "second": true}
			var at := -1
			for i in range(qi + 1, queue.size()):
				if queue[i].init < 2:
					at = i; break
			if at < 0:
				at = queue.size()
			if float(e.get("init", 0)) <= 2:
				at = qi + 1
			queue.insert(at, entry)
	qi += 1
	begin_turn()

func end_round() -> void:
	for sd in sides:
		if sd.hero:
			sd.st.rounds += 1
	if not damage_this_round:
		say("No damage was dealt this round — the battle ends.", "big")
		over = {"winner": null, "reason": "stalemate"}
		return
	if round_n >= C.roundCap:
		over = {"winner": null, "reason": "exhaustion"}
		say("Both armies are exhausted.", "big")
		return
	start_round()

func check_end() -> bool:
	if over:
		return true
	var a := stacks_of(0).size()
	var d := stacks_of(1).size()
	if a == 0 or d == 0:
		var w = null if (a == 0 and d == 0) else (0 if a else 1)
		over = {"winner": w, "reason": "destroyed"}
		say("Both armies are gone." if w == null else "%s win!" % sides[w].name, "big")
		return true
	return false

# ------------------------------------------------------------------ damage
func roll_damage(a: Stk, t, opts: Dictionary = {}) -> Dictionary:
	var n := eff_count(a)
	var X: int = maxi(C.minDice, U.jr(n))
	var r := rng.rint(1, X)
	var crit: int = int(a.sp("crit", 0)) if (a.sp("crit", 0) and not (t.sp("ignoreNegSpecials") if t is Stk else false)) else 0
	var tri := dmg_triple(a, t if t is Stk else null)
	var per: float
	var how: String
	if a.spells.get("fortune", 0) and not a.spells.get("misfortune", 0):
		per = tri[2]; how = "max"
	elif a.spells.get("misfortune", 0) and not a.spells.get("fortune", 0):
		per = tri[0]; how = "min"
	elif opts.get("average", false):
		per = tri[1]; how = "avg"
	# crit adds to the roll itself: a boosted 1 is no longer a natural 1, so crit units never roll minimum
	elif r + crit >= X:
		per = tri[2]; how = "max" if r == X else "crit"
	elif r + crit == 1:
		per = tri[0]; how = "min"
	else:
		per = tri[1]; how = "avg"
	return {"per": per, "how": how, "roll": r, "X": X}

func att_mult(A: int, Dv: int) -> float:
	if A > Dv:
		return minf(1.0 + C.attCap, 1.0 + C.attPerPoint * (A - Dv))
	return maxf(1.0 - C.defCap, 1.0 - C.defPerPoint * (Dv - A))

func hit_numbers(a: Stk, t: Stk, opts: Dictionary = {}) -> Dictionary:
	var roll := roll_damage(a, t, opts)
	var n := eff_count(a)
	var total: float = roll.per * n
	if opts.get("half", false):
		total *= 0.5
	var A := attack(a)
	var Dv := defence(t)
	var mult := att_mult(A, Dv)
	var tot := U.jr(total * mult)
	var phys: int
	var mor: int
	if a.sp("allPhysical"):
		phys = tot; mor = 0
	elif a.sp("split5050"):
		mor = U.jr(tot / 2.0); phys = tot - mor
	else:
		mor = U.jr(tot * C.moraleShare); phys = tot - mor
	if a.sp("extraMoraleDmg") and not ign(t):
		mor += U.jr(a.morale_val * (n if C.beta2PerCreature else 1) * mult)
	if t.sp("extraDamageTaken") and not (t.sp("extraDamageOnlyIfAttLE") and A > Dv):
		phys += 1
	return {"phys": phys, "mor": mor, "total": tot, "mult": mult, "A": A, "D": Dv, "roll": roll}

func deal_damage(t: Stk, phys: int, mor: int, ctx: Dictionary = {}) -> Dictionary:
	if t.count <= 0:
		return {"killed": 0, "deserted": 0, "phys": 0, "mor": 0}
	if fx.get("swapDamage", 0) and ctx.get("kind", "") != "spellPure":
		var x := phys; phys = mor; mor = x
	if fx.get("noPhysical", 0) and phys > 0:
		phys = 0
	if t.sp("lastStandConvert") and phys > 0:
		if simulate_phys(t, phys) >= t.count:
			mor += phys; phys = 0
	if phys > 0 or mor > 0:
		damage_this_round = true
	var courage: int = sides[t.side].courage
	var deserted := 0
	var killed := 0
	if mor > 0:
		var mv := t.morale_val  # "calculate morale before damage"
		t.mor += mor
		var h := health(t)
		while t.count > 0 and t.mor > t.count * cap(mv):
			t.count -= 1; deserted += 1; t.deserters += 1
			t.mor -= maxi(1, 2 * mv + courage)
			if t.phys > 0:
				t.phys = maxi(0, t.phys - cap(h))
		if deserted:
			t.mor = maxi(0, t.mor)
	if phys != 0:
		t.phys += phys
		var h := health(t)
		var extra: int = courage if t.sp("courageHealth") else 0
		while t.count > 0 and t.phys > t.count * cap(h):
			t.count -= 1; killed += 1; t.dead += 1
			t.phys -= maxi(1, 2 * h + extra)
		if killed:
			t.phys = maxi(0, t.phys)
	if fx.get("desertersDie", 0) and deserted:
		t.deserters -= deserted; t.dead += deserted
	t.last_loss_dead = killed > 0
	if killed or deserted:
		on_losses(t, killed, deserted, ctx)
	return {"killed": killed, "deserted": deserted, "phys": phys, "mor": mor}

func simulate_phys(t: Stk, phys: float) -> int:
	var p: float = t.phys + phys
	var c := t.count
	var k := 0
	var h := health(t)
	var extra: int = sides[t.side].courage if t.sp("courageHealth") else 0
	while c > 0 and p > c * cap(h):
		c -= 1; k += 1; p -= maxi(1, 2 * h + extra)
	return k

func on_losses(t: Stk, killed: int, deserted: int, ctx: Dictionary) -> void:
	var src = ctx.get("source", null)
	var tier: int = mini(4, int(t.def.tier))
	var enemy_src: bool = (src != null and src.side != t.side) or (ctx.get("kind", "") == "spell" and ctx.get("spellSide", -1) != t.side)
	if enemy_src:
		var oside := 1 - t.side
		sides[oside].st.killTier += killed * tier
		sides[oside].st.killsByTier[tier] += killed
		sides[t.side].st.lostTier += killed * tier
		sides[t.side].st.desertedByEnemy += deserted
	var lost := killed + deserted
	if t.sp("lossMoraleHeal", 0):
		t.mor = maxi(0, t.mor - int(t.def.sp.lossMoraleHeal) * lost)
	if t.sp("lossGainMorale"):
		t.extra_mor += lost
	# Delta T1 necromancy
	if killed > 0:
		for o in stacks:
			if o == t or o.count <= 0:
				continue
			var g := 0
			if o.sp("necroAny"):
				g += killed
			elif o.sp("necroPhys", "") == "base" and tier >= mini(4, int(o.def.tier)):
				g += 1
			elif o.sp("necroPhys", "") == "melee":
				g += int(floor(float(tier) / mini(4, int(o.def.tier))))
			if g > 0:
				o.count += g; o.gained += g
				say("%s gains %d creature%s." % [o.name, g, "s" if g > 1 else ""], "good")
	# killer effects
	if src != null and src.count > 0 and src.side != t.side and killed > 0:
		if src.sp("killMoraleHeal"):
			src.mor = maxi(0, src.mor - tier * killed)
		if src.sp("bigKillMorale") and tier >= 3:
			src.extra_mor += killed
		var g = src.sp("gainHealthOnKill", "")
		if g:
			var th := raw_health(t)
			var mh := raw_health(src)
			if (g == "gt" and th > mh) or (g == "ge" and th >= mh):
				src.extra_hp += 1
				say("%s grows stronger (+1 health)." % src.name, "good")
		if src.sp("killRecoverDeserter"):
			var r := mini(killed, src.deserters)
			if r:
				src.deserters -= r; src.count += r
		recalc_morale(src)
	var bits := []
	if killed:
		bits.append("%d killed" % killed)
	if deserted:
		bits.append("%d deserted" % deserted)
	say("%s: %s." % [t.name, ", ".join(bits)], "loss")
	if t.count <= 0:
		eliminated(t)
		return
	recalc_morale(t)
	check_hero_unit(t)

func check_hero_unit(s: Stk) -> void:
	if s.hero or s.count <= 0:
		return
	if s.count <= s.start * hero_frac(s.side) or s.count <= always_hero_n(s.side):
		s.hero = true
		sides[s.side].courage += 1
		recalc_morale(s)
		s.mor = maxi(0, s.mor - 2 * s.morale_val)  # "a unit rallies when it becomes a hero"
		say("%s become HEROES! (+1 courage, rallies)" % s.name, "hero")

func eliminated(s: Stk) -> void:
	for o in stacks:
		o.engaging = o.engaging.filter(func(id): return id != s.id)
		if o.guarded_by == s.id:
			o.guarded_by = null
		if o.guarding == s.id:
			o.guarding = null
	s.engaging = []; s.guarding = null; s.guarded_by = null
	say("%s are gone from the field." % s.name, "big")
	var sd: BSide = sides[s.side]
	if s.hero:
		sd.courage -= 1
	for o in allies_of(s):
		recalc_morale(o)
	if s.def.tier >= 4 and not s.def.mounted and sd.hs != null and not sd.hs.gone:
		sd.hs.gone = "dead" if s.last_loss_dead else "fled"
		say("%s %s the %s!" % [sd.hero.name, "falls with" if sd.hs.gone == "dead" else "flees with", s.name], "big")

# ------------------------------------------------------------------ legality
func turn_stack() -> Stk:
	return null if (over or pre_combat) else current_stack()

func check_attack(a: Stk, t: Stk):
	if a == null or t == null or t.count <= 0 or t.side == a.side:
		return "Invalid target"
	if t.fallen_back:
		return "Fallen back (only guard may target it)"
	var ass := assaulters(a)
	if ass.size() and not ass.has(t):
		return "Must target an assaulter"
	var eng := engaged_with(a, t)
	if round_n <= slow_level(a) and not eng:
		return "Slow: can't attack in round %d unless engaged with target" % round_n
	if wall_protected(t) and not eng:
		return "Behind the walls"
	var t_engaged: bool = t.engaging.size() > 0 or assaulters(t).size() > 0
	if is_ranged(t) and round_n == 1 and not eng and not t_engaged:
		if can_fly(t):
			if not is_ranged(a):
				return "Flying archers cannot be attacked in round 1 except by ranged units"
		elif not is_cavalry(a):
			return "Ranged units cannot be attacked in round 1 (except by cavalry)"
	var p := protector_of(t)
	if p and not eng:
		var ranged_ok: bool = is_ranged(a) and not p.sp("guardVsRanged")
		if not (ranged_ok or can_fly(a) or a.def.ab.get("teleport", false)):
			return "Guarded by %s" % p.name
	if is_guarded(a) and not eng and not is_ranged(a):
		return "Guarded units may only attack units they are engaged with"
	return null

func check_engage(a: Stk, t: Stk):
	if a == null or t == null or t.count <= 0 or t.side == a.side:
		return "Invalid target"
	if t.fallen_back:
		return "Fallen back"
	var ass := assaulters(a)
	if ass.size() and not ass.has(t):
		return "Must target an assaulter"
	if engaged_with(a, t):
		return "Already engaged"
	if is_cavalry(t) and not is_cavalry(a):
		return "Only cavalry can engage cavalry"
	if wall_protected(t):
		return "Behind the walls"
	if is_ranged(t) and round_n == 1 and not is_cavalry(a):
		return "Ranged units cannot be engaged in round 1 (except by cavalry)"
	var p := protector_of(t)
	if p:
		var pike := hero_skill(p.side, "pikemanship") >= 1
		if not (is_cavalry(a) and not is_cavalry(p) and not pike):
			return "Guarded by %s" % p.name
	return null

func check_guard(a: Stk, t: Stk):
	if a == null or t == null or t == a or t.count <= 0 or t.side != a.side:
		return "Pick another friendly stack"
	if assaulters(a).size():
		return "Cannot guard while under assault"
	var p := protector_of(t)
	if p and p != a:
		return "Already guarded by %s" % p.name
	if a.guarding == t.id:
		return "Already guarding it"
	return null

func _pike_block(st: Stk) -> bool:
	return st != null and st.adv > 0 and hero_skill(st.side, "pikemanship") >= 2

func deny_options(a: Stk, t: Stk) -> Array:
	var out := []
	if t == null or t.count <= 0 or t.side == a.side or t.fallen_back:
		return out
	for id in t.engaging:
		var x := stack(id)
		if x:
			out.append({"type": "engage", "id": id, "label": "Break its engagement on %s" % x.name})
	if t.guarding != null and stack(t.guarding) and not _pike_block(t):
		out.append({"type": "guard", "sub": "out", "label": "End its guard over %s" % stack(t.guarding).name})
	if t.guarded_by != null and protector_of(t) and not _pike_block(protector_of(t)):
		out.append({"type": "guard", "sub": "in", "label": "End %s's guard over it" % protector_of(t).name})
	if t.adv > 0:
		out.append({"type": "adv", "label": ("Strip up to %d advantages" % (a.adv + 1)) if a.sp("denyMulti") else "Strip one advantage"})
	if a.adv > 0:
		for id in t.spells:
			if t.spells[id] > 0:
				out.append({"type": "spell", "id": id, "label": "Cancel one level of %s (spends 1 advantage)" % D.SPELLS[id].name})
	return out

func check_deny(a: Stk, t: Stk):
	if a == null or t == null or t.count <= 0 or t.side == a.side:
		return "Invalid target"
	if t.fallen_back:
		return "Fallen back"
	var ass := assaulters(a)
	if ass.size() and not ass.has(t):
		return "Must target an assaulter"
	if deny_options(a, t).is_empty():
		return "Nothing to deny"
	return null

func check_fallback(a: Stk):
	var others := allies_of(a).filter(func(o): return o != a and not o.fallen_back)
	if others.is_empty():
		return "Cannot fall back as the last unit standing"
	return null

func check_rally(a: Stk, t: Stk):
	if t == null or t.count <= 0:
		return "Invalid target"
	if t.side != a.side:
		if a.sp("rallyEnemy"):
			return "Fallen back" if t.fallen_back else null
		return "Rally targets friendly units"
	if t.fallen_back and t != a:
		return "Fallen back (only guard may target it)"
	return null

func can_wait(a: Stk) -> bool:
	return hero_skill(a.side, "tactics") >= 1 and not a.waited and qi < queue.size() - 1

# ------------------------------------------------------------------ actions
## target: stack id, "wall", or null. Returns an error string or null.
func act(action: String, target_id = null, opt = null):
	var a := turn_stack()
	if a == null:
		return "Not a unit turn"
	var t: Stk = stack(target_id) if (target_id != null and typeof(target_id) == TYPE_INT) else null
	var err = null
	match action:
		"attack": err = check_wall_attack(a) if (typeof(target_id) == TYPE_STRING and target_id == "wall") else check_attack(a, t)
		"engage": err = check_engage(a, t)
		"guard": err = check_guard(a, t)
		"deny": err = check_deny(a, t)
		"fallback": err = check_fallback(a)
		"rally": err = check_rally(a, t)
		"seek", "retaliate": err = null
		"wait": err = null if can_wait(a) else "Cannot wait"
		_: err = "Unknown action"
	if err != null:
		return err
	turn_acted = true
	match action:
		"attack":
			if typeof(target_id) == TYPE_STRING and target_id == "wall":
				attack_wall(a)
			else:
				do_attack(a, t)
		"engage":
			a.engaging.append(t.id); unguard(a); unprotect(a)
			if not fx.get("keepAdv", 0): a.adv = 0
			say("%s engage %s." % [a.name, t.name])
		"guard":
			unprotect(a); unguard(a)
			if not fx.get("keepAdv", 0): a.adv = 0
			a.engaging = []
			a.guarding = t.id; t.guarded_by = a.id
			if a.sp("advAfterGuard"): a.adv += 1
			if hero_skill(a.side, "pikemanship") >= 3: a.adv += 1
			say("%s guard %s." % [a.name, t.name])
		"deny":
			var opts := deny_options(a, t)
			var o: Dictionary = opts[opt] if (opt != null and int(opt) < opts.size()) else opts[0]
			var spent := 1
			if o.type == "engage":
				t.engaging = t.engaging.filter(func(id): return id != o.id)
			elif o.type == "guard":
				if o.get("sub", "") == "out":
					var g := stack(t.guarding)
					if g: g.guarded_by = null
					t.guarding = null
				else:
					var p := protector_of(t)
					if p: p.guarding = null
					t.guarded_by = null
			elif o.type == "adv":
				var n: int = mini(t.adv, a.adv + 1) if a.sp("denyMulti") else 1
				t.adv -= n
				spent = n if a.sp("denyMulti") else 1
			elif o.type == "spell":
				t.spells[o.id] -= 1
				if t.spells[o.id] <= 0: t.spells.erase(o.id)
				recalc_morale(t)
			unprotect(a); unguard(a)
			if not fx.get("keepAdv", 0): a.adv = maxi(0, a.adv - spent)
			a.engaging = a.engaging.filter(func(id): return id == t.id)
			say("%s deny %s: %s." % [a.name, t.name, str(o.label).to_lower()])
		"fallback":
			for o in stacks:
				o.engaging = o.engaging.filter(func(id): return id != a.id)
			a.engaging = []; unguard(a); unprotect(a); a.adv = 0; a.retaliating = false; a.fallen_back = true
			if a.sp("fallbackRecover") and a.deserters > 0:
				a.deserters -= 1; a.count += 1
				say("%s recover a deserter." % a.name, "good")
			recalc_morale(a)
			say("%s fall back." % a.name)
		"seek":
			a.adv += 1
			say("%s seek advantage (%d)." % [a.name, a.adv])
		"retaliate":
			a.retaliating = true
			say("%s ready to retaliate." % a.name)
		"rally":
			do_rally(a, t)
		"wait":
			a.waited = true
			var e = queue[qi]
			queue.remove_at(qi)
			e["resumed"] = true
			queue.append(e)
			say("%s wait." % a.name)
			begin_turn()
			return null
	end_turn(action)
	return null

func unguard(a: Stk) -> void:
	var p := protector_of(a)
	if p: p.guarding = null
	a.guarded_by = null

func unprotect(a: Stk) -> void:
	if a.guarding != null:
		var g := stack(a.guarding)
		if g: g.guarded_by = null
		a.guarding = null

func check_wall_attack(a: Stk):
	if wall == null or wall.hp <= 0 or a.side != 0:
		return "No wall"
	if assaulters(a).size():
		return "Must target an assaulter"
	if round_n <= slow_level(a):
		return "Slow"
	return null

func attack_wall(a: Stk) -> void:
	var roll := roll_damage(a, null)
	var A := attack(a)
	var mult := att_mult(A, 10)
	var dmg := U.jr(roll.per * eff_count(a) * mult)
	wall.hp = maxi(0, wall.hp - dmg)
	damage_this_round = true; attacked_this_round[a.side] = true
	say("%s batter the walls for %d (%d left)." % [a.name, dmg, wall.hp], "dmg")

func strike(a: Stk, t: Stk, opts: Dictionary = {}):
	if a.count <= 0 or t.count <= 0:
		return null
	var n := hit_numbers(a, t, {"half": opts.get("half", false)})
	var what := "retaliate against" if opts.get("ret", false) else "hit"
	var pct := U.jr((n.mult - 1.0) * 100.0)
	say("%s %s %s: %d dmg (%s roll %d/%d, %s%d%%) → %d morale, %d health." % [a.name, what, t.name, n.phys + n.mor, n.roll.how, n.roll.roll, n.roll.X, "+" if n.mult >= 1 else "", pct, n.mor, n.phys], "dmg")
	if n.roll.how == "max" or n.roll.how == "crit":
		events.append({"type": "crit", "side": a.side, "id": a.id})
	var res := deal_damage(t, n.phys, n.mor, {"source": a, "kind": "attack"})
	last_attack.append({"a": a.id, "t": t.id, "phys": res.phys, "mor": res.mor, "killed": res.killed, "deserted": res.deserted,
		"ret": opts.get("ret", false), "crit": n.roll.how == "max" or n.roll.how == "crit"})
	if a.sp("lifesteal") and a.count > 0 and n.phys > 0:
		a.phys = maxi(mini(a.phys, 0), a.phys - n.phys)
	if t.sp("thorns") and t.count > 0 and not opts.get("ret", false) and not ign(a):
		var x := t.count
		var xm := U.jr(x * C.moraleShare)
		deal_damage(a, x - xm, xm, {"source": t, "kind": "attack"})
		say("%s take %d thorn damage from %s." % [a.name, x, t.name], "dmg")
	return res

func do_attack(a: Stk, t: Stk) -> void:
	last_attack = []
	var engaged := engaged_with(a, t) or engaged_with(t, a)
	var under_assault := assaulters(a).size() > 0
	var ranged := is_ranged(a)
	var half: bool = ranged and half_ranged_only(a) and not engaged
	attacked_this_round[a.side] = true
	if a.sp("fleeOnAttack") and not ign(t) and t.count > 0 and t.def.tier <= 3:
		t.count -= 1; t.deserters += 1
		say("1 of %s flees before %s!" % [t.name, a.name], "loss")
		if t.count <= 0:
			eliminated(t)
			return
	var can_ret: bool = (t.retaliating or t.sp("alwaysRetaliate")) and not (ranged and not is_ranged(t) and not engaged)
	if can_ret and t.sp("firstStrikeRetaliate"):
		strike(t, a, {"ret": true})
		strike(a, t, {"half": half})
	else:
		strike(a, t, {"half": half})
		if can_ret:
			strike(t, a, {"ret": true})
	if a.sp("attackAllEngaged"):
		for id in a.engaging.duplicate():
			var e := stack(id)
			if e and e != t and e.count > 0:
				strike(a, e)
	var ce = t.sp("counterEngage", "")
	if t.count > 0 and ce and a.count > 0 and (ce == "any" or not ranged) and not t.engaging.has(a.id):
		t.engaging.append(a.id)
		say("%s engage %s in return." % [t.name, a.name])
	if a.count <= 0:
		return
	if not engaged and not (ranged and not under_assault):
		unprotect(a); unguard(a)
		if not a.sp("keepAdvOnAttack") and not fx.get("keepAdv", 0):
			a.adv = 0
		a.engaging = []
	if a.sp("engageAfterAttack") and t.count > 0 and not a.engaging.has(t.id):
		a.engaging.append(t.id)
		say("%s engage %s." % [a.name, t.name])

func do_rally(a: Stk, t: Stk) -> void:
	if t.side != a.side:
		var amt0 := 2 * a.morale_val
		say("%s terrify %s (%d morale damage)." % [a.name, t.name, amt0], "dmg")
		deal_damage(t, 0, amt0, {"source": a, "kind": "attack"})
		attacked_this_round[a.side] = true
		return
	var amt := U.jr(2 * a.morale_val * (1.5 if a.sp("rallyBoost") else 1.0))
	if a.sp("rallyConvert"):
		var p := mini(maxi(t.phys, 0), amt)
		t.phys -= p; t.mor += 2 * p; amt -= p
		if p:
			say("%s convert %d physical damage on %s into %d morale damage." % [a.name, p, t.name, 2 * p])
	if t.mor <= 0 and t.sp("negMoraleOverflow"):
		t.mor -= U.jr(amt / 2.0)
	else:
		t.mor = maxi(0, t.mor - amt)
	if a.sp("rallyHealsPhys") and t.phys > 0:
		t.phys = maxi(0, t.phys - a.count)
	recalc_morale(t)
	say("%s rally %s (−%d morale damage)." % [a.name, "themselves" if t == a else t.name, amt], "good")

# ------------------------------------------------------------------ commander
func hero_can_act(side: int) -> bool:
	var sd: BSide = sides[side]
	if over or sd.hs == null or sd.hs.gone:
		return false
	if pre_combat:
		return sd.hs.freeCast > 0
	if not sd.hs.active or sd.hs.castsLeft <= 0:
		return false
	var e = current()
	if e == null:
		return false
	if e.type == "hero":
		return e.side == side
	return e.side == side and not turn_acted

func hero_turn_now(side: int) -> bool:
	var e = current()
	return not over and not pre_combat and e != null and e.type == "hero" and e.side == side

func spell_uses_left(side: int) -> Dictionary:
	var hs = sides[side].hs
	var out := {}
	if hs == null:
		return out
	for i in hs.equipped.size():
		var id: String = hs.equipped[i]
		out[id] = out.get(id, 0) + hs.uses[i]
	return out

func spell_max_level(side: int, id: String) -> float:
	var sp: Dictionary = D.SPELLS[id]
	var extra: float = [0.0, 1.0, 2.0, INF][hero_skill(side, "layering")]
	var st = sp.get("stack", false)
	if typeof(st) == TYPE_BOOL and st == true:
		return INF
	if typeof(st) == TYPE_STRING and st == "copies":
		return sides[side].hs.equipped.count(id) + extra
	return 1.0 + extra

func spell_power_mult(side: int, id: String) -> float:
	var h = sides[side].hero
	var p: int = hero_stat(side, "power") + (int(h.spellPower.get(id, 0)) if h else 0)
	var ev: float = [0.0, 0.10, 0.25, 0.50][hero_skill(side, "evocation")]
	return (1.0 + C.spellPowerPct * p) * (1.0 + ev * maxi(0, round_n - 1))

func _hero_target(t_id) -> int:
	if typeof(t_id) == TYPE_STRING and (t_id == "hero0" or t_id == "hero1"):
		return int(t_id.substr(4))
	return -1

func check_cast(side: int, id: String, t_id, t2_id = null):
	if not hero_can_act(side):
		return "Commander cannot act now"
	if spell_uses_left(side).get(id, 0) <= 0:
		return "No uses left"
	var sp: Dictionary = D.SPELLS[id]
	if sp.target == "stackOrHero" and _hero_target(t_id) >= 0:
		return null
	var t: Stk = stack(t_id) if typeof(t_id) == TYPE_INT else null
	if t == null or t.count <= 0:
		return "Pick a target"
	if sp.target == "pair":
		var t2: Stk = stack(t2_id) if typeof(t2_id) == TYPE_INT else null
		if t2 == null or t2.count <= 0 or t2 == t:
			return "Pick a second target"
	if not sp.get("instant", false):
		if float(t.spells.get(id, 0)) >= spell_max_level(side, id):
			return "Cannot stack further"
	return null

func cast(side: int, id: String, t_id, t2_id = null):
	var err = check_cast(side, id, t_id, t2_id)
	if err != null:
		return err
	var sd: BSide = sides[side]
	var hs = sd.hs
	var sp: Dictionary = D.SPELLS[id]
	var h = sd.hero
	for k in hs.equipped.size():
		if hs.equipped[k] == id and hs.uses[k] > 0:
			hs.uses[k] -= 1
			break
	if pre_combat:
		hs.freeCast -= 1
	else:
		hs.castsLeft -= 1
	sd.st.spells += 1
	var pm := spell_power_mult(side, id)
	var hi := _hero_target(t_id)
	if hi >= 0:
		sides[hi].hs.haste += 1
		say("%s casts %s on %s." % [h.name, sp.name, sides[hi].hero.name], "spell")
	else:
		var t := stack(t_id)
		say("%s casts %s on %s." % [h.name, sp.name, t.name], "spell")
		match id:
			"flame":
				deal_damage(t, U.jr(sp.amount * pm), 0, {"kind": "spell", "spellSide": side})
				if t.side != side: attacked_this_round[side] = true
			"dread":
				var tot := U.jr(sp.amount * pm)
				var dm := U.jr(tot * C.moraleShare)
				deal_damage(t, tot - dm, dm, {"kind": "spell", "spellSide": side})
				if t.side != side: attacked_this_round[side] = true
			"ward":
				t.phys -= U.jr(sp.amount * pm)
			"mend":
				if t.phys > 0: t.phys = maxi(0, t.phys - U.jr(sp.amount * pm))
			"dispel":
				t.spells = {}
				recalc_morale(t)
			"transfer":
				var t2 := stack(t2_id)
				var amt := maxi(0, t.mor)
				t.mor = mini(0, t.mor)
				say("%d morale damage moves from %s to %s." % [amt, t.name, t2.name], "spell")
				deal_damage(t2, 0, amt, {"kind": "spell", "spellSide": side})
			_:
				t.spells[id] = int(t.spells.get(id, 0)) + 1
				recalc_morale(t)
	# spellthief (enemy): gains power on their copy
	var other: BSide = sides[1 - side]
	if other.hero and Heroes.skill(other.hero, "spellthief") >= 2 and (other.hero.spellbook as Array).has(id):
		other.hero.spellPower[id] = int(other.hero.spellPower.get(id, 0)) + 1
		say("%s's %s grows stronger." % [other.hero.name, sp.name], "spell")
	if not hs.ranOut:
		var all_out := true
		for u in hs.uses:
			if u > 0: all_out = false
		if all_out:
			hs.ranOut = true
			sd.st.knowledgeXP += 3 * hs.equipped.size()
	check_end()
	return null

func command_options(side: int) -> Array:
	var hs = sides[side].hs
	if hs == null:
		return []
	return [
		{"id": "recall", "label": "Recall deserter", "desc": "Spend courage = tier to return 1 deserter to a stack%s." % (" (Horn of Returning: even one that was wiped out)" if can_return_wiped(side) else " still on the field"), "need": "stack"},
		{"id": "revive", "label": "Revive fallen", "desc": "Spend spare knowledge (%d) = tier to revive 1 dead%s." % [hs.spareKnowledge, " (Horn of Returning: even in a wiped-out stack)" if can_return_wiped(side) else " in a stack still on the field"], "need": "stack"},
		{"id": "embolden", "label": "Embolden", "desc": "Spend one initiative pip: +1 advantage to a stack.", "need": "stack"},
		{"id": "steel", "label": "Steel nerves", "desc": "+1 courage.", "need": null},
	]

func command(side: int, cmd: String, t_id = null):
	if not hero_can_act(side) or pre_combat:
		return "Commander cannot act now"
	var sd: BSide = sides[side]
	var hs = sd.hs
	var h = sd.hero
	var t: Stk = stack(t_id) if typeof(t_id) == TYPE_INT else null
	var tier: int = mini(4, int(t.def.tier)) if t else 0
	match cmd:
		"recall":
			# doc: may not return a fleeing unit if the stack was wiped out (the Horn of Returning allows it)
			if t == null or t.side != side: return "Pick a friendly stack"
			if t.count <= 0 and not can_return_wiped(side): return "That stack was wiped out (needs the Horn of Returning)"
			if t.deserters <= 0: return "No deserters"
			if sd.courage < tier: return "Not enough courage"
			sd.courage -= tier; t.deserters -= 1
			_return_one(t)
			say("%s recalls a deserter to %s." % [h.name, t.name], "hero")
		"revive":
			if t == null or t.side != side: return "Pick a friendly stack"
			if t.count <= 0 and not can_return_wiped(side): return "That stack was wiped out (needs the Horn of Returning)"
			if t.dead <= 0: return "No dead to revive"
			if hs.spareKnowledge < tier: return "Not enough spare knowledge"
			hs.spareKnowledge -= tier; t.dead -= 1
			_return_one(t)
			say("%s revives one of %s." % [h.name, t.name], "hero")
		"embolden":
			if t == null or t.side != side or t.count <= 0: return "Pick a friendly stack"
			if Heroes.stat(h, "initiative") - hs.pips <= 0: return "No initiative pips left"
			hs.pips += 1; t.adv += 1
			say("%s emboldens %s (+1 advantage)." % [h.name, t.name], "hero")
		"steel":
			sd.courage += 1
			say("%s steels the army (+1 courage)." % h.name, "hero")
		_:
			return "Unknown command"
	hs.castsLeft -= 1
	return null

## Horn of Returning: recall / revive may target a wiped-out stack
func can_return_wiped(side: int) -> bool:
	var h = sides[side].hero
	return h != null and Heroes.has(h, "horn")

## one creature rejoins a stack; a wiped-out stack comes back onto the field
func _return_one(t: Stk) -> void:
	var was_gone := t.count <= 0
	t.count = maxi(0, t.count) + 1
	if was_gone:
		t.phys = 0; t.mor = 0; t.hero = false
		say("%s return to the field!" % t.name, "good")
		check_hero_unit(t)
	recalc_morale(t)

func hero_end(side: int):
	if not hero_turn_now(side):
		return "Not the commander's turn"
	end_turn("hero")
	return null

func flee(side: int):
	if over:
		return "Battle over"
	over = {"winner": 1 - side, "reason": "fled", "fled": side}
	say("%s retreat!" % sides[side].name, "big")
	return null

# ------------------------------------------------------------------ results
func summary() -> Array:
	var out := []
	for sd in sides:
		var st := []
		for s in stacks:
			if s.side != sd.idx: continue
			st.append({"uid": s.uid, "key": s.key, "name": s.name, "start": s.start, "survivors": maxi(0, s.count), "dead": s.dead, "deserters": s.deserters, "gained": s.gained})
		out.append({"side": sd.idx, "st": sd.st, "heroGone": sd.hs.gone if sd.hs != null else null, "courage": sd.courage, "stacks": st})
	return out

# ------------------------------------------------------------------ AI helpers
func ai_should_flee(side: int) -> bool:
	var opp := 1 - side
	if attacked_last_round[opp]:
		return false
	var weak := strength(side) <= 0.5 * strength(opp)
	var can_kill := false
	for a in stacks_of(side):
		for t in stacks_of(opp):
			if expected_hit(a, t).removed >= 1:
				can_kill = true
				break
	return weak or not can_kill

## average-roll hit simulation with no side effects
func expected_hit(a: Stk, t: Stk) -> Dictionary:
	# (like the prototype, the preview roll consumes one random number: state is saved after it)
	var n := hit_numbers(a, t, {"average": true})
	var save_rng := rng.get_state()
	var save_log := log.size()
	var save_dmg := damage_this_round
	var mv := t.morale_val
	var h := health(t)
	var cour: int = sides[t.side].courage
	var c := t.count
	var m: int = t.mor + n.mor
	var p: int = t.phys
	var removed := 0
	# same order as deal_damage: morale first (deserters shed health − 1 damage), then health
	while n.mor > 0 and c > 0 and m > c * cap(mv):
		c -= 1; removed += 1; m -= maxi(1, 2 * mv + cour)
		if p > 0: p = maxi(0, p - cap(h))
	p += n.phys
	var extra: int = cour if t.sp("courageHealth") else 0
	while c > 0 and p > c * cap(h):
		c -= 1; removed += 1; p -= maxi(1, 2 * h + extra)
	rng.set_state(save_rng)
	log.resize(save_log)
	damage_this_round = save_dmg
	var frac: float = (n.mor / float(maxi(1, mv * t.count))) + (n.phys / float(maxi(1, h * t.count)))
	return {"removed": removed, "total": n.total, "frac": frac}

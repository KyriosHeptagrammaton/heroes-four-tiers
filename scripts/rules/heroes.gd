# ============================================================================
# Heroes — primary stats, secondary skills, spells, artifacts, XP rules.
# A hero is a plain Dictionary so it saves/loads as JSON.
# ============================================================================
extends Node

## what each primary skill does in battle (shown as tooltips)
const PRIMARY_TEXT := {
	"attack": "[b]Attack (Atk)[/b]\n+1 attack to every creature in the army. Each point of attack above the target's defence adds +10% damage (up to +300%).",
	"defence": "[b]Defence (Def)[/b]\n+1 defence to every creature in the army. Each point of defence above the attacker's attack takes 5% off the damage (up to −75%).",
	"courage": "[b]Courage[/b]\nArmy courage at the start of battle = hero courage − (number of allied stacks + number of allied tier-4 creatures). Each point of army courage removes 1 extra morale damage whenever a creature deserts. The commander can spend courage to recall deserters.",
	"initiative": "[b]Initiative[/b]\nWhere the commander acts in the turn order: every 3 points = 1 initiative (shown as 1, 1+, 1++). Each point can also be spent as a pip to Embolden a stack (+1 advantage), which lowers the commander's initiative.",
	"power": "[b]Power (Pow)[/b]\nEvery point makes spells 10% stronger.",
	"knowledge": "[b]Knowledge[/b]\nThe budget for equipped spells: their total cost can't be more than your knowledge (one spell on its own is always allowed). Knowledge left over can revive fallen creatures during battle.",
}

func create(cls: String, faction: String, hero_name = null, rng: Rng = null) -> Dictionary:
	var st: Dictionary = D.CFG.heroStart[cls]
	var r := rng if rng else Rng.new(randi())
	var nm: String = hero_name if hero_name else D.HERO_NAMES[int(floor(r.next() * D.HERO_NAMES.size()))]
	var h := {
		"id": U.uid("h"), "name": nm, "cls": cls, "faction": faction,
		"stats": st.duplicate(),
		"xp": {"attack": 0, "defence": 0, "courage": 0, "initiative": 0, "power": 0, "knowledge": 0},
		"skills": (D.CLASSES[cls].skills as Dictionary).duplicate(),
		"skillXp": {}, "lastChosen": null, "pendingSkillChoice": null,
		"spellbook": ["flame", "valor", "sharpen", "mend", "dread", "haste"] if cls == "mage" else ["flame", "valor", "mend"],
		"equipped": [], "artifacts": [], "spellPower": {}, "level": 1,
	}
	for k in D.SKILLS:
		h.skillXp[k] = 0
	h.equipped = auto_equip(h)
	return h

func stat(h: Dictionary, k: String) -> int:
	var v: int = int(h.stats.get(k, 0))
	for a in h.artifacts:
		var A: Dictionary = D.ARTIFACTS.get(a, {})
		if A.has("stat") and A.stat.has(k):
			v += int(A.stat[k])
	if k == "initiative" and int(h.skills.get("tactics", 0)) >= 2:
		v += 1
	return v

func has(h, art: String) -> bool:
	return h != null and (h.artifacts as Array).has(art)

func skill(h, k: String) -> int:
	if h == null:
		return 0
	return int(h.skills.get(k, 0))

## Hero initiative "0, 0+, 0++, 1, 1+ ..." (3 points = 1 initiative)
func init_str(v: int) -> String:
	var whole := int(floor(v / 3.0))
	var pips := v - whole * 3
	return str(whole) + "+".repeat(maxi(0, pips))

func casts_per_round(h) -> float:
	return [1.0, 2.0, 4.0, INF][skill(h, "sorcery")]

func uses_per_spell(h) -> float:
	return [1.0, 2.0, 4.0, INF][skill(h, "arcana")]

func spell_cost(h, id: String) -> int:
	return int(D.SPELLS[id].cost) * (2 if is_inf(uses_per_spell(h)) else 1)

func equipped_cost(h, list = null) -> int:
	var l: Array = list if list != null else h.equipped
	var t := 0
	for id in l:
		t += spell_cost(h, id)
	return t

## Doc: with a spell book you may always have any ONE spell even if it exceeds knowledge
func can_equip(h, list: Array) -> bool:
	if list.size() <= 1:
		return true
	return equipped_cost(h, list) <= stat(h, "knowledge")

func auto_equip(h) -> Array:
	var out := []
	for p in ["flame", "valor", "sharpen", "dread", "mend", "haste"]:
		if (h.spellbook as Array).has(p) and can_equip(h, out + [p]):
			out.append(p)
	return out

# ---- primary XP: "3 (skilled) or 4 (unskilled) x the next level" -------------
func primary_cost(h, k: String) -> int:
	var c: Dictionary = D.CLASSES[h.cls]
	var skilled: bool = (c.skilled as Array).has(k) or c.get("flatPrimary", false)
	return (3 if skilled else 4) * (int(h.stats[k]) + 1)

## Skilled skills first, then unskilled. On level up add XP equal to the new level
## to a random skill in the same group (possibly the same one).
func apply_primary_levels(h, rng: Rng, log: Array = []) -> void:
	var skilled_set: Array = D.CLASSES[h.cls].skilled
	var groups := [D.PRIMARY.filter(func(k): return skilled_set.has(k)), D.PRIMARY.filter(func(k): return not skilled_set.has(k))]
	var guard := 0
	var changed := true
	while changed and guard < 200:
		guard += 1
		changed = false
		for grp in groups:
			for k in grp:
				var cost := primary_cost(h, k)
				if int(h.xp[k]) >= cost:
					h.stats[k] = int(h.stats[k]) + 1
					# Paragon (doc "Beta hero specialty") does not lose XP: level N needs 3N total
					if not D.CLASSES[h.cls].get("flatPrimary", false):
						h.xp[k] = int(h.xp[k]) - cost
					log.append("%s: %s rises to %d" % [h.name, k, h.stats[k]])
					if grp.size():
						var tgt = grp[int(floor(rng.next() * grp.size()))]
						h.xp[tgt] = int(h.xp[tgt]) + int(h.stats[k])
					changed = true

# ---- secondary skills --------------------------------------------------------
## cost of next tier = 3 x tier, plus (known tier x 2) for every OTHER known skill
func skill_cost(h, k: String) -> int:
	var nxt := skill(h, k) + 1
	var extra := 0
	var learner: bool = D.CLASSES[h.cls].get("learner", false)
	for o in h.skills:
		var t := int(h.skills[o])
		if o != k and t > 0:
			extra += maxi(0, t * 2 - 2) if learner else t * 2
	return 3 * nxt + extra

func skill_maxed(h, k: String) -> bool:
	var cur := skill(h, k)
	var mx: int = (D.SKILLS[k].tiers as Array).size()
	if cur >= mx:
		return true
	# cannot reach infinite (tier 3) in both sorcery and arcana
	if cur == 2 and ((k == "sorcery" and skill(h, "arcana") >= 3) or (k == "arcana" and skill(h, "sorcery") >= 3)):
		return true
	return false

func ready_skills(h) -> Array:
	if D.CLASSES[h.cls].get("noSecondary", false):
		return []
	return D.SKILLS.keys().filter(func(k): return not skill_maxed(h, k) and int(h.skillXp.get(k, 0)) >= skill_cost(h, k))

## When 2+ skills are ready, offer a choice between two (never the one chosen last time)
func maybe_offer_skill(h, rng: Rng):
	if h.pendingSkillChoice != null:
		return h.pendingSkillChoice
	var ready := ready_skills(h).filter(func(k): return k != h.lastChosen)
	if ready.size() < 2:
		return null
	for i in range(ready.size() - 1, 0, -1):
		var j := int(floor(rng.next() * (i + 1)))
		var t = ready[i]; ready[i] = ready[j]; ready[j] = t
	h.pendingSkillChoice = [ready[0], ready[1]]
	return h.pendingSkillChoice

func choose_skill(h, pick: String) -> void:
	var pair = h.pendingSkillChoice
	if pair == null:
		return
	var other: String = pair[1] if pair[0] == pick else pair[0]
	var cost := skill_cost(h, pick)
	h.skillXp[pick] = int(h.skillXp[pick]) - cost
	h.skillXp[other] = maxi(0, int(h.skillXp[other]) - cost)
	h.skills[pick] = skill(h, pick) + 1
	h.lastChosen = pick
	h.pendingSkillChoice = null
	# infinite uses doubles spell costs: re-validate equipment
	while h.equipped.size() > 1 and not can_equip(h, h.equipped):
		h.equipped.pop_back()

func add_skill_xp(h, cat: String, n: int) -> void:
	if n == 0:
		return
	for k in D.SKILLS:
		if D.SKILLS[k].cat == cat:
			h.skillXp[k] = int(h.skillXp.get(k, 0)) + n

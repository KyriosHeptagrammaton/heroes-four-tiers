# ============================================================================
# D — all rules data, loaded from res://data/data.json (edit that file to tune
# stats, spells, terrain, skills, prices...). Whole-number floats from JSON are
# turned back into ints so maths and formatting behave.
# ============================================================================
extends Node

var J: Dictionary
var CFG: Dictionary
var FACTIONS: Dictionary
var FACTION_IDS: Array
var UNIT_BASE: Dictionary
var MAGI: Dictionary
var SECOND_UPGRADE: Dictionary
var ABILITY_TEXT: Dictionary
var UNIT_NAMES: Dictionary
var SPELLS: Dictionary
var TERRAIN: Dictionary
var TIMES: Dictionary
var WEATHER: Dictionary
var SKILLS: Dictionary
var ARTIFACTS: Dictionary
var PRIMARY: Array
var CLASSES: Dictionary
var HERO_NAMES: Array
var OBJ: Dictionary
var MINES: Dictionary
var BUILDINGS: Dictionary
var MUSIC: Dictionary
var FLAGS: Array

const DX := [0, 1, 0, -1]
const DY := [-1, 0, 1, 0]

func _init() -> void:
	var f := FileAccess.open("res://data/data.json", FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	J = _ints(parsed)
	CFG = J["CFG"]; FACTIONS = J["FACTIONS"]; FACTION_IDS = J["FACTION_IDS"]; UNIT_BASE = J["UNIT_BASE"]; MAGI = J["MAGI"]
	SECOND_UPGRADE = J["SECOND_UPGRADE"]; ABILITY_TEXT = J["ABILITY_TEXT"]; UNIT_NAMES = J["UNIT_NAMES"]
	SPELLS = J["SPELLS"]; TERRAIN = J["TERRAIN"]; TIMES = J["TIMES"]; WEATHER = J["WEATHER"]; SKILLS = J["SKILLS"]
	ARTIFACTS = J["ARTIFACTS"]; PRIMARY = J["PRIMARY"]; CLASSES = J["CLASSES"]; HERO_NAMES = J["HERO_NAMES"]
	OBJ = J["OBJ"]; MINES = J["MINES"]; BUILDINGS = J["BUILDINGS"]; MUSIC = J["MUSIC"]; FLAGS = J["FLAGS"]

func _ints(v):
	match typeof(v):
		TYPE_FLOAT:
			if is_finite(v) and v == floor(v) and absf(v) < 1e15:
				return int(v)
			return v
		TYPE_DICTIONARY:
			var o := {}
			for k in v:
				o[k] = _ints(v[k])
			return o
		TYPE_ARRAY:
			var a := []
			for x in v:
				a.append(_ints(x))
			return a
	return v

func flag(id: String, area: String, text: String) -> void:
	for f in FLAGS:
		if f["id"] == id:
			return
	FLAGS.append({"id": id, "area": area, "text": text})

func opp(e: int) -> int:
	return (e + 2) % 4

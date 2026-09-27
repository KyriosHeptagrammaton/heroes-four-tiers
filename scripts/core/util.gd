# U — small helpers shared by rules and UI
extends Node

var _uid := 1

## JS Math.round: halves round toward +infinity
func jr(x: float) -> int:
	return int(floor(x + 0.5))

func fmt(v) -> String:
	if typeof(v) == TYPE_FLOAT and is_inf(v):
		return "∞"
	return str(jr(float(v)))

func sum(arr: Array):
	var s = 0
	for x in arr:
		s += x
	return s

func uid(p: String = "id") -> String:
	_uid += 1
	return "%s%d_%s" % [p, _uid, str(randi() % 1000000)]

## escape text for RichTextLabel BBCode
func esc(s) -> String:
	return str(s).replace("[", "[lb]")

func clampf2(v: float, lo: float, hi: float) -> float:
	return maxf(lo, minf(hi, v))

func color(hex: String) -> Color:
	return Color.html(hex)

func roman(n: int) -> String:
	return "I".repeat(n)

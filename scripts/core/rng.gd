# ============================================================================
# Seedable RNG — mulberry32, bit-for-bit identical to the JS prototype so the
# same seed produces the same battles/maps in both versions.
# ============================================================================
class_name Rng
extends RefCounted

const M32 := 0xFFFFFFFF
var a: int = 1

func _init(s: int = 1) -> void:
	a = s & M32
	if a == 0:
		a = 1

## low 32 bits of x*y, computed in halves so nothing overflows 64 bits
static func imul(x: int, y: int) -> int:
	x &= M32; y &= M32
	var lo := (x & 0xFFFF) * y
	var hi := (((x >> 16) * y) & 0xFFFF) << 16
	return (lo + hi) & M32

func next() -> float:
	a = (a + 0x6D2B79F5) & M32
	var t := imul(a ^ (a >> 15), 1 | a)
	t = ((t + imul(t ^ (t >> 7), 61 | t)) & M32) ^ t
	return float((t ^ (t >> 14)) & M32) / 4294967296.0

## inclusive integer in [lo, hi]
func rint(lo: int, hi: int) -> int:
	return lo + int(floor(next() * (hi - lo + 1)))

func pick(arr: Array):
	return arr[int(floor(next() * arr.size()))]

func shuffle(arr: Array) -> Array:
	for i in range(arr.size() - 1, 0, -1):
		var j := int(floor(next() * (i + 1)))
		var tmp = arr[i]; arr[i] = arr[j]; arr[j] = tmp
	return arr

func get_state() -> int:
	return a

func set_state(s: int) -> void:
	a = s & M32

## 角色身上看得到的兵器：劍斜背、刀扛在身側、槍直立、拳是手上的護手。程式畫的水墨線條，原點在腳底、面朝右。
## 出招時 swing 從 1 掉回 0，兵器跟著往前揮。品階越高刃上的光越亮。
extends Node2D

var kind := "sword"
var grade := 0
var swing := 0.0
var aura := Color(0, 0, 0, 0)
var aura_time := 0.0
var _time := 0.0

const INK := Color("#1b1814")
const STEEL := Color("#d9dccf")
const CINNABAR := Color("#b23a2e")
const WOOD := Color("#6b4a2f")


func _ready() -> void:
	show_behind_parent = true


func _process(delta: float) -> void:
	_time += delta
	swing = move_toward(swing, 0.0, delta * 5.0)
	aura_time = maxf(0.0, aura_time - delta)
	queue_redraw()


func _draw() -> void:
	var shine := Color(1.0, 0.95, 0.75, 0.25 + 0.15 * grade)
	draw_set_transform(Vector2.ZERO, -1.2 * swing, Vector2.ONE)
	match kind:
		"sword":
			# 斜背在身後：劍柄在右肩上，劍尖朝左下
			var hilt := Vector2(10, -66)
			var tip := Vector2(-22, -18)
			draw_line(hilt, tip, INK, 5.0, true)
			draw_line(hilt.lerp(tip, 0.1), tip, STEEL, 2.0, true)
			draw_line(hilt + Vector2(-6, -5), hilt + Vector2(6, 5), INK, 4.0, true)   # 劍格
			draw_line(hilt, hilt + Vector2(5, -10), CINNABAR, 3.0, true)             # 劍穗
			if grade > 0:
				draw_line(hilt.lerp(tip, 0.2), tip, shine, 4.0, true)
		"blade":
			# 厚背大刀垂在身側，刀背在外
			var top := Vector2(18, -50)
			var bottom := Vector2(26, -6)
			var pts := PackedVector2Array([top, bottom, bottom + Vector2(-10, -4), top + Vector2(-9, 4)])
			draw_colored_polygon(pts, STEEL)
			draw_polyline(pts + PackedVector2Array([top]), INK, 2.5, true)
			draw_line(top, top + Vector2(-3, -16), WOOD, 5.0, true)
			if grade > 0:
				draw_line(top + Vector2(-8, 5), bottom + Vector2(-9, -3), shine, 3.0, true)
		"spear":
			# 直立在身後，槍尖過頭
			var butt := Vector2(-14, -2)
			var head := Vector2(-6, -118)
			draw_line(butt, head, WOOD, 4.0, true)
			draw_colored_polygon(PackedVector2Array([head + Vector2(-5, 2), head + Vector2(2, -22), head + Vector2(6, 3)]), STEEL)
			draw_polyline(PackedVector2Array([head + Vector2(-5, 2), head + Vector2(2, -22), head + Vector2(6, 3)]), INK, 1.5, true)
			draw_circle(head + Vector2(0, 6), 4.0, CINNABAR)                         # 紅纓
			if grade > 0:
				draw_line(head, head + Vector2(2, -20), shine, 3.0, true)
		"fist":
			# 兩隻護手
			for p in [Vector2(12, -40), Vector2(-8, -38)]:
				draw_circle(p, 6.0, INK)
				draw_circle(p, 3.5, STEEL)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if aura_time > 0.0:
		# 金身：身外一圈墨金光，呼吸般明暗
		var a := (0.35 + 0.15 * sin(_time * 10.0)) * minf(1.0, aura_time * 3.0)
		draw_arc(Vector2(0, -44), 46.0, 0, TAU, 40, Color(aura, a), 6.0, true)
		draw_arc(Vector2(0, -44), 38.0, 0, TAU, 40, Color(aura, a * 0.5), 3.0, true)

## 一次性的水墨特效：劍氣墨痕、落地揚塵、浮起的傷害字。都是畫完自己淡出、自己刪掉的節點。
extends Node2D

enum Kind { SLASH, DUST, NUMBER }

var kind := Kind.SLASH
var facing := 1.0
var text := ""
var color := Color("#1b1814")
var life := 0.0
var duration := 0.28
var _seed := 0
var _font: Font


static func slash(parent: Node, pos: Vector2, dir: float) -> Node2D:
	var fx = load("res://scripts/ink_fx.gd").new()
	fx.kind = Kind.SLASH
	fx.facing = dir
	fx.position = pos
	parent.add_child(fx)
	return fx


static func dust(parent: Node, pos: Vector2) -> Node2D:
	var fx = load("res://scripts/ink_fx.gd").new()
	fx.kind = Kind.DUST
	fx.duration = 0.4
	fx.position = pos
	fx.color = Color("#5a4f40")
	parent.add_child(fx)
	return fx


static func number(parent: Node, pos: Vector2, value: String, tint: Color) -> Node2D:
	var fx = load("res://scripts/ink_fx.gd").new()
	fx.kind = Kind.NUMBER
	fx.duration = 0.8
	fx.text = value
	fx.color = tint
	fx.position = pos
	parent.add_child(fx)
	return fx


func _ready() -> void:
	_seed = randi()
	var custom: String = ProjectSettings.get_setting("gui/theme/custom_font", "")
	_font = load(custom) if custom != "" else ThemeDB.fallback_font
	z_index = 5


func _process(delta: float) -> void:
	life += delta
	if life >= duration:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var t := life / duration
	match kind:
		Kind.SLASH:
			_draw_slash(t)
		Kind.DUST:
			_draw_dust(t)
		Kind.NUMBER:
			_draw_number(t)


## 一道彎月形的墨痕，筆鋒朝前；尾端一點朱砂
func _draw_slash(t: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed
	var grow := minf(1.0, t * 3.5)
	var fade := 1.0 - smoothstep(0.35, 1.0, t)
	var arc_end := lerpf(-1.1, 1.0, grow)
	# 外圈墨、內圈月白劍光：亮暗背景都看得到
	for layer in 4:
		var r := 46.0 + layer * 7.0
		var c := Color("#f3ecd9") if layer == 0 else color
		var pts := PackedVector2Array()
		var widths := []
		var steps := 14
		for i in steps + 1:
			var a := lerpf(-1.1, arc_end, float(i) / steps)
			pts.append(Vector2(cos(a) * r * facing, sin(a) * r * 0.75) + Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)))
			widths.append(sin(PI * float(i) / steps) * (9.0 - layer * 2.0) + 1.0)
		for i in steps:
			draw_line(pts[i], pts[i + 1], Color(c, (0.9 - layer * 0.2) * fade), widths[i], true)
	draw_circle(Vector2(cos(arc_end) * 50.0 * facing, sin(arc_end) * 37.0), 3.0, Color("#b23a2e", fade))


## 幾團淡墨往兩側散開
func _draw_dust(t: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed
	var fade := 1.0 - t
	for i in 6:
		var side := -1.0 if i % 2 == 0 else 1.0
		var x := side * (6.0 + t * rng.randf_range(18, 34))
		var y := -t * rng.randf_range(4, 10)
		draw_circle(Vector2(x, y), rng.randf_range(3, 6) * (0.6 + t), Color(color, 0.35 * fade))


func _draw_number(t: float) -> void:
	var y := -t * 36.0
	var a := 1.0 - smoothstep(0.6, 1.0, t)
	var size := 22
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string_outline(_font, Vector2(-w / 2, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 5, Color(0.1, 0.08, 0.06, a))
	draw_string(_font, Vector2(-w / 2, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(color, a))

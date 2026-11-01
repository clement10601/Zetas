## 一次性的水墨特效：劍氣墨痕、落地揚塵、浮起的傷害字。都是畫完自己淡出、自己刪掉的節點。
extends Node2D

enum Kind { SLASH, DUST, NUMBER, HEAVY, THRUST, JAB, RING, WAVE, FIREBALL }

var kind := Kind.SLASH
var facing := 1.0
var text := ""
var color := Color("#1b1814")
var life := 0.0
var duration := 0.28
var _seed := 0
var step := 0          # 刀的第幾刀（第二刀更大）
var finisher := false
var reach := 90.0      # 槍的長度
var radius := 60.0     # 圈的半徑
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


static func _make(parent: Node, pos: Vector2, k: int, dur: float) -> Node2D:
	var fx = load("res://scripts/ink_fx.gd").new()
	fx.kind = k
	fx.duration = dur
	fx.position = pos
	return fx


## 刀：又大又厚的弧，前後都掃到，第二刀更大
static func heavy(parent: Node, pos: Vector2, dir: float, which: int) -> Node2D:
	var fx = _make(parent, pos, Kind.HEAVY, 0.36)
	fx.facing = dir
	fx.step = which
	parent.add_child(fx)
	return fx


## 槍：一條往前戳出去的直筆，槍尖一點朱砂
static func thrust(parent: Node, pos: Vector2, dir: float, length: float, last: bool) -> Node2D:
	var fx = _make(parent, pos, Kind.THRUST, 0.24)
	fx.facing = dir
	fx.reach = length
	fx.finisher = last
	parent.add_child(fx)
	return fx


## 拳：小圈墨點；收招是大圈加放射筆觸
static func jab(parent: Node, pos: Vector2, dir: float, last: bool) -> Node2D:
	var fx = _make(parent, pos, Kind.JAB, 0.3 if last else 0.18)
	fx.facing = dir
	fx.finisher = last
	parent.add_child(fx)
	return fx


## 擴散的墨圈：震地波、火符炸開、血祭、金身反震
static func ring(parent: Node, pos: Vector2, r: float, tint: Color, dur := 0.4) -> Node2D:
	var fx = _make(parent, pos, Kind.RING, dur)
	fx.radius = r
	fx.color = tint
	parent.add_child(fx)
	return fx


## 飛行物（劍氣 wave、火符 fireball）：不會自己消失，由 main 移動、打中或飛完時刪掉
static func projectile(parent: Node, pos: Vector2, dir: float, what: String) -> Node2D:
	var fx = _make(parent, pos, Kind.FIREBALL if what == "fireball" else Kind.WAVE, 1e9)
	fx.facing = dir
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
		Kind.HEAVY:
			_draw_heavy(t)
		Kind.THRUST:
			_draw_thrust(t)
		Kind.JAB:
			_draw_jab(t)
		Kind.RING:
			_draw_ring(t)
		Kind.WAVE:
			_draw_wave()
		Kind.FIREBALL:
			_draw_fireball()


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


## 刀：從背後上方掄到前方地面的大弧，筆觸粗、墨重，尾端炸開幾點墨
func _draw_heavy(t: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed
	var grow := minf(1.0, t * 3.0)
	var fade := 1.0 - smoothstep(0.4, 1.0, t)
	var size := 1.0 + 0.25 * step
	var a0 := -2.4
	var a1 := lerpf(a0, 1.2, grow)
	for layer in 4:
		var r := (58.0 + layer * 9.0) * size
		var c := Color("#f3ecd9") if layer == 0 else color
		var pts := PackedVector2Array()
		var n := 18
		for i in n + 1:
			var a := lerpf(a0, a1, float(i) / n)
			pts.append(Vector2(cos(a) * r * facing, sin(a) * r * 0.7) + Vector2(rng.randf_range(-2, 2), rng.randf_range(-2, 2)))
		for i in n:
			var w := sin(PI * float(i) / n) * (15.0 - layer * 3.0) * size + 2.0
			draw_line(pts[i], pts[i + 1], Color(c, (0.95 - layer * 0.2) * fade), w, true)
	if grow >= 1.0:
		for i in 5:
			var p := Vector2(cos(1.2) * 70.0 * size * facing, sin(1.2) * 50.0 * size) + Vector2(rng.randf_range(-20, 20), rng.randf_range(-8, 12)) * (1.0 + t)
			draw_circle(p, rng.randf_range(2, 5), Color(color, 0.6 * fade))


## 槍：一筆直戳，前段細、後段粗，槍尖朱紅；收招多兩道殘影
func _draw_thrust(t: float) -> void:
	var grow := minf(1.0, t * 5.0)
	var fade := 1.0 - smoothstep(0.45, 1.0, t)
	var tip := Vector2(reach * grow * facing, 0)
	var lanes := [0.0, -9.0, 9.0] if finisher else [0.0]
	for k in lanes.size():
		var off := Vector2(-14.0 * k * facing, lanes[k])
		var alpha := fade * (1.0 if k == 0 else 0.4)
		draw_line(off, tip + off, Color(color, 0.85 * alpha), 9.0, true)
		draw_line(off + Vector2(reach * 0.2 * facing, 0), tip + off, Color("#f3ecd9", 0.9 * alpha), 3.0, true)
	draw_colored_polygon(PackedVector2Array([tip + Vector2(-14 * facing, -7), tip + Vector2(10 * facing, 0), tip + Vector2(-14 * facing, 7)]), Color(color, fade))
	draw_circle(tip, 3.5, Color("#b23a2e", fade))


## 拳：一點墨團往外散；收招是大圈＋放射短筆
func _draw_jab(t: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed
	var fade := 1.0 - t
	var r := (16.0 + 30.0 * t) * (1.8 if finisher else 1.0)
	draw_arc(Vector2.ZERO, r, 0, TAU, 24, Color("#f3ecd9", 0.7 * fade), 9.0 if finisher else 6.0, true)
	draw_arc(Vector2.ZERO, r, 0, TAU, 24, Color(color, 0.9 * fade), 5.0 if finisher else 3.5, true)
	draw_circle(Vector2.ZERO, (8.0 if finisher else 5.0) * (1.0 - t), Color("#f3ecd9", fade))
	var spokes := 8 if finisher else 4
	for i in spokes:
		var a := TAU * i / spokes + rng.randf_range(-0.2, 0.2)
		var d := Vector2(cos(a), sin(a))
		draw_line(d * r * 0.8, d * r * 1.4, Color(color, 0.7 * fade), 3.0, true)


## 墨圈從中間往外擴，越擴越淡；底下壓一條地面的墨痕
func _draw_ring(t: float) -> void:
	var fade := 1.0 - smoothstep(0.3, 1.0, t)
	var r := radius * (0.25 + 0.75 * sqrt(t))
	draw_arc(Vector2.ZERO, r, 0, TAU, 48, Color("#1b1814", 0.5 * fade), 12.0 * (1.0 - t) + 4.0, true)
	draw_arc(Vector2.ZERO, r, 0, TAU, 48, Color(color, 0.95 * fade), 9.0 * (1.0 - t) + 2.5, true)
	draw_arc(Vector2.ZERO, r * 0.7, 0, TAU, 40, Color(Color("#1b1814"), 0.4 * fade), 3.0, true)
	draw_line(Vector2(-r, 0), Vector2(r, 0), Color(color, 0.5 * fade), 5.0, true)


## 劍氣：月白彎月往前飛，外圈墨、後面拖兩道淡影
func _draw_wave() -> void:
	var flicker := 0.85 + 0.15 * sin(life * 40.0)
	for g in 3:
		var back := Vector2(-g * 16.0 * facing, 0)
		var alpha := (1.0 - g * 0.35) * flicker
		for layer in 3:
			var r := 34.0 + layer * 6.0
			var c := Color("#f3ecd9") if layer == 0 else Color("#1b1814")
			var pts := PackedVector2Array()
			for i in 13:
				var a := lerpf(-1.2, 1.2, i / 12.0)
				pts.append(back + Vector2(cos(a) * r * 0.6 * facing, sin(a) * r))
			for i in 12:
				draw_line(pts[i], pts[i + 1], Color(c, (0.9 - layer * 0.25) * alpha), sin(PI * i / 12.0) * (8.0 - layer * 2.0) + 1.0, true)
	draw_circle(Vector2(cos(0.0) * 20.0 * facing, 0), 2.5, Color("#b23a2e", flicker))


## 火符：朱紅墨團，外層橘焰抖動，後面拖火星
func _draw_fireball() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(life * 30.0)
	for i in 6:
		var p := Vector2(-facing * (10.0 + i * 9.0), rng.randf_range(-6, 6))
		draw_circle(p, 6.0 - i * 0.8, Color("#d9622b", 0.5 - i * 0.07))
	draw_circle(Vector2.ZERO, 16.0 + rng.randf_range(-1.5, 1.5), Color("#d9622b", 0.85))
	draw_circle(Vector2.ZERO, 10.0, Color("#b23a2e"))
	draw_circle(Vector2(2 * facing, -2), 4.0, Color("#f3ecd9", 0.9))
	draw_arc(Vector2.ZERO, 17.0, 0, TAU, 20, Color("#1b1814", 0.6), 2.0, true)

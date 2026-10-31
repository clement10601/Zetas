## 地圖的景深層：背景畫後面不動，前面再疊兩層視差。
## - 山嵐：淡淡的霧帶，比地面慢一點、自己緩緩飄，在畫和角色之間。
## - 近景：畫面最下方的墨色草葉與石塊，比地面快，蓋在角色前面但不擋到腳。
## 全部程式畫，不需要素材；顏色依地圖標籤換（洞窟、心魔幻境）。
extends RefCounted

const MIST_Z := -1
const FRONT_Z := 10
const TILE := 1600.0


static func mist_color(tags: Array) -> Color:
	if tags.has("illusion"):
		return Color(0.75, 0.32, 0.3, 0.24)
	if tags.has("cave"):
		return Color(0.7, 0.74, 0.78, 0.18)
	return Color(0.97, 0.96, 0.92, 0.38)


static func add_layers(level: Node, floor_y: float, tags: Array, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	level.add_child(_mist(floor_y, mist_color(tags), rng))
	level.add_child(_front(floor_y, rng))


static func _mist(floor_y: float, color: Color, rng: RandomNumberGenerator) -> Parallax2D:
	var layer := Parallax2D.new()
	layer.name = "Mist"
	layer.z_index = MIST_Z
	layer.scroll_scale = Vector2(0.85, 1.0)
	layer.repeat_size = Vector2(TILE, 0)
	layer.repeat_times = 3
	layer.autoscroll = Vector2(-9.0, 0)
	var g := GradientTexture2D.new()
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.0, 0.5)
	g.width = 128
	g.height = 64
	g.gradient = Gradient.new()
	g.gradient.set_color(0, Color(1, 1, 1, 1))
	g.gradient.set_color(1, Color(1, 1, 1, 0))
	for i in 9:
		var s := Sprite2D.new()
		s.texture = g
		s.modulate = color
		s.modulate.a *= rng.randf_range(0.6, 1.0)
		s.position = Vector2(i * TILE / 9 + rng.randf_range(-60, 60), floor_y - rng.randf_range(20, 360))
		s.scale = Vector2(rng.randf_range(4.0, 7.0), rng.randf_range(0.9, 1.6))
		layer.add_child(s)
	return layer


static func _front(floor_y: float, rng: RandomNumberGenerator) -> Parallax2D:
	var layer := Parallax2D.new()
	layer.name = "Foreground"
	layer.z_index = FRONT_Z
	layer.scroll_scale = Vector2(1.3, 1.0)
	layer.repeat_size = Vector2(TILE, 0)
	layer.repeat_times = 3
	var ink := Color(0.05, 0.045, 0.04, 1.0)
	var base := floor_y + 120.0     # 鏡頭下緣是 floor_y + 110（main.gd CAMERA_BOTTOM）
	var x := rng.randf_range(40, 160)
	while x < TILE - 120:
		if rng.randf() < 0.35:
			layer.add_child(_stone(Vector2(x, base), rng.randf_range(90, 170), rng, ink))
		else:
			layer.add_child(_tuft(Vector2(x, base), rng.randf_range(100, 170), rng, ink))
		x += rng.randf_range(220, 520)
	return layer


## 一叢草：幾片彎的葉子，筆觸由粗到細。
static func _tuft(at: Vector2, height: float, rng: RandomNumberGenerator, ink: Color) -> Node2D:
	var tuft := Node2D.new()
	tuft.position = at
	for i in rng.randi_range(9, 15):
		var lean := rng.randf_range(-0.9, 0.9)
		var h := height * rng.randf_range(0.55, 1.0)
		var w := rng.randf_range(7, 13)
		var pts := PackedVector2Array()
		var steps := 6
		for k in steps + 1:
			var t := float(k) / steps
			var cx := lean * h * 0.6 * t * t + rng.randf_range(-1, 1)
			pts.append(Vector2(cx - w * (1.0 - t) / 2, -h * t))
		for k in range(steps, -1, -1):
			var t := float(k) / steps
			var cx := lean * h * 0.6 * t * t
			pts.append(Vector2(cx + w * (1.0 - t) / 2, -h * t))
		var blade := Polygon2D.new()
		blade.polygon = pts
		blade.color = ink
		blade.position.x = rng.randf_range(-22, 22)
		tuft.add_child(blade)
	return tuft


## 一塊石頭：不規則的墨塊，上緣淡一點。
static func _stone(at: Vector2, width: float, rng: RandomNumberGenerator, ink: Color) -> Node2D:
	var stone := Polygon2D.new()
	stone.position = at
	var pts := PackedVector2Array()
	var n := 9
	var h := width * rng.randf_range(0.45, 0.7)
	for k in n + 1:
		var a := PI * float(k) / n
		var r := rng.randf_range(0.85, 1.1)
		pts.append(Vector2(-cos(a) * width / 2 * r, -sin(a) * h * r))
	stone.polygon = pts
	stone.color = ink
	return stone

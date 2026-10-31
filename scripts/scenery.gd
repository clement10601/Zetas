## 地圖的景深層：背景畫後面不動，前面再疊兩層視差。
## - 山嵐：淡淡的霧帶，比地面慢一點、自己緩緩飄，在畫和角色之間。
## - 近景：畫面最下方的墨色草葉與石塊，比地面快，蓋在角色前面但不擋到腳。
## - 遠霧：一條極慢的水平霧帶，壓在底圖上，遠景退後一點（空氣透視）。
## - 垂掛：從畫面上緣垂下的柳枝／殿柱／鐘乳石，半透明、比地面快，偶爾擋到角色（Hollow Knight 式前景）。
##   打鬥地圖（幻境、獸穴）不放，免得擋視線。
## 全部程式畫，不需要素材；顏色依地圖標籤換（洞窟、心魔幻境）。
extends RefCounted

const HAZE_Z := -9
const MIST_Z := -8              # 底圖 -10、接縫霧 -9，山嵐在其上、平台與角色之下
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
	level.add_child(_haze(floor_y, mist_color(tags)))
	var kind := hanging_kind(tags)
	if kind != "":
		level.add_child(_hanging(floor_y, kind, rng))


## 垂掛前景的種類；空字串表示不放
static func hanging_kind(tags: Array) -> String:
	if tags.has("illusion") or tags.has("den"):
		return ""
	if tags.has("sect") or tags.has("hall"):
		return "pillar"
	if tags.has("cave"):
		return "stalactite"
	return "willow"


static func _haze(floor_y: float, color: Color) -> Parallax2D:
	var layer := Parallax2D.new()
	layer.name = "Haze"
	layer.z_index = HAZE_Z
	layer.scroll_scale = Vector2(0.05, 1.0)
	layer.repeat_size = Vector2(TILE, 0)
	layer.repeat_times = 3
	var g := GradientTexture2D.new()
	g.fill_from = Vector2(0.5, 0.0)
	g.fill_to = Vector2(0.5, 1.0)
	g.width = 4
	g.height = 64
	g.gradient = Gradient.new()
	g.gradient.set_color(0, Color(1, 1, 1, 0))
	g.gradient.set_color(1, Color(1, 1, 1, 0))
	g.gradient.add_point(0.55, Color(1, 1, 1, 1))
	var band := Sprite2D.new()
	band.texture = g
	band.centered = false
	band.modulate = Color(color, color.a * 0.45)
	band.position = Vector2(0, floor_y - 420)
	band.scale = Vector2(TILE / 4.0, 340.0 / 64.0)
	layer.add_child(band)
	return layer


static func _hanging(floor_y: float, kind: String, rng: RandomNumberGenerator) -> Parallax2D:
	var layer := Parallax2D.new()
	layer.name = "Hanging"
	layer.z_index = FRONT_Z
	layer.scroll_scale = Vector2(1.25, 1.0)
	layer.repeat_size = Vector2(TILE, 0)
	layer.repeat_times = 3
	# 整層一起淡，重疊處不會更黑；柱子整根擋住，再淡一些
	layer.modulate = Color(1, 1, 1, 0.38 if kind == "pillar" else 0.55)
	var ink := Color(0.07, 0.065, 0.06, 1.0)
	var top := floor_y - 700.0      # 比鏡頭上緣（floor_y - 640）再高一點
	var x := rng.randf_range(200, 500)
	while x < TILE - 150:
		match kind:
			"pillar":
				layer.add_child(_pillar(Vector2(x, top), floor_y, rng, ink))
			"stalactite":
				layer.add_child(_stalactites(Vector2(x, top), rng, ink))
			_:
				layer.add_child(_willow(Vector2(x, top), rng, ink))
		x += rng.randf_range(900, 1300) if kind == "pillar" else rng.randf_range(650, 1000)
	return layer


## 柳枝：幾條細長的弧線垂下來，末端點幾片葉
static func _willow(at: Vector2, rng: RandomNumberGenerator, ink: Color) -> Node2D:
	var node := Node2D.new()
	node.position = at
	for i in rng.randi_range(4, 7):
		var length := rng.randf_range(220, 360)
		var sway := rng.randf_range(-40, 40)
		var line := Line2D.new()
		line.width = rng.randf_range(2.5, 4.0)
		line.default_color = ink
		line.width_curve = Curve.new()
		line.width_curve.add_point(Vector2(0, 1))
		line.width_curve.add_point(Vector2(1, 0.3))
		var x0 := rng.randf_range(-70, 70)
		for k in 9:
			var t := k / 8.0
			line.add_point(Vector2(x0 + sway * t * t, length * t))
		node.add_child(line)
		for k in rng.randi_range(5, 9):
			var t := rng.randf_range(0.3, 1.0)
			var leaf := Polygon2D.new()
			var p := Vector2(x0 + sway * t * t, length * t)
			var side := -1.0 if k % 2 == 0 else 1.0
			leaf.polygon = PackedVector2Array([Vector2.ZERO, Vector2(side * 5, 9), Vector2(side * 2, 22), Vector2(-side * 2, 10)])
			leaf.position = p
			leaf.rotation = side * 0.35
			leaf.color = ink
			node.add_child(leaf)
	return node


## 殿柱：一根直到地面的柱子，上頭一截斗栱，左右邊緣筆觸略深
static func _pillar(at: Vector2, floor_y: float, rng: RandomNumberGenerator, ink: Color) -> Node2D:
	var node := Node2D.new()
	node.position = at
	var w := rng.randf_range(30, 40)
	var h := floor_y + 140.0 - at.y
	var body := Polygon2D.new()
	body.polygon = PackedVector2Array([Vector2(-w / 2, 0), Vector2(w / 2, 0), Vector2(w / 2 + 3, h), Vector2(-w / 2 - 3, h)])
	body.color = ink
	node.add_child(body)
	var cap := Polygon2D.new()
	cap.polygon = PackedVector2Array([Vector2(-w * 1.6, 70), Vector2(w * 1.6, 70), Vector2(w, 100), Vector2(-w, 100)])
	cap.color = ink
	node.add_child(cap)
	return node


## 鐘乳石：一排長短不一的尖錐
static func _stalactites(at: Vector2, rng: RandomNumberGenerator, ink: Color) -> Node2D:
	var node := Node2D.new()
	node.position = at
	var x := -90.0
	while x < 90.0:
		var w := rng.randf_range(16, 34)
		var length := rng.randf_range(110, 260)
		var cone := Polygon2D.new()
		cone.polygon = PackedVector2Array([Vector2(x, 0), Vector2(x + w, 0), Vector2(x + w * 0.55, length), Vector2(x + w * 0.4, length - 4)])
		cone.color = ink
		node.add_child(cone)
		x += w + rng.randf_range(4, 22)
	return node


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
	var ink := Color(0.07, 0.065, 0.06, 0.9)
	var base := floor_y + 120.0     # 鏡頭下緣是 floor_y + 110（main.gd CAMERA_BOTTOM）
	var x := rng.randf_range(40, 160)
	while x < TILE - 120:
		if rng.randf() < 0.35:
			layer.add_child(_stone(Vector2(x, base), rng.randf_range(60, 120), rng, ink))
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

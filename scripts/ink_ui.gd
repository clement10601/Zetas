## 水墨卷軸風的介面：全域字樣（字加墨色描邊，亮暗背景都看得清）、紙面面板、墨底狀態列、氣血／修為條。
## 只用 StyleBoxFlat 與程式產生的漸層，不需要額外圖檔；網頁版（相容渲染器）也能用。
extends RefCounted

const INK := Color("#1b1814")
const INK_SOFT := Color("#3a332b")
const PAPER := Color("#ece3cc")
const PAPER_EDGE := Color("#c9b994")
const CINNABAR := Color("#b23a2e")
const JADE := Color("#6fa597")
const GOLD := Color("#c9a45c")
const MOON := Color("#f3ecd9")


## 裝上全域主題：併進引擎的預設主題，所有 Control 都吃得到（主題不會穿過 Node2D／CanvasLayer 往下傳，
## 掛在 root 視窗上沒有用）。只裝一次。
static func install() -> void:
	var base := ThemeDB.get_default_theme()
	if base.has_meta("zetas_ink"):
		return
	base.merge_with(make_theme())
	base.set_meta("zetas_ink", true)


static func make_theme() -> Theme:
	var t := Theme.new()
	t.set_color("font_color", "Label", MOON)
	t.set_color("font_outline_color", "Label", Color(INK, 0.85))
	t.set_constant("outline_size", "Label", 5)
	t.set_font_size("font_size", "Label", 16)
	# 紙面：對話框、地圖選單
	t.set_type_variation("PaperLabel", "Label")
	t.set_color("font_color", "PaperLabel", INK)
	t.set_constant("outline_size", "PaperLabel", 0)
	t.set_font_size("font_size", "PaperLabel", 20)
	t.set_constant("line_spacing", "PaperLabel", 6)
	t.set_type_variation("NameLabel", "Label")
	t.set_color("font_color", "NameLabel", MOON)
	t.set_constant("outline_size", "NameLabel", 0)
	t.set_font_size("font_size", "NameLabel", 18)
	t.set_type_variation("HudTitle", "Label")
	t.set_font_size("font_size", "HudTitle", 20)
	t.set_type_variation("HudSmall", "Label")
	t.set_font_size("font_size", "HudSmall", 14)
	t.set_color("font_color", "HudSmall", Color(MOON, 0.85))
	return t


static func paper_box() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = PAPER
	s.border_color = INK_SOFT
	s.set_border_width_all(2)
	s.border_width_top = 3
	s.border_width_bottom = 3
	s.set_corner_radius_all(3)
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 10
	s.shadow_offset = Vector2(3, 5)
	s.content_margin_left = 28
	s.content_margin_right = 28
	s.content_margin_top = 18
	s.content_margin_bottom = 16
	return s


## 卷軸兩端的軸頭
static func roller() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color("#4a2f22")
	s.border_color = GOLD
	s.border_width_top = 3
	s.border_width_bottom = 3
	s.set_corner_radius_all(4)
	return s


## 墨底半透明面板（狀態列、紀錄）
static func ink_box(alpha := 0.62, accent := Color.TRANSPARENT) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(INK, alpha)
	s.set_corner_radius_all(6)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	if accent.a > 0:
		s.border_color = accent
		s.border_width_left = 4
	return s


## 印章樣式的名牌（朱砂底）
static func seal_box(color := CINNABAR) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(2)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 3
	s.content_margin_bottom = 4
	s.shadow_color = Color(0, 0, 0, 0.3)
	s.shadow_size = 3
	return s


## 細長的筆刷條：氣血用朱砂、修為用青玉
static func bar(color: Color, width := 150.0) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = Vector2(width, 9)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.45)
	bg.border_color = Color(MOON, 0.25)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(4)
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fill)
	return b


## 暗角：畫面四周壓一圈淡墨，讓視線集中在中間
static func vignette_texture() -> GradientTexture2D:
	var g := Gradient.new()
	# 偏暖的墨色，像紙邊受潮暈開
	var warm := Color("#2b1d12")
	g.set_color(0, Color(warm, 0.0))
	g.set_color(1, Color(warm, 0.6))
	g.add_point(0.6, Color(warm, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.08, 1.08)
	tex.width = 256
	tex.height = 144
	return tex


## 傳送點的光暈：以底部中央為心的橢圓，往上、往兩側淡出
static func portal_glow(color: Color) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(color, 0.6))
	g.set_color(1, Color(color, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 1.0)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 64
	tex.height = 64
	return tex


## 小圓點（粒子用）：中間實、邊緣柔
static func soft_dot(size := 16) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = size
	tex.height = size
	return tex


## 各時辰的整體色調（CanvasModulate，只染世界、不染介面）
static func time_tint(time_of_day: String) -> Color:
	return {
		"晨": Color("#f4efe6"),
		"午": Color("#ffffff"),
		"暮": Color("#e9b088"),
		"夜": Color("#6f7ca8"),
	}.get(time_of_day, Color.WHITE)


static var _halo: ShaderMaterial


## 角色立繪用：後面一圈淡紙色光暈（scripts/ink_halo.gdshader），大家共用一個材質
static func halo_material() -> ShaderMaterial:
	if _halo == null:
		_halo = ShaderMaterial.new()
		_halo.shader = load("res://scripts/ink_halo.gdshader")
	return _halo


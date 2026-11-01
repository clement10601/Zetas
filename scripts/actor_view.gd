## 角色（NPC、敵人、常駐 NPC）的外觀與小動作。原點在腳底，縮放與傾斜都以腳底為軸，
## 所以只動這個節點的 scale／rotation，不碰立繪本身（立繪的縮放代表身高）。
## 站著會呼吸、移動時一步一頓、被打會閃紅後退、倒下時墨散淡出。
extends Node2D

var hostile := false
var phase := 0.0            # 每個角色錯開，免得整排一起呼吸
var _last_x := 0.0
var _walk := 0.0
var _moving := 0.0          # 0–1，最近有沒有在走
var _hit := 0.0             # 被打後的閃紅、後仰，1 → 0
var _hit_dir := 1.0
var _dying := false
var _shadow: TextureRect
var _omen: Label            # 出招前搖時頭上的朱紅「煞」字
var _windup := 0.0          # 前搖蓄力，0–1
var winding := false


func _ready() -> void:
	_last_x = position.x
	phase = randf() * TAU
	# 用 TextureRect 不用 Sprite2D：view 底下的 Sprite2D 只該有立繪一張
	_shadow = TextureRect.new()
	_shadow.texture = shadow_texture()
	_shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_shadow.size = Vector2(56, 14)
	_shadow.position = Vector2(-28, -7)
	_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shadow.modulate = Color(1, 1, 1, 0.55)
	add_child(_shadow)
	move_child(_shadow, 0)


func _process(delta: float) -> void:
	if _dying:
		return
	var dx := position.x - _last_x
	_last_x = position.x
	var speed := absf(dx) / maxf(delta, 0.0001)
	_moving = move_toward(_moving, 1.0 if speed > 8.0 else 0.0, delta * 6.0)
	_walk += delta * clampf(speed, 0.0, 200.0) / 14.0
	phase += delta
	_hit = move_toward(_hit, 0.0, delta * 3.5)
	var breathe := sin(phase * 2.1) * 0.014 * (1.0 - _moving)
	var step := absf(sin(_walk)) * 0.035 * _moving
	scale = Vector2(1.0 - breathe * 0.5, 1.0 + breathe - step)
	var lean := signf(dx) * 0.07 * _moving if hostile else 0.0
	_windup = move_toward(_windup, 1.0 if winding else 0.0, delta * (5.0 if winding else 8.0))
	# 前搖：往後仰、身子拉高、泛朱紅；收招時回來
	scale *= Vector2(1.0 - 0.05 * _windup, 1.0 + 0.07 * _windup)
	rotation = lean - _hit_dir * 0.18 * _hit + (0.12 if hostile else 0.0) * _windup * (1.0 if _facing_right() else -1.0)
	var omen_tint := Color(1.0, 0.55 - 0.15 * sin(phase * 22.0), 0.45)
	modulate = Color.WHITE.lerp(omen_tint, _windup * 0.8).lerp(Color(1.0, 0.45, 0.4), _hit)


func _facing_right() -> bool:
	for c in get_children():
		if c is Sprite2D:
			return not c.flip_h
	return false


## 出招前搖（朱紅預兆）：頭上浮現「煞」字、身子後仰泛紅；on=false 收起。height 是角色身高。
func telegraph(on: bool, height := 120.0) -> void:
	winding = on
	if not on:
		if _omen != null:
			var fade := _omen.create_tween()
			fade.tween_property(_omen, "modulate:a", 0.0, 0.15)
			fade.tween_callback(_omen.queue_free)
			_omen = null
		return
	if _omen != null:
		return
	_omen = Label.new()
	_omen.text = "煞"
	_omen.add_theme_font_size_override("font_size", 30)
	_omen.add_theme_color_override("font_color", Color("#d2321e"))
	_omen.add_theme_color_override("font_outline_color", Color(0.08, 0.05, 0.04, 0.9))
	_omen.add_theme_constant_override("outline_size", 6)
	_omen.size = Vector2(40, 40)
	_omen.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_omen.pivot_offset = Vector2(20, 20)
	_omen.position = Vector2(-20, -height - 70)
	_omen.scale = Vector2.ONE * 1.8
	_omen.modulate.a = 0.0
	add_child(_omen)
	var tw := _omen.create_tween().set_parallel(true)
	tw.tween_property(_omen, "scale", Vector2.ONE, 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(_omen, "modulate:a", 1.0, 0.12)


## 被擊中：閃紅、往後仰。from_x 是打過來的人的位置。
func hit(from_x: float) -> void:
	_hit = 1.0
	_hit_dir = signf(position.x - from_x)
	if _hit_dir == 0.0:
		_hit_dir = 1.0
	position.x += _hit_dir * 14.0


## 倒下：往後倒、化成墨散掉，然後移除。
func die() -> void:
	telegraph(false)
	_dying = true
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "rotation", -_hit_dir * 1.2, 0.45).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "modulate", Color(0.1, 0.08, 0.07, 0.0), 0.55)
	tw.tween_property(self, "scale", Vector2(1.15, 0.85), 0.55)
	tw.chain().tween_callback(queue_free)


static var _shadow_tex: Texture2D


## 腳下的淡墨影子（共用一張）
static func shadow_texture() -> Texture2D:
	if _shadow_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(0.08, 0.06, 0.05, 0.6))
		g.set_color(1, Color(0.08, 0.06, 0.05, 0.0))
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.width = 32
		tex.height = 32
		_shadow_tex = tex
	return _shadow_tex

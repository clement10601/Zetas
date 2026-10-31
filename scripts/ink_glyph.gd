## 字訣特效：照筆順寫出一個字（寫字）→ 停一下（成形）→ 淡出，或命中時碎成墨點（散墨）。
## 字形與筆順貼圖由 tools/glyph_fx.py 從授權字型產生，在 art/fx/。之後的術法都用同一套三段。
extends Node2D

const WRITE := 0.18
const HOLD := 0.12
const FADE := 0.22
const SCATTER := 0.32

var glyph := "zhan"
var size := 84.0
var hit := false
var _t := 0.0
var _sprite: Sprite2D
var _mat: ShaderMaterial
var _burst_done := false

static var _shader: Shader


static func spawn(parent: Node, pos: Vector2, name: String = "zhan", px: float = 84.0) -> Node2D:
	var path := "res://art/fx/%s.png" % name
	if not ResourceLoader.exists(path):
		return null
	var fx = load("res://scripts/ink_glyph.gd").new()
	fx.glyph = name
	fx.size = px
	fx.position = pos
	parent.add_child(fx)
	return fx


func _ready() -> void:
	z_index = 6
	if _shader == null:
		_shader = load("res://scripts/ink_glyph.gdshader")
	_mat = ShaderMaterial.new()
	_mat.shader = _shader
	_sprite = Sprite2D.new()
	_sprite.texture = load("res://art/fx/%s.png" % glyph)
	_sprite.material = _mat
	_mat.set_shader_parameter("glyph_tex", _sprite.texture)
	_sprite.scale = Vector2.ONE * size / _sprite.texture.get_height()
	add_child(_sprite)


## 命中：寫完之後碎成墨點，而不是淡出
func shatter() -> void:
	hit = true


func _process(delta: float) -> void:
	_t += delta
	var progress := clampf(_t / WRITE, 0.0, 1.0)
	_mat.set_shader_parameter("progress", progress)
	var after := _t - WRITE - HOLD
	if hit:
		var s := clampf((_t - WRITE) / SCATTER, 0.0, 1.0)
		_mat.set_shader_parameter("scatter", s)
		if _t >= WRITE and not _burst_done:
			_burst_done = true
			_burst()
		if s >= 1.0:
			queue_free()
	elif after > 0.0:
		modulate.a = 1.0 - after / FADE
		if after >= FADE:
			queue_free()


## 墨點往外噴：一次性的粒子
func _burst() -> void:
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.emitting = true
	p.amount = 26
	p.lifetime = 0.45
	p.explosiveness = 0.9
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = size * 0.3
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.initial_velocity_min = 60.0
	p.initial_velocity_max = 170.0
	p.gravity = Vector2(0, 260)
	p.texture = preload("res://scripts/ink_ui.gd").soft_dot(10)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.1
	p.color = Color(0.08, 0.06, 0.05, 0.9)
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = fade
	add_child(p)

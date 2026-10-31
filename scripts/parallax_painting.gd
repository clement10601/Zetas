## 區塊背景畫的視差：畫比區塊寬一點，鏡頭移動時畫只跟著走一部分（DEPTH），
## 看起來比平台和角色遠。畫只在自己的區塊範圍內顯示；和左邊的區塊在接縫處交疊淡入，
## 不會有硬邊。仍然是 TextureRect，素材管線與測試照舊。
extends TextureRect

const DEPTH := 0.12             # 0 = 跟地面一起動，1 = 釘在畫面上
const FEATHER := 140.0           # 接縫交疊的寬度
const HEIGHT := 600.0           # 美術規格的畫高（art/STYLE.md）

const SHADER := """
shader_type canvas_item;
uniform vec2 window = vec2(0.0, 1.0);   // 區塊左右緣，以畫的 UV 表示
uniform float feather = 0.05;
uniform bool fade_left = true;
uniform bool cut_right = true;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float a = 1.0;
	if (fade_left) {
		a *= smoothstep(window.x - feather * 0.5, window.x + feather * 0.5, UV.x);
	}
	if (cut_right && UV.x > window.y + feather * 0.5) {
		a = 0.0;
	}
	COLOR = vec4(c.rgb, c.a * a);
}
"""

static var _shader: Shader

var win_left := 0.0
var win_width := 0.0
var margin := 0.0


## left/width 是區塊在地圖上的範圍；first/last 表示地圖兩端（外側不必淡入或裁掉）。
func setup(tex: Texture2D, left: float, width: float, floor_y: float, first: bool, last: bool) -> void:
	texture = tex
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	win_left = left
	win_width = width
	margin = DEPTH * width / 2 + FEATHER / 2
	var w := width + 2 * margin
	var h := HEIGHT * w / width       # 等比放大，多出來的裁掉天空那一側
	size = Vector2(w, h)
	position = Vector2(left - margin, floor_y - h)
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	material = ShaderMaterial.new()
	material.shader = _shader
	material.set_shader_parameter("feather", FEATHER / w)
	material.set_shader_parameter("fade_left", not first)
	material.set_shader_parameter("cut_right", not last)
	_apply(left + width / 2)


func _process(_delta: float) -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var center := vp.get_canvas_transform().affine_inverse() * (vp.get_visible_rect().size / 2)
	_apply(center.x)


func _apply(camera_x: float) -> void:
	var limit := DEPTH * win_width / 2
	var shift := clampf((camera_x - (win_left + win_width / 2)) * DEPTH, -limit, limit)
	position.x = win_left - margin + shift
	var local_left := win_left - position.x
	material.set_shader_parameter("window", Vector2(local_left, local_left + win_width) / size.x)

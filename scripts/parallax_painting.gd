## 區塊背景畫（古畫中景）的視差。框固定在區塊範圍（左右各多出半個接縫寬，再多留畫能移動的距離），
## 鏡頭移動時著色器在框裡把畫往回取樣，畫只跟著走一部分；框裡畫移開的地方是透明的。
## 相鄰兩塊的畫只會越移越疊在一起（右邊那塊移得比左邊那塊少），接縫不會露出縫。
## 而且越往上走得越少：畫的上半（遠山）幾乎不動、下半（近處坡腳）跟得多，同一張畫裡也拉出遠近。
## 上半另外往天色淡化（空氣透視），下半稍微加強對比；畫上方空白的天是透明的（tools/inkpaint/skyline.py），
## 後面露出 scenery.gd 的天色與遠山層。和左邊的區塊在接縫處交疊淡入，不會有硬邊。
extends TextureRect

const DEPTH := 0.24             # 畫的下半（近處）：鏡頭走 100，畫跟著走 24
const DEPTH_FAR := 0.06         # 畫頂（遠山）
const RIGID_FROM := 0.62        # 畫高這個比例以下都用 DEPTH，房子、牌坊不會被拉斜
const FEATHER := 140.0          # 接縫交疊的寬度
const HEIGHT := 600.0           # 美術規格的畫高（art/STYLE.md）
const SINK := 120.0             # 畫往下沉（底下被地面蓋住），畫面上緣露出天與遠山

const SHADER := """
shader_type canvas_item;
uniform float rel = 0.0;          // 鏡頭離區塊中心多遠（px）
uniform float rect_w = 1.0;       // 框寬（px）
uniform float paint_w = 1.0;      // 畫鋪開的寬（px）
uniform float extra = 0.0;        // 畫最多能往左右移多少（px），框兩邊各多留這麼寬
uniform float depth_far = 0.06;
uniform float depth_near = 0.24;
uniform float rigid_from = 0.62;
uniform float feather = 0.05;     // 以畫寬為 1
uniform bool fade_left = true;
uniform vec4 haze : source_color = vec4(0.9, 0.88, 0.82, 0.35);
// 青綠山水式的上色：依明度把墨色映到「深墨 → 地區主色 → 紙色」，再和原畫混合 tone_mix
uniform vec4 tone_dark : source_color = vec4(0.1, 0.13, 0.15, 1.0);
uniform vec4 tone_mid : source_color = vec4(0.33, 0.5, 0.45, 1.0);
uniform vec4 tone_light : source_color = vec4(0.95, 0.91, 0.82, 1.0);
uniform float tone_mix = 0.0;

varying vec4 tint;

void vertex() {
	tint = COLOR;
}

float shift_at(float v) {
	float d = mix(depth_far, depth_near, smoothstep(0.0, rigid_from, v));
	return clamp(rel * d, -extra, extra);
}

void fragment() {
	float u = (UV.x * rect_w - extra - shift_at(UV.y)) / paint_w;
	vec4 c = texture(TEXTURE, vec2(clamp(u, 0.0, 1.0), UV.y));
	// 古畫褪色的絹底偏灰：拉一點彩度與對比，畫面不再那麼素
	float l = dot(c.rgb, vec3(0.3, 0.59, 0.11));
	c.rgb = clamp((mix(vec3(l), c.rgb, 1.35) - 0.55) * 1.08 + 0.55, 0.0, 1.0);
	vec3 toned = l < 0.55 ? mix(tone_dark.rgb, tone_mid.rgb, smoothstep(0.05, 0.55, l))
		: mix(tone_mid.rgb, tone_light.rgb, smoothstep(0.55, 0.9, l));
	c.rgb = mix(c.rgb, toned, tone_mix);
	// 空氣透視：越上面越淡、越偏天色
	float far = 1.0 - smoothstep(0.05, 0.7, UV.y);
	c.rgb = mix(c.rgb, haze.rgb, far * haze.a);
	// 近處墨色重一點
	float near = smoothstep(0.55, 1.0, UV.y);
	c.rgb = mix(c.rgb, clamp((c.rgb - 0.6) * 1.1 + 0.6, 0.0, 1.0), near);
	float a = step(0.0, u) * step(u, 1.0);
	if (fade_left) {
		a *= smoothstep(0.0, feather, u);
	}
	a *= smoothstep(0.0, 0.07, UV.y);    // 畫頂不留硬邊
	COLOR = vec4(c.rgb, c.a * a) * tint;   // fragment 裡的 COLOR 已乘過原 UV 的貼圖色，不能直接乘
}
"""

static var _shader: Shader

var win_left := 0.0
var win_width := 0.0
var extra := 0.0
var paint_w := 0.0
var rel := 0.0


## left/width 是區塊在地圖上的範圍；first 表示地圖最左（不必淡入）；haze 是這塊的天色。
## 各地區的上色（深、主色、亮）與混合比例；幻境、洞窟保持原樣
const TONES := {
	"forest": [Color("#18232a"), Color("#4d7867"), Color("#f1e8d2"), 0.42],
	"sect": [Color("#1a2330"), Color("#4b6f8a"), Color("#efe7d4"), 0.3],
	"mountain": [Color("#1e1a18"), Color("#7a6248"), Color("#ede2cc"), 0.38],
	"village": [Color("#1f1c18"), Color("#7d6a3e"), Color("#f2e8cf"), 0.36],
}


static func tone_for(tags: Array) -> Array:
	for t in ["sect", "village", "mountain", "forest"]:
		if tags.has(t) or (t == "sect" and tags.has("hall")) or (t == "mountain" and tags.has("ravine")) or (t == "village" and tags.has("shrine")):
			return TONES[t]
	return []


func setup(tex: Texture2D, left: float, width: float, floor_y: float, first: bool, _last: bool, haze := Color(0.9, 0.88, 0.82), tags: Array = []) -> void:
	texture = tex
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	win_left = left
	win_width = width
	extra = DEPTH * width / 2
	var margin := FEATHER / 2
	paint_w = width + 2 * margin
	var rect_w := paint_w + 2 * extra
	var h := HEIGHT * paint_w / width     # 等比放大，畫不會被壓扁
	size = Vector2(rect_w, h)
	position = Vector2(left - margin - extra, floor_y + SINK - h)
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	material = ShaderMaterial.new()
	material.shader = _shader
	material.set_shader_parameter("rect_w", rect_w)
	material.set_shader_parameter("paint_w", paint_w)
	material.set_shader_parameter("extra", extra)
	material.set_shader_parameter("depth_far", DEPTH_FAR)
	material.set_shader_parameter("depth_near", DEPTH)
	material.set_shader_parameter("rigid_from", RIGID_FROM)
	material.set_shader_parameter("feather", FEATHER / paint_w)
	material.set_shader_parameter("fade_left", not first)
	material.set_shader_parameter("haze", Color(haze.lerp(Color.WHITE, 0.45), 0.35))
	var tone := tone_for(tags)
	if not tone.is_empty() and not (tags.has("illusion") or tags.has("cave")):
		material.set_shader_parameter("tone_dark", tone[0])
		material.set_shader_parameter("tone_mid", tone[1])
		material.set_shader_parameter("tone_light", tone[2])
		material.set_shader_parameter("tone_mix", tone[3])
	_apply(left + width / 2)


func _process(_delta: float) -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var center := vp.get_canvas_transform().affine_inverse() * (vp.get_visible_rect().size / 2)
	_apply(center.x)


func _apply(camera_x: float) -> void:
	rel = camera_x - (win_left + win_width / 2)
	material.set_shader_parameter("rel", rel)


## 畫高比例 v（0 頂、1 底）那一列目前跟著鏡頭移了多少（px），和著色器同一個算法
func shift_at(v: float) -> float:
	var d := lerpf(DEPTH_FAR, DEPTH, smoothstep(0.0, RIGID_FROM, v))
	return clampf(rel * d, -extra, extra)

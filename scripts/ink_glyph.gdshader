// 字訣：依筆順寫出一個字（art/fx/*.png：R 字形、G 寫到的時間、B 第幾筆），
// 外圈一層淡紙色讓暗背景上也看得到；scatter > 0 時字從後寫的筆畫開始碎成墨點散去。
shader_type canvas_item;

uniform float progress = 0.0;   // 0–1 寫到哪裡
uniform float scatter = 0.0;    // 0–1 散墨
uniform vec4 ink : source_color = vec4(0.08, 0.06, 0.05, 1.0);
uniform vec4 glow : source_color = vec4(0.97, 0.94, 0.86, 0.55);
// 跟 Sprite2D 的貼圖同一張；函式裡不能用 TEXTURE（相容渲染器不支援把它當參數傳），所以另設一個
uniform sampler2D glyph_tex : filter_linear;

float written(vec2 uv) {
	vec4 t = texture(glyph_tex, uv);
	return t.r * smoothstep(t.g - 0.001, t.g + 0.03, progress);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	float a = written(UV);
	float g = 0.0;
	for (int i = 0; i < 8; i++) {
		float ang = float(i) * 0.785398;
		g = max(g, written(UV + vec2(cos(ang), sin(ang)) * TEXTURE_PIXEL_SIZE * 5.0));
	}
	// 散墨：每一小塊依雜訊決定何時消失，後寫的筆畫先散
	vec2 cell = floor(UV * 48.0);
	float order = texture(TEXTURE, UV).b;
	float gone = step(hash(cell) * 0.7 + (1.0 - order) * 0.3, scatter);
	float keep = 1.0 - gone;
	float fade = 1.0 - smoothstep(0.6, 1.0, scatter);
	vec3 rgb = mix(glow.rgb, ink.rgb, a);
	float out_a = max(a * ink.a, g * glow.a) * keep * fade;
	COLOR = vec4(rgb, out_a) * tint;
}

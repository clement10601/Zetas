// 角色後面一圈淡紙色光暈：把立繪的不透明範圍往外擴 radius 個貼圖像素，填上紙色，
// 角色在繁複的古畫上靠明度差跳出來（設計文件 reference-study.md 的 A1）。
// 保留父節點的 modulate（受擊閃紅、倒下淡出）。
shader_type canvas_item;

uniform vec4 halo_color : source_color = vec4(0.96, 0.93, 0.85, 0.35);
uniform float radius = 14.0;

varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float a = 0.0;
	for (int i = 0; i < 12; i++) {
		float ang = float(i) * 0.5235988;
		vec2 dir = vec2(cos(ang), sin(ang)) * TEXTURE_PIXEL_SIZE;
		a = max(a, texture(TEXTURE, UV + dir * radius).a * 0.6);
		a = max(a, texture(TEXTURE, UV + dir * radius * 0.5).a);
	}
	float ha = halo_color.a * a * (1.0 - c.a);
	float out_a = c.a + ha;
	vec3 rgb = out_a > 0.0 ? (c.rgb * c.a + halo_color.rgb * ha) / out_a : c.rgb;
	COLOR = vec4(rgb, out_a) * tint;
}

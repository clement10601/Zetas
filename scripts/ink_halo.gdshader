// 角色立繪的「遊戲感」：
// 1. 外圈一道墨色描邊（比立繪本身的勾線粗），剪影在繁複的古畫上一眼看得出來。
// 2. 描邊外一圈依身分上色的光暈：玩家青玉、敵人朱砂、其他人淡金紙色（ink_ui.gd 的 halo_material）。
// 3. 立繪本身提高彩度與對比，不再灰灰的像底圖的一部分。
// 半徑以貼圖像素計（立繪約 4 倍解析度，outline 8 ≈ 畫面上 2px）。保留父節點的 modulate（受擊閃紅、倒下淡出）。
shader_type canvas_item;

uniform vec4 halo_color : source_color = vec4(0.96, 0.93, 0.85, 0.4);
uniform vec4 outline_color : source_color = vec4(0.07, 0.06, 0.05, 0.92);
uniform float outline = 8.0;
uniform float radius = 20.0;
uniform float saturation = 1.3;
uniform float contrast = 1.08;

varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float line = 0.0;
	float glow = 0.0;
	for (int i = 0; i < 12; i++) {
		float ang = float(i) * 0.5235988;
		vec2 dir = vec2(cos(ang), sin(ang)) * TEXTURE_PIXEL_SIZE;
		line = max(line, texture(TEXTURE, UV + dir * outline).a);
		line = max(line, texture(TEXTURE, UV + dir * outline * 0.5).a);
		glow = max(glow, texture(TEXTURE, UV + dir * radius).a * 0.55);
		glow = max(glow, texture(TEXTURE, UV + dir * (outline + radius) * 0.5).a);
	}
	// 立繪本身：彩度、對比
	float l = dot(c.rgb, vec3(0.3, 0.59, 0.11));
	vec3 body = mix(vec3(l), c.rgb, saturation);
	body = clamp((body - 0.5) * contrast + 0.5, 0.0, 1.0);
	// 由外往內疊：光暈 → 描邊 → 立繪
	float ga = halo_color.a * glow;
	float la = outline_color.a * smoothstep(0.2, 0.6, line);
	vec3 rgb = halo_color.rgb;
	float a = ga;
	rgb = mix(rgb, outline_color.rgb, la);
	a = la + a * (1.0 - la);
	rgb = mix(rgb, body, c.a);
	a = c.a + a * (1.0 - c.a);
	COLOR = vec4(rgb, a) * tint;
}

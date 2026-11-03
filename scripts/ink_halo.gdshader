// 角色立繪的「遊戲感」：
// 1. 外圈一道墨色描邊（比立繪本身的勾線粗），剪影在繁複的古畫上一眼看得出來。
// 2. 描邊外一圈依身分上色的光暈：玩家青玉、敵人朱砂、其他人淡金紙色（ink_ui.gd 的 halo_material）。
// 3. 立繪本身提高彩度與對比，不再灰灰的像底圖的一部分。
// 4. 飄動（玩家用；預設 bend 0 不動）：像奇幻之境把衣片掛在骨頭上整片轉，不拉伸。以 pivot（貼圖 UV）為軸，
//    pivot 下方離軸越遠彎得越多（reach 貼圖像素處到 bend 弧度），長度不變；ripple 是沿著長度往外傳的小擺動（弧度）。
//    bend 正＝往立繪背後甩（立繪面朝右，背後是 -x）。飄帶、後髮（飄動層，軸在肩頸）與腿（身體那張，軸在胯，只有御劍、御風用）各一份參數，見 player.gd。
// 半徑以貼圖像素計（立繪約 4 倍解析度，outline 8 ≈ 畫面上 2px）。保留父節點的 modulate（受擊閃紅、倒下淡出）。
shader_type canvas_item;

uniform vec4 halo_color : source_color = vec4(0.96, 0.93, 0.85, 0.4);
uniform vec4 outline_color : source_color = vec4(0.07, 0.06, 0.05, 0.92);
uniform float outline = 8.0;
uniform float radius = 20.0;
uniform float saturation = 1.3;
uniform float contrast = 1.08;
uniform float bend = 0.0;
uniform float ripple = 0.0;
uniform float ripple_phase = 0.0;    // 由腳本累加（換狀態時速度變了也不會跳）
uniform vec2 pivot = vec2(0.5, 0.25);
uniform float reach = 200.0;

varying vec4 tint;

void vertex() {
	tint = COLOR;
}

vec2 warp(vec2 uv, vec2 px) {
	if (bend == 0.0 && ripple == 0.0) {
		return uv;
	}
	vec2 d = (uv - pivot) / px;                     // 貼圖像素
	float r = length(d);
	float below = smoothstep(-30.0, 40.0, d.y);      // 軸以上（頭頂的髮）不動
	float k = clamp(r / reach, 0.0, 1.6);           // 越遠彎越多：整條是一道弧，不是一根棍子
	float a = (bend * k + ripple * sin(ripple_phase - r * 0.03) * k) * below;
	// 輸出點往回轉 a，找到原圖上的點（整片繞軸轉，長度不變）
	float c = cos(a);
	float s = sin(a);
	vec2 src = vec2(d.x * c + d.y * s, -d.x * s + d.y * c);
	return pivot + src * px;
}

vec4 sample_tex(sampler2D tex, vec2 uv, vec2 px) {
	vec2 u = warp(uv, px);
	if (u.x < 0.0 || u.x > 1.0 || u.y < 0.0 || u.y > 1.0) {
		return vec4(0.0);
	}
	return texture(tex, u);
}

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE;
	vec4 c = sample_tex(TEXTURE, UV, px);
	float line = 0.0;
	float glow = 0.0;
	for (int i = 0; i < 12; i++) {
		float ang = float(i) * 0.5235988;
		vec2 dir = vec2(cos(ang), sin(ang)) * TEXTURE_PIXEL_SIZE;
		line = max(line, sample_tex(TEXTURE, UV + dir * outline, px).a);
		line = max(line, sample_tex(TEXTURE, UV + dir * outline * 0.5, px).a);
		glow = max(glow, sample_tex(TEXTURE, UV + dir * radius, px).a * 0.55);
		glow = max(glow, sample_tex(TEXTURE, UV + dir * (outline + radius) * 0.5, px).a);
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

shader_type canvas_item;

// 伪 3D 棋盘形变：用单应矩阵把平面棋盘重投影成"旋转中的面板"
// inv_matrix：屏幕 UV → 棋盘 UV（由 BoardView3D 每帧更新）
// depth_shade：倾斜程度（0=正对，越大越暗，用于表现厚度感）
// shadow_offset：投影偏移（UV，y 方向），为空处补一层柔和阴影
// 注意：Godot 的 fragment 函数内不能用 return，这里用条件嵌套

uniform mat3 inv_matrix;
uniform float depth_shade : hint_range(0.0, 1.0) = 0.0;
uniform float shadow_offset = 0.010;

void fragment() {
	vec4 c = vec4(0.0);
	vec3 m = inv_matrix * vec3(UV, 1.0);
	if (abs(m.z) >= 0.00001) {
		vec2 src = m.xy / m.z;
		if (src.x >= -0.02 && src.x <= 1.02 && src.y >= -0.02 && src.y <= 1.02) {
			vec2 clamped = clamp(src, vec2(0.0), vec2(1.0));
			vec4 tex = texture(TEXTURE, clamped);
			if (tex.a < 0.01) {
				// 空白处：用偏移采样做一层淡淡投影，制造悬浮感
				vec4 sh = texture(TEXTURE, clamp(src + vec2(0.0, shadow_offset), vec2(0.0), vec2(1.0)));
				c = vec4(0.32, 0.40, 0.36, sh.a * 0.16);
			} else {
				tex.rgb *= (1.0 - depth_shade * 0.16);
				c = tex;
			}
		}
	}
	COLOR = c;
}

// A sea anemone on the sand: a short column and a crown of soft tentacles swaying in the current, their tips lighter.
// col is its color; extra.y (the seed) varies the sway and the lean.
float4 draw_coral_anemone(float2 c, float t, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.2, 1.0);
    float column = sd_box(p - float2(0.0, -0.7), float2(0.32, 0.22), 0.12);
    float tent = 1e3, tipT = 0.0;
    for (int i = 0; i < 13; i++) {
        float fi = float(i);
        float s = (fi - 6.0) / 6.0;
        float2 q = float2(s * 0.3, -0.5);
        float ang = s * 1.1 + sin(t * 0.9 + fi * 0.7 + extra.y * 6.0) * 0.18 + (extra.y - 0.5) * 0.3;
        float len = 0.62 + 0.18 * fract(sin(fi * 12.9 + extra.y) * 43.7);
        for (int j = 0; j < 4; j++) {
            float t1 = float(j + 1) / 4.0;
            float a2 = ang + sin(t * 1.3 + fi + t1 * 3.0) * 0.25 * t1;
            float2 q1 = q + float2(sin(a2), cos(a2)) * len / 4.0;
            float2 pa = p - q, ba = q1 - q;
            float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
            float dd = length(pa - ba * h) - mix(0.06, 0.035, (float(j) + h) / 4.0);
            if (dd < tent) { tent = dd; tipT = (float(j) + h) / 4.0; }
            q = q1;
        }
    }
    float d = min(smin_k(column, tent, 0.06), tent);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float3 c3;
    if (tent < column) {
        c3 = mix(col.rgb * 0.75, col.rgb * 1.2 + float3(0.25, 0.2, 0.25), smoothstep(0.55, 1.0, tipT));
        c3 *= 0.8 + 0.3 * smoothstep(-0.5, 0.4, p.y);
    } else {
        c3 = mix(col.rgb, float3(0.85, 0.75, 0.6), 0.4) * (0.6 + 0.4 * smoothstep(-0.95, -0.5, p.y));
        c3 *= 0.9 + 0.1 * sin(p.x * 40.0);                                           // vertical stripes on the column
    }
    c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.025, -d)) * 0.25;
    return float4(c3 * a, a);
}

// Tube sponges: a cluster of three or four open tubes of different heights, rough, darker inside the openings.
float4 draw_coral_sponge(float2 c, float t, float glow, float4 col, float4 extra) {
    float2 p = c * float2(0.8, 1.0);
    float d = 1e3, which = 0.0;
    float3 c3 = col.rgb;
    for (int i = 0; i < 4; i++) {
        float fi = float(i);
        float x0 = -0.32 + fi * 0.21 + (fract(extra.y * 7.0 + fi * 0.3) - 0.5) * 0.06;
        float h = 0.45 + 0.5 * fract(sin(fi * 7.1 + extra.y * 13.0) * 91.3);
        float lean = (fi - 1.5) * 0.06;
        float2 q = p - float2(x0 + lean * (p.y + 0.9), 0.0);
        float w = 0.12 + 0.02 * sin(q.y * 9.0 + fi);
        float tube = max(abs(q.x) - w, max(-0.9 - q.y, q.y - (-0.9 + h)));
        if (tube < d) { d = tube; which = fi; }
    }
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float n = vnoise(p * 16.0 + extra.y * 9.0);
    c3 = col.rgb * (0.7 + 0.35 * n) * (0.65 + 0.45 * smoothstep(-0.9, 0.3, p.y));
    c3 *= 0.85 + 0.15 * (1.0 - smoothstep(0.0, 0.06, -d));
    // the openings: each tube's top is darker inside a lighter lip
    float top = 1e3;
    for (int i = 0; i < 4; i++) {
        float fi = float(i);
        float x0 = -0.32 + fi * 0.21 + (fract(extra.y * 7.0 + fi * 0.3) - 0.5) * 0.06;
        float h = 0.45 + 0.5 * fract(sin(fi * 7.1 + extra.y * 13.0) * 91.3);
        float lean = (fi - 1.5) * 0.06;
        top = min(top, length((p - float2(x0 + lean * h, -0.9 + h - 0.02)) / float2(0.11, 0.035)) - 1.0);
    }
    c3 = mix(c3, col.rgb * 0.3, (1.0 - smoothstep(-0.2, 0.0, top)) * 0.8);
    c3 = mix(c3, col.rgb * 1.3 + 0.08, (1.0 - smoothstep(0.0, 0.25, abs(top))) * 0.4);
    return float4(c3 * a, a);
}

// The reef's far side: coral heads and sea fans in silhouette along the bottom, fading into the blue.
float4 draw_coral_background(float2 uv, float t, float light, float2 gaze, float3 water, float4 extra) {
    if (uv.y > 0.5) return float4(0.0);
    float x = uv.x + gaze.x * 0.004;
    float h = extra.z + 0.06 + 0.08 * vnoise(float2(x * 4.0, 1.3)) + 0.05 * vnoise(float2(x * 13.0, 3.7));
    h += 0.08 * smoothstep(0.15, 0.0, abs(x - 0.3)) + 0.06 * smoothstep(0.12, 0.0, abs(x - 0.82));
    // bumps of coral heads on the ridge
    h += 0.025 * max(0.0, sin(x * 60.0) * sin(x * 23.0));
    float4 out = float4(0.0);
    if (uv.y < h) {
        float far = smoothstep(h - 0.12, h, uv.y);
        float3 tint = mix(float3(0.45, 0.32, 0.5), float3(0.35, 0.5, 0.55), vnoise(float2(x * 6.0, 2.0)));
        float3 c3 = mix(water, tint * (0.5 + 0.6 * light), 0.6 * (1.0 - far * 0.4));
        c3 += tint * 0.15 * (1.0 - smoothstep(0.0, 0.01, h - uv.y)) * light;           // the ridge catches the light
        out = float4(c3, 0.8);
    }
    // a few sea fans standing on the ridge, lacy and faint
    for (int k = 0; k < 5; k++) {
        float fk = float(k);
        float x0 = 0.1 + fk * 0.2 + 0.05 * sin(fk * 3.0);
        float2 q = float2((x - x0) * extra.x, uv.y - (extra.z + 0.1 + 0.05 * fract(fk * 0.71)));
        float r = length(q / float2(1.0, 1.2));
        float fan = (1.0 - smoothstep(0.06, 0.07, r)) * step(0.0, q.y) * (0.5 + 0.5 * step(0.5, fract(atan2(q.x, q.y) * 6.0 + r * 30.0)));
        out = mix(out, float4(mix(water, float3(0.55, 0.35, 0.5) * (0.4 + 0.6 * light), 0.3), 1.0) * 0.7, fan * 0.6);
    }
    return out;
}

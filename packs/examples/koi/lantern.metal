// Tōrō, a stone lantern standing on the sand: a base, a post, the firebox with a window, a curved roof and a jewel on
// top. At night its window glows (glow) and lights the stone around it. extra.y: a seed for the moss and the wear.
float4 draw_lantern(float2 c, float t, float glow, float4 col, float4 extra) {
    float2 p = c;
    float base = sd_box(p - float2(0.0, -0.9), float2(0.62, 0.1), 0.04);
    float post = sd_box(p - float2(0.0, -0.55), float2(0.2, 0.26), 0.03);
    float plat = sd_box(p - float2(0.0, -0.24), float2(0.6, 0.06), 0.03);
    float box = sd_box(p - float2(0.0, 0.03), float2(0.42, 0.22), 0.03);
    // the roof: wide, with tips curving up
    float ry = p.y - 0.3;
    float roofW = 0.86 - ry * 1.6 + 0.08 * smoothstep(0.5, 0.9, abs(p.x));
    float roof = max(abs(p.x) - roofW * 0.95, max(-ry, ry - 0.24 + 0.1 * smoothstep(0.55, 0.9, abs(p.x))));
    roof = max(roof, -(ry + 0.05 - 0.12 * smoothstep(0.45, 0.95, abs(p.x))) * 1.0);
    float jewel = min(length(p - float2(0.0, 0.66)) - 0.08, sd_box(p - float2(0.0, 0.57), float2(0.04, 0.04), 0.01));
    float d = min(min(min(base, post), min(plat, box)), min(roof, jewel));
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    // the window and the light behind it
    float win = sd_box(p - float2(0.0, 0.03), float2(0.2, 0.13), 0.02);
    float inWin = 1.0 - smoothstep(-aa, aa, win);
    float bars = step(abs(p.x), 0.015) * inWin;
    // stone: weathered, with moss on the upper faces
    float n = vnoise(p * 6.0 + extra.y * 20.0) * 0.6 + vnoise(p * 17.0) * 0.4;
    float3 stone = col.rgb * (0.75 + 0.35 * n);
    float up = smoothstep(0.02, -0.02, max(roof, -1.0)) * smoothstep(0.15, 0.3, ry);
    stone = mix(stone, float3(0.32, 0.42, 0.26) * dot(col.rgb, float3(0.7)), smoothstep(0.55, 0.75, n + up * 0.4) * 0.6);
    // light from above: tops bright, undersides dark (under the roof, under the platform)
    float shade = 0.75 + 0.3 * smoothstep(-1.0, 1.0, p.y);
    shade *= 1.0 - 0.35 * (1.0 - smoothstep(0.0, 0.06, -(p.y - 0.28))) * step(abs(p.x), 0.45) * step(p.y, 0.3) * step(0.2, p.y);
    float3 c3 = stone * shade;
    c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.03, -d)) * 0.3;
    // the glow: warm light in the window, spilling onto the stone around it
    float3 warm = float3(1.0, 0.72, 0.32);
    float spill = exp(-max(win, 0.0) * 9.0) * glow;
    c3 += warm * spill * 0.35 * (1.0 - inWin);
    float3 lit = mix(float3(0.08, 0.06, 0.05), warm * (0.8 + 0.6 * glow), clamp(0.15 + glow, 0.0, 1.0));
    lit *= 0.9 + 0.1 * sin(t * 7.0 + extra.y * 30.0) * glow;                    // the flame flickers
    c3 = mix(c3, lit, inWin * (1.0 - bars));
    c3 = mix(c3, stone * 0.5, bars);
    return float4(c3 * a, a);
}

// The arctic's far side and ceiling: an ice sheet over the surface, cracked, the light coming through it in soft
// shafts, and ice cliffs far away along the bottom, fading into the cold blue.
float4 draw_arctic_background(float2 uv, float t, float light, float2 gaze, float3 water, float4 extra) {
    float x = uv.x + gaze.x * 0.004;
    float4 out = float4(0.0);
    // ice cliffs along the bottom: tall, flat-topped, with vertical faces
    float h = extra.z + 0.04 + 0.08 * smoothstep(0.25, 0.75, vnoise(float2(x * 2.5, 1.1)));
    h += 0.025 * vnoise(float2(x * 40.0, 3.3)) + 0.015 * abs(sin(x * 70.0));            // a jagged, broken top
    if (uv.y < h) {
        // vertical striations of old ice, lighter toward the top, fading into the water
        float stria = 0.5 + 0.5 * sin(x * extra.x * 140.0 + vnoise(float2(x * 30.0, uv.y * 6.0)) * 4.0);
        float3 ice = mix(float3(0.45, 0.62, 0.78), float3(0.75, 0.88, 0.97), stria * 0.35 + 0.4 * smoothstep(h - 0.12, h, uv.y));
        ice *= 0.35 + 0.65 * light;
        float3 c3 = mix(water, ice, 0.28);
        c3 += float3(0.7, 0.85, 1.0) * (1.0 - smoothstep(0.0, 0.005, h - uv.y)) * 0.25 * light;   // the lit edge on top
        out = float4(c3, 0.8);
    }
    // the ice sheet overhead: from the surface down, thick and uneven, with cracks of light
    float under = 0.9 - 0.035 * vnoise(float2(x * 6.0, 2.0)) - 0.02 * vnoise(float2(x * 23.0, 5.0));
    if (uv.y > under) {
        float depth = (uv.y - under) / max(0.001, 1.0 - under);
        float2 cp = float2(x * extra.x * 7.0, uv.y * 7.0);
        float crack = vor_edge(cp + 3.0);
        float3 sheet = mix(float3(0.62, 0.78, 0.9), float3(0.9, 0.96, 1.0), depth) * (0.45 + 0.55 * light);
        sheet *= 0.85 + 0.25 * vnoise(cp * 1.5);
        sheet = mix(sheet, float3(0.95, 0.98, 1.0) * (0.5 + 0.6 * light), (1.0 - smoothstep(0.0, 0.05, crack)) * 0.6);
        // its underside is darker and bluer, catching the water's color
        sheet = mix(water * 1.3, sheet, smoothstep(0.0, 0.25, depth));
        out = float4(sheet, 1.0);
    }
    // light shafts coming down through the cracks, soft
    if (uv.y < under) {
        float s = pow(max(0.0, sin((x + uv.y * 0.12) * 37.0) * sin((x - uv.y * 0.05) * 13.0)), 6.0);
        float fade = smoothstep(0.2, under, uv.y);
        float3 shaft = float3(0.75, 0.9, 1.0) * s * fade * 0.12 * light;
        out = float4(out.rgb + shaft * (1.0 - out.a), out.a + length(shaft) * 0.3 * (1.0 - out.a));
    }
    return out;
}

// An ice floe floating at the surface: a flat slab, white on top, blue-green where it goes under, its edge lit.
// The water line is at c.y ≈ 0.12 / 0.5 = 0.24.
float4 draw_arctic_floe(float2 c, float t, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.0, 0.5);
    float wl = 0.12;
    float top = wl + 0.05 + 0.03 * vnoise(float2(p.x * 4.0 + extra.y * 9.0, 1.0));
    float bottom = wl - 0.22 - 0.06 * vnoise(float2(p.x * 3.0 + extra.y * 5.0, 2.0));
    float halfw = 0.85 - 0.1 * vnoise(float2(p.y * 6.0, extra.y * 7.0));
    float d = max(max(abs(p.x) - halfw * (1.0 - 0.25 * smoothstep(wl, bottom, p.y)), p.y - top), bottom - p.y);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float3 c3;
    if (p.y > wl) {
        c3 = mix(float3(0.85, 0.92, 0.97), float3(1.0), smoothstep(wl, top, p.y)) * col.rgb;         // snow on top
    } else {
        float k = (wl - p.y) / max(0.001, wl - bottom);
        c3 = mix(float3(0.6, 0.85, 0.9), float3(0.2, 0.45, 0.6), k) * col.rgb;                      // under water
        a *= 0.85 - 0.3 * k;
    }
    c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.02, -d)) * 0.2;
    return float4(c3 * a, a);
}

// The chest, frozen in a block of ice: the old chest blurred inside, the block's facets and frost. extra.y is how
// open it is (the summary is showing): the ice cracks and a warm light comes through.
float4 draw_arctic_frozen_chest(float2 c, float t, float glow, float4 col, float4 extra) {
    float2 p = c;
    float open = clamp(extra.y, 0.0, 1.0);
    float block = sd_box(p - float2(0.0, -0.15), float2(0.82, 0.72), 0.08);
    float aa = fwidth(block) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, block);
    // the chest inside, soft
    float chest = sd_box(p - float2(0.0, -0.35), float2(0.5, 0.3), 0.04);
    float lid = max(length((p - float2(0.0, -0.05)) / float2(0.52, 0.22)) - 1.0, -(p.y + 0.05));
    float inside = 1.0 - smoothstep(-0.03, 0.05, min(chest, lid * 0.22));
    float3 wood = float3(0.45, 0.28, 0.14) * (0.8 + 0.2 * step(0.5, fract((p.y + 1.0) * 6.0)));
    float band = step(abs(abs(p.x) - 0.3), 0.04);
    wood = mix(wood, float3(0.5, 0.45, 0.35), band);
    // the ice: bluish, facets, frost toward the edges, a highlight
    float2 fp = p * 3.0;
    float facet = vor_edge(fp + 7.0);
    float3 ice = mix(float3(0.55, 0.75, 0.88), float3(0.85, 0.94, 1.0), smoothstep(-0.6, 0.6, p.y + 0.3 * p.x));
    ice *= 0.9 + 0.15 * smoothstep(0.0, 0.2, facet);
    float3 c3 = mix(ice, mix(ice, wood, 0.65), inside);
    c3 = mix(c3, float3(1.0), (1.0 - smoothstep(0.0, 0.08, -block)) * 0.45);           // frost at the edges
    c3 += float3(1.0) * pow(max(0.0, 1.0 - length((p - float2(-0.45, 0.35)) / float2(0.25, 0.12))), 3.0) * 0.4;
    // open: cracks of warm light
    float cr = 1.0 - smoothstep(0.0, 0.025, abs(vnoise(p * 4.0 + 3.0) - 0.5));
    c3 = mix(c3, float3(1.0, 0.82, 0.45) * (0.7 + 0.6 * glow), cr * open);
    c3 *= 0.78 + 0.22 * smoothstep(-0.9, 0.6, p.y);                                  // lit from above, darker low
    return float4(c3 * a * 0.85, a * 0.92);
}

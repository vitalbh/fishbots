// The arctic's far side and ceiling: an ice sheet over the surface, cracked, the light coming through it in soft
// shafts, and ice cliffs far away along the bottom, fading into the cold blue.
float4 draw_arctic_background(float2 uv, float t, float light, float2 gaze, float3 water, float4 extra) {
    float x = uv.x + gaze.x * 0.004;
    float4 out = float4(0.0);
    // ice cliffs along the bottom: tall, flat-topped, with vertical faces
    float h = extra.z + 0.04 + 0.08 * smoothstep(0.25, 0.75, vnoise(float2(x * 2.5, 1.1)));
    // a broken top: flat-topped blocks of different widths and heights, a little rough
    float bx = x * 9.0 + vnoise(float2(x * 3.0, 8.0)) * 2.0;
    h += 0.045 * mix(hash21(float2(floor(bx), 4.4)), hash21(float2(floor(bx) + 1.0, 4.4)), smoothstep(0.9, 1.0, fract(bx)))
       + 0.012 * vnoise(float2(x * 40.0, 3.3));
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
        // a few wide shafts leaning with the light, each its own strength, instead of an even curtain
        float sx = x + uv.y * 0.22;
        float s = pow(max(0.0, sin(sx * 9.0 + vnoise(float2(sx * 2.0, 1.0)) * 3.0)), 5.0)
                * smoothstep(0.35, 0.8, vnoise(float2(sx * 3.3 + t * 0.02, 6.0))) * 1.6;
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

// Gravel: a dark angular stone (extra.y varies its shape and shade).
float4 draw_arctic_gravel(float2 c, float t, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.0, 0.6);
    float s = extra.y;
    float d = sd_tri(p, float2(-0.8, -0.55), float2(0.75, -0.55), float2(-0.1 + 0.4 * s, -0.05 + 0.15 * s)) - 0.05;
    d = min(d, sd_box(p - float2(0.0, -0.45), float2(0.6, 0.12), 0.06));
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float3 c3 = mix(float3(0.28, 0.3, 0.33), float3(0.45, 0.47, 0.5), s) * (0.7 + 0.45 * smoothstep(-0.55, 0.0, p.y + 0.2 * p.x));
    c3 *= 0.9 + 0.2 * vnoise(p * 16.0 + s * 7.0);
    return float4(c3 * a, a);
}

// A chip of ice lying on the gravel: clear, faceted, catching the light.
float4 draw_arctic_ice_chip(float2 c, float t, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.0, 0.7);
    float d = sd_tri(p, float2(-0.6, -0.6), float2(0.6, -0.6), float2(0.1, 0.3)) - 0.06;
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float face = step(0.1 + (p.y + 0.6) * 0.1, p.x);
    float3 c3 = mix(float3(0.6, 0.8, 0.92), float3(0.9, 0.97, 1.0), face * 0.6 + 0.4 * smoothstep(-0.6, 0.3, p.y));
    c3 += float3(1.0) * (1.0 - smoothstep(0.0, 0.03, -d)) * 0.3;
    return float4(c3 * a * 0.85, a * 0.8);
}

// An ice crystal drifting (the arctic's marine snow): a small six-armed star, clear and bright at the tips.
float4 draw_arctic_crystal(float2 c, float t, float glow, float4 col, float4 extra) {
    float ang = t * (0.2 + extra.y * 0.4) + extra.y * 6.28;
    float2 p = float2(c.x * cos(ang) - c.y * sin(ang), c.x * sin(ang) + c.y * cos(ang));
    float r = length(p), th = atan2(p.y, p.x);
    float arm = abs(fract(th / 6.2832 * 6.0 + 0.5) - 0.5) * r * 6.2832 / 6.0;      // distance to the nearest arm
    float d = max(arm - 0.06, r - 0.9);
    float branches = max(abs(fract(r * 3.0) - 0.5) - 0.1, arm - 0.22) ;
    d = min(d, max(branches, r - 0.8));
    float a = (1.0 - smoothstep(-0.05, 0.05, d)) * 0.85;
    float3 c3 = mix(float3(0.75, 0.88, 1.0), float3(1.0), smoothstep(0.2, 0.9, r)) * (0.7 + 0.3 * col.rgb);
    return float4(c3 * a * col.a, a * col.a);
}

// The underside of an iceberg, coming down out of the ice ceiling: a huge irregular mass of ice, white-blue up top
// where the light comes through, with melt grooves and soft facets, deeper blue and fading toward its tip. Anchored at
// the surface (the water line is at p.y = 0.12 in size units); its top blends into the ceiling.
float4 draw_arctic_iceberg(float2 c, float t, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.3, 2.0);
    float top = -0.12, depth = 1.85;                                     // starts under the ceiling
    float k = clamp((top - p.y) / depth, 0.0, 1.0);                       // 0 at the top, 1 at the tip
    // the outline: each side its own lumps; wide up top, a bulge, then a blunt off-center tip
    float base = 1.12 * pow(1.0 - k, 0.75) + 0.06;
    float left = base * (0.8 + 0.35 * vnoise(float2(k * 3.2, 1.3)) + 0.18 * (vnoise(float2(k * 7.0, 3.3)) - 0.5));
    float right = base * (0.78 + 0.4 * vnoise(float2(k * 2.7, 6.1)) + 0.2 * (vnoise(float2(k * 6.5, 8.2)) - 0.5));
    float cx = 0.1 * sin(k * 3.0) - 0.05;
    float d = p.x < cx ? (cx - left) - p.x : p.x - (cx + right);
    d = max(d, -p.y - (depth - top) - 0.02 + 0.08 * vnoise(float2(p.x * 4.0, 3.0)));
    float aa = fwidth(d) * 2.5 + 0.01;                                     // soft: it's far away
    float a = 1.0 - smoothstep(-aa, aa, d);
    a *= smoothstep(top + 0.3, top - 0.05, p.y);                          // melts into the ceiling up top
    if (a <= 0.001) return float4(0.0);
    // soft facets: a voronoi of planes, each lit a little differently, their edges barely there
    float2 g = p * float2(1.6, 2.2) + float2(0.0, vnoise(p * 2.0) * 0.6);
    float2 cell = floor(g);
    float best = 1e3, second = 1e3, id = 0.0;
    for (int j = -1; j <= 1; j++) for (int i = -1; i <= 1; i++) {
        float2 o = cell + float2(i, j);
        float2 pt = o + float2(hash21(o), hash21(o + 4.7)) * 0.8 + 0.1;
        float dd = length(g - pt);
        if (dd < best) { second = best; best = dd; id = hash21(o + 9.1); }
        else if (dd < second) { second = dd; }
    }
    float edge = 1.0 - smoothstep(0.0, 0.05, second - best);
    float3 hi = float3(0.8, 0.93, 0.99), deep = float3(0.1, 0.32, 0.52);
    float3 c3 = mix(hi, deep, smoothstep(0.0, 0.85, k));
    c3 *= 0.9 + 0.16 * id;
    c3 += float3(0.6, 0.85, 1.0) * edge * 0.04 * (1.0 - k);
    // melt grooves running down it, and the light from the surface rippling over the upper part
    float groove = 0.5 + 0.5 * sin(p.x * 11.0 + vnoise(float2(p.x * 3.0, p.y * 0.8)) * 4.0);
    c3 *= 0.92 + 0.12 * groove;
    float caust = sin(p.x * 6.0 + t * 0.7) * sin(p.y * 4.0 - t * 0.5 + p.x * 1.7);
    c3 += float3(0.7, 0.9, 1.0) * max(0.0, caust) * 0.1 * (1.0 - k);
    // darker toward its far side, air bubbles caught in the ice, a bright rim where it meets the water
    c3 *= 0.85 + 0.25 * smoothstep(0.8, -0.8, p.x - cx);
    float bub = (1.0 - smoothstep(0.08, 0.16, length(fract(p * 13.0) - 0.5))) * step(0.94, hash21(floor(p * 13.0) + 2.3));
    c3 = mix(c3, float3(0.95, 1.0, 1.0), bub * 0.45 * (1.0 - k));
    c3 += float3(0.75, 0.92, 1.0) * (1.0 - smoothstep(0.0, 0.06, -d)) * 0.3 * (1.0 - 0.6 * k);
    c3 *= col.rgb;
    // far behind: the water between takes its color and some of its light
    c3 = mix(c3, float3(0.12, 0.28, 0.42) * col.rgb, 0.4);
    a *= mix(0.7, 0.32, k) * (1.0 - smoothstep(0.85, 1.0, k) * 0.6);
    return float4(c3 * a, a);
}

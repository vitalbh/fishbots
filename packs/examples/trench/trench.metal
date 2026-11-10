// Abyssal trench: the far walls in the dark, the black smoker, the tube worms, the sea pens and the whale fall.

// The trench far behind: two rows of basalt ridges and spires barely darker than the water, vents glowing orange
// at their feet, sparks of living light blinking in the distance, and darkness closing in overhead (it covers the
// surface: nothing of the day gets down here). uv 0…1 over the window (y up).
float4 draw_trench_background(float2 uv, float t, float light, float2 gaze, float3 water, float4 extra) {
    float4 o = float4(0.0);
    float asp = extra.x;
    for (int layer = 0; layer < 2; layer++) {
        float fl = float(layer);
        float x = (uv.x + gaze.x * (0.004 + 0.006 * fl)) * asp;
        float n = vnoise(float2(x * (2.2 + fl * 1.3) + fl * 17.0, 3.0));
        float n2 = vnoise(float2(x * 9.0 + fl * 5.0, 7.0));
        float sp = pow(vnoise(float2(x * (5.0 + fl * 2.0) + 40.0 * fl, 11.0)), 3.0);        // spires
        float h = extra.z + 0.04 + (0.24 - 0.09 * fl) * n + 0.03 * n2 + (0.26 - 0.1 * fl) * sp;
        float k = 1.0 - smoothstep(h - 0.004, h + 0.004, uv.y);
        float3 rock = mix(water, float3(0.0, 0.003, 0.01), 0.5 + 0.3 * fl);
        rock += float3(0.03, 0.075, 0.13) * exp(-max(h - uv.y, 0.0) * 40.0) * (0.8 - 0.3 * fl);   // a breath of light on the crest
        // a vent glowing at the foot of the ridge now and then
        float cell = floor(x * 1.3 + fl * 0.5), fx = fract(x * 1.3 + fl * 0.5);
        float hs = hash21(float2(cell, 5.0 + fl));
        float2 vd = float2((fx - 0.25 - 0.5 * hs) / 1.3, (uv.y - extra.z - 0.05 - 0.05 * hs) * 1.6);
        float vent = exp(-dot(vd, vd) * 900.0) * step(0.45, hs) * (0.7 + 0.3 * sin(t * 1.7 + hs * 40.0));
        rock += float3(1.0, 0.36, 0.08) * vent * (0.3 - 0.1 * fl);
        o = mix(o, float4(rock, 1.0), k);
    }
    // living light far away: sparks that blink and drift
    float2 g = float2(uv.x * asp * 46.0 + t * 0.05, uv.y * 46.0 - t * 0.03);
    float2 id = floor(g);
    float hsp = hash21(id);
    float blink = pow(0.5 + 0.5 * sin(t * (0.4 + hsp * 1.2) + hsp * 50.0), 8.0);
    float spark = step(0.95, hsp) * blink * (1.0 - smoothstep(0.0, 0.3, length(fract(g) - 0.5)));
    spark *= smoothstep(extra.z, extra.z + 0.1, uv.y) * (1.0 - o.a);
    float3 sc = mix(float3(0.25, 0.8, 1.0), float3(0.4, 1.0, 0.7), hash21(id + 7.0));
    o += float4(sc * spark * 0.5, spark * 0.3);
    // the dark overhead
    float dk = smoothstep(0.42, 0.93, uv.y);
    o = mix(o, float4(0.0, 0.002, 0.008, 1.0), dk * 0.97);
    return o;
}

// Black smoker: a chimney of sulfide minerals grown over a hydrothermal vent, a shorter spire beside it, cracks
// glowing with the heat inside, and a plume of black smoke billowing up, lit from below by the mouth.
// p = c * (0.7, 1.0); the ground at y ≈ -0.92. extra.y: the seed (the lean, the heights, which side the spire is on).
float4 draw_trench_smoker(float2 c, float t, float glow, float4 col, float4 extra) {
    float2 p = c * float2(0.7, 1.0);
    float seed = extra.y;
    float top = 0.0 + 0.12 * fract(seed * 3.7);
    float u = clamp((p.y + 0.92) / (top + 0.92), 0.0, 1.0);
    float lean = (fract(seed * 5.3) - 0.5) * 0.14;
    float cx = lean * u + 0.02 * sin(p.y * 7.0 + seed * 9.0);
    float w = mix(0.2, 0.06, pow(u, 0.8)) + 0.04 * (vnoise(float2(p.y * 8.0, seed * 20.0)) - 0.5)
            + 0.02 * (vnoise(float2(p.y * 22.0, seed * 7.0)) - 0.5);
    float spire = max(abs(p.x - cx) - w, max(p.y - top, -(p.y + 0.95)));
    float sd = fract(seed * 7.1) < 0.5 ? -1.0 : 1.0;
    float top2 = -0.5 + 0.2 * fract(seed * 2.3);
    float u2 = clamp((p.y + 0.92) / (top2 + 0.92), 0.0, 1.0);
    float cx2 = sd * (0.18 + 0.05 * u2);
    float w2 = mix(0.12, 0.04, u2) + 0.03 * (vnoise(float2(p.y * 10.0 + 5.0, seed * 11.0)) - 0.5);
    float side = max(abs(p.x - cx2) - w2, max(p.y - top2, -(p.y + 0.95)));
    float mound = max((length((p - float2(0.0, -0.95)) / float2(0.44, 0.17)) - 1.0) * 0.17, -(p.y + 0.95));
    float d = smin_k(smin_k(spire, side, 0.04), mound, 0.06);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);

    float3 hot = float3(1.0, 0.42, 0.08);
    float2 m = float2(lean + 0.02 * sin(top * 7.0 + seed * 9.0), top);           // the mouth
    float2 m2 = float2(sd * 0.23, top2);
    float flick = 0.8 + 0.2 * sin(t * 2.3 + seed * 20.0) * sin(t * 3.7);
    float3 c3 = float3(0.0);
    if (a > 0.001) {
        // rough dark rock, crusted with ochre and rust running down it
        c3 = col.rgb * (0.5 + 0.7 * vnoise(p * float2(14.0, 9.0) + seed * 30.0)) * (0.8 + 0.35 * vnoise(p * 42.0));
        float streak = smoothstep(0.5, 0.8, vnoise(float2(p.x * 26.0 + seed * 9.0, p.y * 3.0)));
        c3 = mix(c3, col.rgb * float3(2.3, 1.5, 0.55), streak * 0.45);
        c3 *= 0.5 + 0.6 * smoothstep(0.0, 0.07, -d);                              // round
        c3 *= 0.6 + 0.4 * smoothstep(-0.95, -0.7, p.y);                           // darker where it meets the ground
        // the heat: light from the mouths on the rock, and cracks glowing brighter the higher they are
        float heat = exp(-length(p - m) * 5.5) + 0.5 * exp(-length(p - m2) * 8.0);
        c3 += hot * heat * 0.5 * flick;
        float ve = vor_edge(p * float2(7.0, 5.0) + seed * 13.0);
        float crack = (1.0 - smoothstep(0.0, 0.022, ve)) * smoothstep(0.3, 0.62, vnoise(p * 3.5 + seed * 21.0));   // only some seams are open
        float up = smoothstep(-0.95, top, p.y);
        float ci = crack * (0.03 + 0.97 * up * up * up) * (0.65 + 0.35 * sin(t * 1.3 + p.y * 6.0 + seed * 8.0)) * step(d, -0.01);
        c3 += (hot * 1.6 + float3(0.3, 0.3, 0.1) * crack) * ci * (0.5 + 0.5 * glow);
    }
    // the smoke: rising, widening, curling
    float hy = p.y - top;
    float rise = clamp(hy / (0.97 - top), 0.0, 1.0);
    float px = m.x + sin(hy * 5.0 - t * 0.7 + seed * 6.0) * 0.07 * rise + 0.1 * rise * rise * sin(t * 0.2 + seed * 4.0);
    float pw = 0.05 + 0.2 * rise;
    float g = exp(-pow((p.x - px) / pw, 2.0) * 1.6);
    float n = vnoise(float2((p.x - px) * 9.0, hy * 6.0 - t * 0.9) + seed * 5.0) * 0.65
            + vnoise(float2((p.x - px) * 21.0, hy * 13.0 - t * 1.6)) * 0.35;
    float smoke = g * smoothstep(0.15, 0.55, n + 0.35 * (1.0 - rise)) * smoothstep(-0.03, 0.03, hy)
                * (1.0 - smoothstep(0.55, 1.0, rise)) * (1.0 - smoothstep(0.5, 0.68, abs(p.x)));
    float3 sc = mix(float3(0.11, 0.11, 0.14), float3(0.3, 0.3, 0.36), smoothstep(0.3, 0.8, n))          // billows catching what light there is
              + hot * (exp(-max(hy, 0.0) * 7.0) * 0.9 + exp(-max(hy, 0.0) * 2.2) * 0.25) * flick;
    float sa = smoke * 0.85;
    // the mouths' glow in the water
    float2 q = p - m, q2 = p - m2;
    float halo = (exp(-dot(q, q) * 70.0) * 0.7 + exp(-dot(q, q) * 12.0) * 0.16 + exp(-dot(q2, q2) * 140.0) * 0.35) * flick
               * (1.0 - smoothstep(0.5, 0.7, abs(p.x)));
    float3 rgb = c3 * a + (sc * sa + hot * halo) * (1.0 - a);
    return float4(rgb, a + (sa + halo * 0.4) * (1.0 - a) * (1.0 - sa * 0.0));
}

// Giant tube worms: a clump of pale tubes of different heights leaning out of the rock, each with a red plume that
// slides out to feed and back in. p = c * (1.2, 1.0); the ground at y ≈ -0.92.
float4 draw_trench_tubeworms(float2 c, float t, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.2, 1.0);
    float seed = extra.y;
    float dT = 1e3, dP = 1e3, px = 0.0, py = 0.0, tubeY = 0.0;
    for (int i = 0; i < 7; i++) {
        float fi = float(i);
        float h1 = hash21(float2(fi, seed * 31.0 + 1.0)), h2 = hash21(float2(fi + 9.0, seed * 17.0 + 2.0));
        float bx = (fi - 3.0) * 0.17 + (h1 - 0.5) * 0.1;
        float hgt = (0.45 + 0.95 * h2) * (1.0 - abs(fi - 3.0) * 0.13);
        float2 a0 = float2(bx, -0.95);
        float2 a1 = float2(bx * 1.55 + sin(t * 0.5 + fi * 1.7) * 0.015, -0.95 + hgt);
        float dt = sd_seg(p, a0, a1) - 0.045;
        if (dt < dT) { dT = dt; tubeY = (p.y + 0.95) / hgt; }
        float outp = smoothstep(-0.3, 0.6, sin(t * 0.45 + fi * 2.1 + seed * 5.0));
        float2 dir = normalize(a1 - a0);
        float2 q = p - (a1 + dir * (0.01 + 0.07 * outp));
        float2 ql = float2(dot(q, float2(dir.y, -dir.x)), dot(q, dir));
        float dp = (length(ql / float2(0.042 + 0.012 * outp, 0.035 + 0.085 * outp)) - 1.0) * 0.04;
        if (dp < dP) { dP = dp; px = ql.x; py = ql.y; }
    }
    float d = min(dT, dP);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    if (a <= 0.001) return float4(0.0);
    float3 c3;
    if (dT < aa) {
        // the tube: chalky, ringed, round, stained darker toward the base
        c3 = col.rgb * (0.82 + 0.18 * sin(p.y * 75.0 + p.x * 20.0));
        c3 *= 0.45 + 0.6 * smoothstep(0.0, 0.04, -dT);
        c3 *= 0.45 + 0.6 * smoothstep(0.0, 0.8, tubeY);
        c3 = mix(c3, col.rgb * float3(0.5, 0.42, 0.3), 0.35 * vnoise(p * 18.0));
    } else {
        // the plume: blood red, feathery
        c3 = float3(0.95, 0.1, 0.1) * (0.7 + 0.3 * sin(px * 260.0)) * (0.6 + 0.5 * smoothstep(-0.05, 0.08, py));
        c3 *= 0.55 + 0.75 * dot(col.rgb, float3(0.4));
    }
    c3 *= 0.55 + 0.45 * smoothstep(-0.95, -0.75, p.y);
    return float4(c3 * a, a);
}

// Sea pen: a quill standing in the mud, a soft stalk with a feather of polyps, and waves of light running up it.
// p = c * (0.6, 1.0); the ground at y ≈ -0.92. col: its light. glow: 1 in the dark.
float4 draw_trench_seapen(float2 c, float t, float glow, float4 col, float4 extra) {
    float2 p = c * float2(0.6, 1.0);
    float seed = extra.y;
    float up = smoothstep(-0.9, 0.9, p.y);
    p.x -= (sin(t * 0.6 + seed * 6.0) * 0.07 + (fract(seed * 4.3) - 0.5) * 0.22) * up * up;
    float stalk = sd_seg(p, float2(0.0, -0.95), float2(0.0, 0.72)) - mix(0.028, 0.008, up);
    float fu = clamp((p.y + 0.5) / 1.3, 0.0, 1.0);
    float wdt = 0.36 * pow(sin(fu * 3.14159), 0.7) * (1.0 - 0.35 * fu);
    float leaf = max(abs(p.x) - wdt, max(-0.5 - p.y, p.y - 0.8));
    float diag = p.y - abs(p.x) * 0.9;                                   // the branches slant up and out
    float barb = smoothstep(-0.3, 0.4, sin(diag * 60.0));
    float aa = fwidth(p.y) * 1.5 + 1e-4;
    float aS = 1.0 - smoothstep(-aa, aa, stalk);
    float aL = (1.0 - smoothstep(-aa, aa, leaf)) * barb * 0.85;
    float a = max(aS, aL);
    float3 hue = col.rgb / max(0.05, max(col.r, max(col.g, col.b)));
    float lit = 0.3 + 0.7 * glow;
    float wave = pow(0.5 + 0.5 * sin(diag * 7.0 - t * 1.6 + seed * 10.0), 4.0);
    float tip = smoothstep(wdt - 0.1, wdt, abs(p.x));
    float3 c3 = hue * (0.16 + 0.1 * up) + hue * lit * (0.25 + 0.9 * wave) * (0.45 + 0.55 * tip);
    c3 += float3(1.0) * lit * wave * tip * 0.35 * aL;
    c3 = mix(c3, hue * 0.22 + float3(0.05, 0.04, 0.05), aS * (1.0 - up) * 0.8);     // the fleshy foot
    float edge = 1.0 - smoothstep(0.6, 1.0, max(abs(c.x), abs(c.y)));
    float halo = lit * exp(-max(leaf, 0.0) * 16.0) * (0.25 + 0.5 * wave) * edge * step(-0.6, p.y);
    return float4(c3 * a + hue * halo * (1.0 - a) * 0.6, a + halo * (1.0 - a) * 0.3);
}

// Whale fall: what's left of a whale that sank here, the spine along the mud, the ribs arching up, the long skull;
// bones the deep is still feeding on, dotted with living light. p = c * (2.2, 0.7); the ground at y ≈ -0.63.
float4 draw_trench_whalefall(float2 c, float t, float glow, float4 col, float4 extra) {
    float2 p = c * float2(2.2, 0.7);
    float seed = extra.y;
    // the spine: a row of vertebrae sagging toward the tail
    float sy = -0.5 - 0.06 * smoothstep(0.5, -1.9, p.x);
    float spine = max(abs(p.y - sy) - (0.035 + 0.02 * abs(sin(p.x * 26.0))) * smoothstep(-2.05, -1.2, p.x), max(p.x - 1.1, -1.95 - p.x));
    // the ribs: half hoops leaning back, the tallest in the middle, one or two broken short
    float ribs = 1e3;
    for (int i = 0; i < 8; i++) {
        float fi = float(i);
        float hr = hash21(float2(fi, seed * 23.0 + 3.0));
        float2 q = p - float2(-0.85 + fi * 0.235, -0.5);
        q.x += q.y * 0.45;
        float hgt = (0.3 + 0.6 * sin(3.14159 * (fi + 1.2) / 9.5)) * (hr < 0.2 ? 0.5 : 1.0);
        float2 r = float2(0.15, hgt);
        float ring = abs(length(q / r) - 1.0) * 0.15 - 0.017 * (1.0 - 0.3 * q.y / hgt);
        ring = max(ring, -q.y);
        if (hr < 0.2) ring = max(ring, q.x);                              // a broken one: only its back half stands
        ribs = min(ribs, ring);
    }
    // the skull: a long beak, the brain case, an eye socket, the lower jaw lying beside it
    float skull = (length((p - float2(1.3, -0.36)) / float2(0.32, 0.2)) - 1.0) * 0.2;
    skull = smin_k(skull, sd_tri(p, float2(1.3, -0.2), float2(2.05, -0.52), float2(1.25, -0.55)) - 0.02, 0.06);
    skull = max(skull, -(length(p - float2(1.33, -0.38)) - 0.065));
    float jaw = sd_seg(p, float2(1.15, -0.6), float2(1.98, -0.59)) - 0.022;
    float d = min(min(spine, ribs), min(skull, jaw));
    d = max(d, -(p.y + 0.66));
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    if (a <= 0.001) return float4(0.0);
    float3 c3 = col.rgb * (0.75 + 0.3 * vnoise(p * float2(30.0, 40.0)));
    c3 *= 0.6 + 0.5 * smoothstep(0.0, 0.03, -d);
    c3 *= 0.5 + 0.6 * smoothstep(-0.66, -0.2, p.y);                        // sunk in the mud's shadow
    c3 = mix(c3, col.rgb * float3(0.45, 0.6, 0.5), 0.5 * smoothstep(0.5, 0.75, vnoise(p * 9.0 + seed * 7.0)));   // mats of bacteria
    // living light on the bones: specks that come and go
    float2 g = p * 26.0;
    float hs = hash21(floor(g) + seed * 50.0);
    float speck = step(0.8, hs) * (1.0 - smoothstep(0.1, 0.32, length(fract(g) - 0.5)))
                * pow(0.5 + 0.5 * sin(t * (0.5 + hs) + hs * 60.0), 3.0);
    c3 += mix(float3(0.3, 0.9, 1.0), float3(0.5, 1.0, 0.6), fract(hs * 9.0)) * speck * (0.35 + 0.65 * glow) * 0.9;
    return float4(c3 * a, a);
}

/// Drawings: what sits on the sand or passes far away (battery, rocks, shells, turtle, whale, corals, chest, wreck…).
let shaderScenery = #"""
// old battery lying in the sand: glow = charge (0…1), extra.y = plugged in.
// The part below the sand line disappears (stays buried).
float4 draw_battery(float2 c, float level, float phase, float4 extra, float2 world, float2 res) {
    float2 p = c * float2(1.2, 0.6);
    float body = sd_box(p - float2(-0.05, 0.0), float2(0.92, 0.42), 0.14);
    float cap = sd_box(p - float2(0.97, 0.0), float2(0.1, 0.17), 0.04);
    float d = min(body, cap);
    float aa = fwidth(d) + 1e-4;
    float inside = 1.0 - smoothstep(-aa, aa, d);

    // faded casing with rust
    float rust = vnoise(p * 9.0 + 3.1) * vnoise(p * 23.0);
    float3 shell = p.x > 0.35 ? float3(0.50, 0.34, 0.16) : float3(0.13, 0.13, 0.12);
    shell = mix(shell, float3(0.40, 0.22, 0.10), smoothstep(0.25, 0.55, rust) * 0.8);
    if (cap < 0.0) shell = float3(0.45, 0.43, 0.38);
    shell *= 0.7 + 0.4 * (p.y + 0.42);
    float3 col = shell;

    // single-color little window: the color alone tells the charge
    float window = sd_box(p - float2(-0.12, 0.02), float2(0.55, 0.16), 0.08);
    float3 tint = level < 0.2 ? float3(1.0, 0.28, 0.22) : level < 0.5 ? float3(1.0, 0.78, 0.25) : float3(0.35, 0.95, 0.45);
    float blink = level < 0.2 ? 0.45 + 0.55 * (0.5 + 0.5 * sin(phase * 5.0)) : 1.0;
    float bright = extra.y > 0.5 ? 0.8 + 0.2 * sin(phase * 3.0) : 0.7;
    col = mix(col, tint * bright * blink, 1.0 - smoothstep(-aa, aa, window));

    // buried: disappears below the sand and darkens near it (contact shadow)
    float ux = world.x / res.x;
    float sandY = (0.075 + 0.018 * sin(ux * 7.0 + 1.3) + 0.008 * sin(ux * 23.0)) * res.y;
    float aboveSand = smoothstep(sandY - 1.0, sandY + 1.0, world.y);
    col *= mix(0.45, 1.0, smoothstep(sandY, sandY + 7.0, world.y));
    inside *= aboveSand;

    float halo = 0.0;
    if (extra.y > 0.5) halo = exp(-max(d, 0.0) * 22.0) * (0.18 + 0.1 * sin(phase * 3.0)) * (1.0 - inside) * aboveSand
                              * (1.0 - smoothstep(0.6, 1.0, max(abs(c.x), abs(c.y))));
    return float4(col * inside + tint * halo, inside + halo * 0.5);
}

// ---------- scenery on the sand (rock, shell, chest); col is already lit ----------

// one stone of a rock: a lumpy ellipse; returns its distance (x) and a dome normal (yzw)
float4 rock_blob(float2 c, float2 at, float2 rad, float seed) {
    float2 q = (c - at) / rad;
    float ang = atan2(q.y, q.x);
    float wob = 1.0 + 0.07 * sin(ang * 3.0 + seed * 5.0) + 0.04 * sin(ang * 5.0 + seed * 11.0) + 0.025 * sin(ang * 9.0 + seed * 3.0);
    float l = length(q);
    float d = (l - wob) * min(rad.x, rad.y);
    float2 qn = q / wob;
    float3 n = normalize(float3(qn * 1.1, sqrt(max(0.02, 1.0 - dot(qn, qn)))));
    return float4(d, n);
}

float4 draw_rock(float2 c, float phase, float4 col) {
    float seed = phase;
    float side = fract(seed * 0.73) < 0.5 ? -1.0 : 1.0;          // which side the smaller stone leans on
    float4 b1 = rock_blob(c, float2(-0.1 * side, -0.16), float2(0.74, 0.76), seed);
    float4 b2 = rock_blob(c, float2(0.55 * side, -0.4), float2(0.38, 0.36), seed + 1.3);
    float4 b3 = rock_blob(c, float2(-0.68 * side, -0.52), float2(0.2, 0.13), seed + 2.1);   // a pebble
    float d12 = smin_k(b1.x, b2.x, 0.06);
    float d = min(d12, b3.x);
    d = max(d, -(c.y + 0.6));                                        // flat bottom, sunk in the sand
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float3 n = b1.x < b2.x ? b1.yzw : b2.yzw;
    if (b3.x < min(b1.x, b2.x)) n = b3.yzw;
    float crease = 1.0 - smoothstep(0.0, 0.05, min(b1.x, b2.x) - d12);  // where the two stones meet

    // a rough surface: the noise bends the normal a little
    float2 tp = c * 7.0 + seed * 13.0;
    float h0 = vnoise(tp), hx = vnoise(tp + float2(0.15, 0.0)), hy = vnoise(tp + float2(0.0, 0.15));
    n = normalize(n + float3(h0 - hx, h0 - hy, 0.0) * 0.7);
    float3 L = normalize(float3(-0.35, 0.85, 0.5));
    float diff = clamp(dot(n, L), 0.0, 1.0);
    float spec = pow(clamp(dot(reflect(-L, n), float3(0.0, 0.0, 1.0)), 0.0, 1.0), 18.0);

    float fine = vnoise(c * 23.0 + seed * 7.0);
    float3 alb = col.rgb * (0.82 + 0.3 * vnoise(c * 3.0 + seed * 4.0)) * (0.9 + 0.2 * fine);
    alb *= 1.0 + 0.08 * sin(c.y * 22.0 + vnoise(c * 4.0 + seed) * 4.0);               // faint layers in the stone
    // speckles: little light and dark grains
    float g = hash21(floor(c * 60.0 + seed * 17.0));
    alb = mix(alb, alb * 1.3 + 0.03, step(0.96, g) * 0.4);
    alb = mix(alb, alb * 0.6, step(g, 0.03) * 0.4);
    // cracks: thin dark lines where the noise crosses its middle
    float cr = abs(vnoise(c * 4.5 + seed * 9.0 + float2(vnoise(c * 9.0) * 0.6)) - 0.5);
    float crack = (1.0 - smoothstep(0.0, 0.02, cr)) * smoothstep(0.45, 0.7, vnoise(c * 2.0 + seed * 3.0));

    float3 c3 = alb * (float3(0.3, 0.36, 0.42) + float3(1.05, 1.0, 0.92) * diff) + float3(0.8, 0.9, 1.0) * spec * 0.1;
    c3 *= 1.0 - crack * 0.45;
    c3 *= 1.0 - crease * 0.4;
    // moss and algae on what faces up, with a ragged edge
    float up = n.y * 0.7 + (c.y + 0.6) * 0.35;
    float moss = smoothstep(0.7, 0.86, up + (vnoise(c * 9.0 + seed * 5.0) - 0.5) * 0.45);
    float3 mossC = mix(float3(0.3, 0.42, 0.26), col.rgb, 0.3) * (0.6 + 0.6 * diff) * (0.8 + 0.4 * fine) * (0.7 + dot(col.rgb, float3(0.3)));
    c3 = mix(c3, mossC, moss * 0.6);
    // the sand: darker where the stone sinks into it (ambient occlusion)
    c3 *= 0.55 + 0.45 * smoothstep(-0.62, -0.35, c.y);
    // the edge catches the light from above
    float edge = 1.0 - smoothstep(0.0, 0.04, -d);
    c3 += float3(0.7, 0.85, 0.95) * edge * clamp(n.y, 0.0, 1.0) * 0.18 * col.rgb * 2.0;
    return float4(c3 * a, a);
}

float4 draw_shell(float2 c, float phase, float4 col) {
    float2 p = c - float2(0.0, -0.62);
    float th = atan2(p.x, p.y);                                       // 0 = straight up from the hinge
    float r = length(p);
    float edge = 1.3 + 0.06 * cos(th * 13.0);                         // scalloped rim
    float fan = max((r - edge) * 0.8, (abs(th) - 1.12) * 0.6);
    float ears = sd_box(p - float2(0.0, 0.06), float2(0.34, 0.1), 0.03);
    float d = max(min(fan, ears), -(c.y + 0.72));
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float ribs = 0.5 + 0.5 * cos(th * 13.0);
    float3 base = col.rgb * (0.68 + 0.32 * ribs) * (0.72 + 0.38 * clamp(r / 1.3, 0.0, 1.0));
    base += col.rgb * pow(ribs, 6.0) * 0.25 * smoothstep(0.3, 1.2, r);   // nacre sheen on the ribs
    return float4(base * a, a);
}

// the oyster (the big shell of the scenery): a rough, lumpy shell lying on the sand, a little open now and then,
// with a pearl peeking out of the gap. t: time.
float4 draw_oyster(float2 c, float t, float4 col) {
    float open = 0.05 + 0.06 * smoothstep(0.3, 1.0, sin(t * 0.21));
    float xn = c.x / 0.84;
    float wav = 0.035 * sin(c.x * 17.0 + 1.0) + 0.02 * sin(c.x * 37.0 + 2.0);       // the frilly lip
    float rimL = -0.36 + wav;
    float rimU = rimL + open * max(0.0, 1.0 - xn * xn) + 0.01;
    // the valves: a lumpy dome on top (lifted by `open`) and a shallow bowl below
    float lump = 0.09 * vnoise(c * 3.5 + 3.0) + 0.03 * vnoise(c * 11.0);
    float2 uq = (c - float2(0.04, rimU - 0.02)) / float2(0.8 + lump, 0.62 + lump);
    float upper = max(length(uq) - 1.0, rimU - c.y);
    float2 lq = (c - float2(0.0, rimL + 0.02)) / float2(0.88 + lump, 0.3);
    float lower = max(length(lq) - 1.0, c.y - rimL);
    float gapIn = max(length((c - float2(0.0, -0.36)) / float2(0.82, 0.4)) - 1.0, max(c.y - rimU, rimL - c.y));
    float shellD = min(min(upper, lower), gapIn);
    float d = max(shellD, -(c.y + 0.72));                                              // half sunk in the sand
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);

    float3 base = col.rgb;
    float3 L3 = normalize(float3(-0.3, 0.85, 0.45));
    float3 c3;
    if (upper <= 0.0) {
        // the top valve: growth lines parallel to the lip, ribs from the hinge, rough and a little purple at the lip
        float topY = rimU - 0.02 + (0.62 + lump) * sqrt(max(0.0, 1.0 - uq.x * uq.x));
        float v = clamp((c.y - rimU) / max(topY - rimU, 0.01), 0.0, 1.0);
        float3 n = normalize(float3(uq.x, uq.y, sqrt(max(0.02, 1.0 - dot(uq, uq)))));
        float2 tp = c * 9.0;
        float h0 = vnoise(tp), hx = vnoise(tp + float2(0.2, 0.0)), hy = vnoise(tp + float2(0.0, 0.2));
        n = normalize(n + float3(h0 - hx, h0 - hy, 0.0) * 1.2);
        float diff = clamp(dot(n, L3), 0.0, 1.0);
        float growth = 0.5 + 0.5 * sin(v * 22.0 + vnoise(c * 3.0) * 7.0 + vnoise(c * 9.0) * 2.0);
        float ribs = 0.5 + 0.5 * sin(atan2(c.x, 0.2 - c.y) * 16.0 + vnoise(c * 4.0) * 2.0);
        float3 alb = base * (0.86 + 0.14 * growth) * (0.88 + 0.14 * ribs) * (0.85 + 0.3 * vnoise(c * 3.0 + 1.0));
        alb = mix(alb, alb * float3(0.85, 0.72, 0.9), (1.0 - smoothstep(0.0, 0.3, v)) * 0.6);     // purplish near the lip
        // a few barnacles and specks of algae
        float2 bc = floor(c * 7.0);
        float2 bp = fract(c * 7.0) - 0.5 - (float2(hash21(bc), hash21(bc + 4.0)) - 0.5) * 0.5;
        float bar = step(0.9, hash21(bc + 9.0)) * (1.0 - smoothstep(0.1, 0.16, length(bp))) * step(0.25, v);
        alb = mix(alb, base * 1.25 + 0.08, bar * 0.7);
        alb = mix(alb, float3(0.3, 0.42, 0.28) * dot(base, float3(0.6)), smoothstep(0.6, 0.85, vnoise(c * 4.0 + 7.0)) * smoothstep(0.4, 0.9, v) * 0.5);
        c3 = alb * (float3(0.32, 0.36, 0.42) + float3(1.0, 0.97, 0.9) * diff);
        c3 += float3(0.8, 0.9, 1.0) * (1.0 - smoothstep(0.0, 0.04, -upper)) * smoothstep(0.3, 1.0, v) * 0.15;   // rim light
        c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.035, c.y - rimU)) * 0.3;                         // the lip's edge
    } else if (lower <= 0.0) {
        // the bottom valve: mostly in shade, with vertical ribs
        float ribs = 0.5 + 0.5 * sin(c.x * 26.0 + vnoise(c * 5.0) * 2.0);
        c3 = base * (0.42 + 0.14 * ribs) * (0.8 + 0.3 * vnoise(c * 8.0)) * (0.7 + 0.5 * smoothstep(-0.7, rimL, c.y));
        c3 = mix(c3, base * 0.85 + 0.12, (1.0 - smoothstep(0.0, 0.03, rimL - c.y)) * 0.6);    // its lip catches the light
    } else {
        // the gap: dark inside, a gleam of nacre along the lips, and the pearl
        float g = clamp((c.y - rimL) / max(rimU - rimL, 0.005), 0.0, 1.0);
        float3 nacre = 0.7 + 0.3 * cos(6.2831 * (c.x * 1.5 + float3(0.0, 0.33, 0.67)));
        c3 = mix(base * 0.08, nacre * 0.55, pow(1.0 - g, 3.0) * 0.8 + pow(g, 4.0) * 0.3);
        float2 pp = (c - float2(0.08, rimL + 0.035)) / 0.075;
        float pr = length(pp);
        if (pr < 1.0) {
            float nz = sqrt(1.0 - pr * pr);
            float3 pc = float3(0.95, 0.92, 0.86) * (0.45 + 0.55 * nz) + 0.6 * exp(-dot(pp - float2(-0.35, 0.4), pp - float2(-0.35, 0.4)) * 6.0);
            c3 = mix(c3, pc, 1.0 - smoothstep(0.85, 1.0, pr));
        }
    }
    c3 *= 0.6 + 0.4 * smoothstep(-0.74, -0.5, c.y);                                    // shadowed where it meets the sand
    return float4(c3 * a, a);
}

// distance to the nearest border between voronoi cells (for lace and meshes)
float vor_edge(float2 x) {
    float2 n = floor(x), f = fract(x), mr = float2(0.0), mg = float2(0.0);
    float md = 8.0;
    for (int j = -1; j <= 1; j++) for (int i = -1; i <= 1; i++) {
        float2 g = float2(i, j), o = float2(hash21(n + g), hash21(n + g + 17.3));
        float2 r = g + o - f;
        float dd = dot(r, r);
        if (dd < md) { md = dd; mr = r; mg = g; }
    }
    md = 8.0;
    for (int j = -2; j <= 2; j++) for (int i = -2; i <= 2; i++) {
        float2 g = mg + float2(i, j), o = float2(hash21(n + g), hash21(n + g + 17.3));
        float2 r = g + o - f;
        if (dot(mr - r, mr - r) > 1e-5) md = min(md, dot(0.5 * (mr + r), normalize(r - mr)));
    }
    return md;
}

// turtle in profile, facing +x: a domed shell of plates, a pale belly, a beaked head and long flippers that row
float4 draw_turtle(float2 c, float phase, float4 col) {
    float2 p = c * float2(1.3, 0.9);
    float paddle = sin(phase * 2.2);
    // shell: a dome, its plates the cells of a voronoi on its surface, a ring of small plates along the rim
    float2 sq = (p - float2(-0.02, -0.04)) / float2(0.62, 0.42);
    float carapace = max(length(sq) - 1.0, -(sq.y + 0.12)) * 0.38;
    float bellyD = max(length((p - float2(0.0, -0.06)) / float2(0.6, 0.15)) - 1.0, p.y + 0.03) * 0.14;
    // head and neck, and the flippers: tapered, curved paddles hinged at the shoulder and the hip
    float headD = length((p - float2(0.76, 0.02)) / float2(0.19, 0.13)) - 1.0;
    headD *= 0.13;
    float2 n0 = float2(0.45, -0.02), n1 = float2(0.66, 0.01), pa = p - n0, ba = n1 - n0;
    float neck = length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0)) - 0.085;
    float fang = -0.95 + paddle * 0.45;
    float2 fq = p - float2(0.3, -0.1);
    fq = float2(fq.x * cos(fang) + fq.y * sin(fang), -fq.x * sin(fang) + fq.y * cos(fang));
    float ft = clamp(fq.x / 0.62, 0.0, 1.0);
    float front = max(abs(fq.y - 0.06 * sin(ft * 3.1416)) - 0.075 * (1.0 - ft * 0.8), -fq.x);
    front = max(front, fq.x - 0.62);
    float bang = -2.6 - paddle * 0.25;
    float2 bq = p - float2(-0.42, -0.1);
    bq = float2(bq.x * cos(bang) + bq.y * sin(bang), -bq.x * sin(bang) + bq.y * cos(bang));
    float bt = clamp(bq.x / 0.3, 0.0, 1.0);
    float back = max(max(abs(bq.y) - 0.07 * (1.0 - bt * 0.6), -bq.x), bq.x - 0.3);
    float skin = min(min(headD, neck), min(front, back));
    float d = min(min(carapace, bellyD), skin);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);

    float3 base = col.rgb;
    float3 L3 = normalize(float3(-0.3, 0.85, 0.45));
    float3 c3;
    if (carapace <= 0.0) {
        float3 n = normalize(float3(sq, sqrt(max(0.03, 1.0 - dot(sq, sq)))));
        float diff = clamp(dot(n, L3), 0.0, 1.0);
        float rimBand = smoothstep(0.78, 0.84, length(sq));
        float2 sm = rimBand > 0.5 ? float2(atan2(sq.y, sq.x) * 6.0, 0.5) : sq / (0.6 + 0.4 * n.z) * 2.2;
        float e = vor_edge(sm + 3.0);
        float seam = 1.0 - smoothstep(0.02, 0.07, e);
        float plate = smoothstep(0.0, 0.35, e);                                  // lighter toward each plate's middle
        float3 alb = base * (0.7 + 0.35 * plate) * (0.85 + 0.3 * vnoise(sq * 6.0 + 2.0));
        alb = mix(alb, base * float3(1.15, 0.95, 0.65), plate * 0.25 * vnoise(sq * 3.0));   // warm patches (tortoiseshell)
        c3 = alb * (0.38 + 0.8 * diff) * (1.0 - seam * 0.5);
        c3 += float3(0.75, 0.9, 1.0) * (1.0 - smoothstep(0.0, 0.03, -carapace)) * smoothstep(0.0, 0.8, sq.y) * 0.18;
    } else if (bellyD <= 0.0 && skin > 0.0) {
        c3 = mix(base, float3(0.85, 0.8, 0.55), 0.6) * 0.75;                     // the pale belly
        c3 *= 1.0 - 0.2 * step(0.85, fract(p.x * 7.0));
    } else {
        // skin: greenish, covered in small pale-edged scales, lighter underneath
        float3 sk = float3(0.5, 0.58, 0.42) * (base.g / 0.55);
        float e = vor_edge(p * 16.0);
        sk *= 0.75 + 0.3 * smoothstep(0.02, 0.2, e);
        sk = mix(sk, sk * 0.6 + 0.25, (1.0 - smoothstep(0.02, 0.06, e)) * 0.4);
        c3 = sk * (0.75 + 0.35 * smoothstep(-0.3, 0.2, p.y));
        // the head: a beak line and an eye
        if (headD < 0.0) {
            float beak = abs(p.y - 0.0 + (p.x - 0.86) * 0.25) - 0.006;
            c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.01, beak)) * step(0.8, p.x) * 0.6;
            float re = length(p - float2(0.82, 0.055));
            c3 = mix(c3, c3 * 0.5, 1.0 - smoothstep(0.035, 0.05, re));
            c3 = mix(c3, float3(0.03), 1.0 - smoothstep(0.022, 0.03, re));
            c3 = mix(c3, float3(1.0), 1.0 - smoothstep(0.004, 0.009, length(p - float2(0.826, 0.064))));
        }
    }
    c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.025, -d)) * 0.3;                         // a darker outline
    return float4(c3 * a, a);
}

// whale in the distance: a humpback's silhouette, soft with the distance, darker on top, with long flippers and flukes
float4 draw_whale(float2 c, float phase, float4 col) {
    float2 p = c * float2(2.2, 0.7);
    float flex = sin(phase * 0.6);
    p.y -= flex * 0.06 * smoothstep(0.0, -1.8, p.x);                           // the tail half bends
    float thin = mix(0.28, 1.0, smoothstep(-1.6, 0.4, p.x));
    float body = (length((p - float2(0.15, 0.0)) / float2(1.45, 0.34 * thin)) - 1.0) * 0.3;
    body = smin_k(body, (length((p - float2(1.1, -0.05)) / float2(0.5, 0.26)) - 1.0) * 0.2, 0.08);   // the big head
    // flukes: two lobes at the end of the tail stock
    float2 fp = p - float2(-1.5, 0.0);
    float fl = min(sd_tri(fp, float2(0.12, 0.0), float2(-0.38, 0.22 + flex * 0.05), float2(-0.3, 0.02)),
                   sd_tri(fp, float2(0.12, 0.0), float2(-0.36, -0.2 + flex * 0.05), float2(-0.28, -0.02))) - 0.02;
    // a long pectoral flipper, slowly rowing, and a small dorsal hump
    float fa = -0.5 + sin(phase * 0.4) * 0.12;
    float2 pq = p - float2(0.55, -0.2);
    pq = float2(pq.x * cos(fa) + pq.y * sin(fa), -pq.x * sin(fa) + pq.y * cos(fa));
    float flip = (length((pq - float2(-0.4, 0.0)) / float2(0.45, 0.07)) - 1.0) * 0.07;
    float hump = (length((p - float2(-0.6, 0.17)) / float2(0.14, 0.06)) - 1.0) * 0.06;
    float d = min(min(smin_k(body, hump, 0.05), fl), flip);
    float a = 1.0 - smoothstep(-0.03, 0.05, d);                                    // soft edges: it's far away
    // darker back, a lighter throat with grooves, a faint eye
    float3 c3 = col.rgb * (0.8 + 0.5 * smoothstep(0.2, -0.3, p.y));
    float throat = smoothstep(-0.05, -0.25, p.y) * smoothstep(0.0, 0.8, p.x) * step(body, 0.0);
    c3 = mix(c3, c3 * 1.35, throat * (0.6 + 0.4 * step(0.5, fract(p.y * 30.0))));
    c3 += col.rgb * 0.25 * (1.0 - smoothstep(0.0, 0.04, -d)) * smoothstep(-0.1, 0.3, p.y);
    c3 *= 1.0 - 0.5 * (1.0 - smoothstep(0.02, 0.04, length(p - float2(0.85, -0.08))));
    float aw = a * 0.6;
    return float4(c3 * aw, aw);
}

// corals on the sand (scenery). The sand line is at y = -0.3; `seed` picks the shape and varies it a little.
float4 draw_coral(float2 c, float seed, float t, float4 col) {
    float2 p = c;
    int kind = int(seed) % 3;
    float h = fract(seed) * 6.0;
    float d = 1e3;
    float cover = -1.0;                 // set directly by shapes whose edges aren't a clean distance (the fan's lace)
    float3 c3 = col.rgb;
    if (kind == 0) {
        // branching: a short trunk and forking branches with rounded tips, swaying a little
        d = sd_seg(p, float2(0.0, -0.35), float2(0.0, -0.05)) - 0.075;
        for (int i = 0; i < 5; i++) {
            float fi = float(i);
            float a = -0.95 + 0.47 * fi + sin(h + fi * 2.1) * 0.12;
            float2 s0 = float2(0.0, -0.08 + 0.05 * fmod(fi, 2.0));
            float len = 0.5 + 0.18 * fract(sin(h * 7.0 + fi * 3.3) * 43.7);
            float2 e = s0 + float2(sin(a), cos(a)) * len;
            e.x += sin(t * 0.7 + fi + h) * 0.03;
            d = min(d, sd_seg(p, s0, e) - 0.055);
            float2 m = mix(s0, e, 0.55);
            float2 e2 = m + float2(sin(a + 0.55), cos(a + 0.55)) * len * 0.42;
            e2.x += sin(t * 0.7 + fi + h + 1.0) * 0.03;
            d = min(d, sd_seg(p, m, e2) - 0.042);
        }
        c3 *= 0.65 + 0.5 * smoothstep(-0.3, 0.8, p.y);                   // lighter toward the tips
        float polyp = step(0.8, vnoise(p * 24.0 + h));
        c3 = mix(c3, c3 * 1.35 + 0.08, polyp * 0.6);
    } else if (kind == 1) {
        // sea fan: a wide lacy fan on a short stem, waving slowly
        // a gorgonian: an irregular mesh of fine twigs (the edges of a stretched voronoi) over a few thicker
        // branches rising from the stem; the outline is ragged, and the twigs thin out toward the rim
        float2 q = p;
        q.x -= sin(t * 0.6 + h) * 0.035 * (p.y + 0.3);
        float2 o = q + float2(0.0, 0.3);
        float rad = length(o);
        float ang = atan2(o.x, o.y);
        float rim = 1.0 + 0.08 * (vnoise(float2(ang * 6.0, h)) - 0.5) + 0.04 * sin(ang * 11.0 + h);
        float fan = (length((q - float2(0.0, 0.28)) / float2(0.85 * rim, 0.62 * rim)) - 1.0) * 0.5;
        fan = max(fan, -0.12 - q.y);
        float outer = smoothstep(0.2, 1.1, rad);
        float2 mp = float2(ang * 6.5, rad * 13.0) + float2(vnoise(q * 4.0 + h), vnoise(q * 4.0 + h + 5.0)) * 0.8;
        float edge = vor_edge(mp);
        float aw = fwidth(edge) + 1e-4;
        float twigW = mix(0.1, 0.05, outer);
        float mesh = 1.0 - smoothstep(twigW - aw, twigW + aw, edge);
        // the main branches: a few wavy ribs fanning out from the stem
        float wa = ang + (vnoise(float2(rad * 4.0, h * 3.0)) - 0.5) * 0.25;
        float rib = abs(fract(wa * 1.6 + 0.5) - 0.5) / 1.6 * rad;
        float ribW = mix(0.03, 0.012, outer);
        float ar = fwidth(rib) + 1e-4;
        float ribs = (1.0 - smoothstep(ribW - ar, ribW + ar, rib)) * (1.0 - smoothstep(0.75, 1.0, rad));
        float afan = fwidth(fan) + 1e-4;
        float inFan = (1.0 - smoothstep(-afan, afan, fan)) * max(mesh, ribs);
        float stem = sd_seg(p, float2(0.0, -0.35), float2(0.0, -0.08)) - 0.05;
        float ast = fwidth(stem) + 1e-4;
        cover = max(inFan, 1.0 - smoothstep(-ast, ast, stem));
        c3 *= 0.6 + 0.5 * smoothstep(-0.3, 0.9, p.y);
        c3 *= 0.85 + 0.3 * vnoise(q * 6.0 + h);                         // patchy color
        c3 = mix(c3, c3 * 1.3 + 0.06, ribs * 0.35);                     // the thick branches catch more light
        c3 = mix(c3, c3 * 1.35 + 0.1, step(0.86, vnoise(q * 30.0 + h)) * 0.6);   // polyps
    } else {
        // brain coral: a dome with winding grooves
        // brain coral: a lumpy dome covered in meandering ridges, the grooves crowding toward its rim
        float2 q = (p - float2(0.0, -0.32)) / float2(0.78, 0.62);
        float lumpy = 0.04 * vnoise(float2(atan2(q.x, q.y) * 3.0, h));
        d = max((length(q) - 1.0 - lumpy) * 0.5, -0.33 - p.y);
        float nz = sqrt(max(0.05, 1.0 - dot(q, q)));
        float2 m = q / pow(nz, 0.6) * 2.2 + h;                              // the dome's surface, stretched near the rim
        // meanders: the grooves are where two warped noises cross their middle, winding lines all over the dome
        float2 wq = m * 4.2 + float2(vnoise(m * 1.5), vnoise(m * 1.5 + 5.0)) * 2.0;
        float g1 = abs(vnoise(wq) - 0.5), g2 = abs(vnoise(wq * 1.9 + 11.0) - 0.5);
        float gv = min(g1 * 1.3, g2 * 1.9);
        float ridge = smoothstep(0.0, 0.16, gv);
        float valley = smoothstep(0.0, 0.35, ridge);
        float3 n = normalize(float3(q, nz));
        float diff = clamp(dot(n, normalize(float3(-0.3, 0.8, 0.5))), 0.0, 1.0);
        c3 *= (0.42 + 0.75 * diff) * (0.4 + 0.6 * valley);
        c3 = mix(c3, c3 * 1.25 + 0.04, smoothstep(0.75, 1.0, ridge) * 0.5);  // the ridge tops
        c3 *= 0.9 + 0.2 * vnoise(q * 8.0 + h);
    }
    float aa = fwidth(d) + 1e-4;
    float inside = cover >= 0.0 ? cover : 1.0 - smoothstep(-aa, aa, d);
    // the sand line hides the base
    inside *= smoothstep(-0.36, -0.3, p.y);
    return float4(c3 * inside, inside) * col.a;
}

// `open` (0…1): the lid rises and tips back, showing a heap of gold coins inside
float4 draw_chest(float2 c, float phase, float glow, float4 col, float open) {
    float2 p = c;
    float body = sd_box(p - float2(0.0, -0.33), float2(0.78, 0.37), 0.04);
    float2 q = p - float2(0.0, 0.11 + open * 0.34);
    q.y /= 1.0 - open * 0.5;                                                // tipping back: seen from the front, it gets shorter
    float lid = max((length(q / float2(0.82, 0.42)) - 1.0) * 0.35, -q.y);   // rounded lid, a bit open
    float d = min(body, lid);
    float aa = fwidth(d) + 1e-4;
    float inside = 1.0 - smoothstep(-aa, aa, d);
    // wood: planks with grain, each its own shade; the lid's planks bend over its curve
    bool onLid = lid < body;
    float pv = onLid ? asin(clamp(q.y / 0.42, 0.0, 1.0)) / 1.5708 * 4.0 + 10.0 : (p.y + 1.0) * 5.5;   // the lid's planks run along it, crowding toward the top
    float plank = floor(pv);
    float seam = 1.0 - smoothstep(0.0, 0.07, min(fract(pv), 1.0 - fract(pv)));
    float grain = vnoise(float2(p.x * 3.0 + plank * 5.0, fract(pv) * 6.0 + plank * 3.0));
    float3 wood = col.rgb * (0.82 + 0.25 * hash21(float2(plank, onLid ? 1.0 : 0.0))) * (0.85 + 0.25 * grain);
    wood *= 1.0 - seam * 0.45;
    // light from above: the lid's curve is lit on top, the body darker toward the sand
    float lidN = clamp(q.y / 0.42, 0.0, 1.0);
    wood *= onLid ? (0.7 + 0.45 * lidN) : (0.62 + 0.38 * smoothstep(-0.7, 0.05, p.y));
    wood = mix(wood, wood * float3(0.75, 0.9, 0.7), smoothstep(0.62, 0.85, vnoise(p * 4.0 + 2.0)) * 0.4);   // old algae stains
    // iron: two straps over body and lid, a band along the body, corner caps; shaded, with rivets
    float3 metal = float3(0.5, 0.45, 0.36) * dot(col.rgb, float3(0.9));
    float strapX = abs(abs(p.x) - 0.5);
    float band = max(step(strapX, 0.06), step(abs(p.y + 0.3), 0.045) * step(p.y, 0.04));
    band = max(band, step(0.68, abs(p.x)) * step(p.y, 0.04) * step(abs(p.y + 0.33), 0.33) * step(abs(p.y + 0.33), 0.33));
    float mshade = 0.75 + 0.4 * (1.0 - strapX / 0.06) * step(strapX, 0.06) + 0.25 * smoothstep(-0.7, 0.4, p.y);
    float2 rv = float2(strapX, fract((p.y + 1.0) * 6.0) - 0.5);
    float rivet = (1.0 - smoothstep(0.018, 0.028, length(float2(rv.x, rv.y / 6.0)))) * step(p.y, 0.02);
    float3 c3 = mix(wood, metal * mshade + rivet * 0.25, band);
    c3 *= 1.0 - band * (1.0 - smoothstep(0.0, 0.015, 0.06 - strapX)) * step(strapX, 0.06) * 0.3;   // the strap's edges
    // the lock: a brass plate with a keyhole
    float plate = sd_box(p - float2(0.0, -0.02), float2(0.085, 0.1), 0.025);
    float key = min(length(p - float2(0.0, 0.0)) - 0.022, sd_box(p - float2(0.0, -0.04), float2(0.01, 0.03), 0.0));
    float3 brass = float3(0.85, 0.66, 0.3) * dot(col.rgb, float3(0.8)) * 1.3 * (0.8 + 0.4 * smoothstep(-0.12, 0.08, p.y));
    c3 = mix(c3, brass, 1.0 - step(0.0, plate));
    c3 = mix(c3, float3(0.04), (1.0 - step(0.0, key)) * (1.0 - step(0.0, plate)));
    // dark along the outline, so the box reads as a solid
    c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.04, -d)) * 0.35;
    // treasure glow through the gap under the lid
    float pulse = (0.55 + 0.45 * sin(phase * 1.3)) * glow;
    float gap = (1.0 - smoothstep(0.0, 0.035, abs(p.y - 0.075))) * step(abs(p.x), 0.74);
    float halo = exp(-max(p.y - 0.08, 0.0) * 6.0) * step(0.075, p.y) * (1.0 - smoothstep(0.5, 0.9, abs(p.x))) * 0.35;
    float3 gold = float3(1.0, 0.8, 0.35);
    float a = max(inside, (gap + halo) * pulse);
    float3 outc = c3 * inside + gold * (gap * 1.2 + halo) * pulse;
    if (open > 0.01) {
        // the inside: the dark back wall between the rim and the raised lid
        float back = step(abs(p.x), 0.76) * step(0.0, p.y) * step(p.y, 0.1 + open * 0.34) * (1.0 - inside);
        outc = mix(outc, col.rgb * 0.3 * (0.8 + 0.2 * step(fract(p.x * 6.0), 0.9)), back);
        a = max(a, back);
        // the treasure: a heap of coins over the rim, glittering, and the light pouring out of it
        float heapTop = 0.04 + open * 0.27 * (1.0 - pow(p.x / 0.74, 2.0));
        float heap = step(abs(p.x), 0.74) * step(p.y, heapTop) * step(-0.02, p.y) * step(body, 0.02);
        float2 cg = p * float2(14.0, 18.0);
        float coin = 1.0 - smoothstep(0.25, 0.42, length(fract(cg + float2(floor(cg.y) * 0.5, 0.0)) - 0.5));
        float twinkle = pow(max(0.0, sin(phase * 3.0 + floor(cg.x) * 1.7 + floor(cg.y) * 2.3)), 8.0);
        float3 goldC = mix(float3(0.85, 0.6, 0.18), float3(1.0, 0.88, 0.45), coin) + float3(1.0) * twinkle * 0.6;
        outc = mix(outc, goldC, heap * (1.0 - step(lid, 0.0)));
        float shine = exp(-max(p.y - heapTop, 0.0) * 5.0) * step(heapTop, p.y) * step(abs(p.x), 0.8) * (1.0 - step(lid, 0.0)) * open * 0.55;
        outc += float3(1.0, 0.8, 0.4) * shine;
        a = max(a, max(heap, shine));
    }
    return float4(outc, min(a, 1.0));
}

// a ship's safe (the deep sea's chest): heavy riveted iron gone rusty, a door with a dial and a wheel handle; it
// swings open (open: 0…1) on the gold inside. Sand line at y ≈ -0.3 like the chest's.
float4 draw_safe(float2 c, float phase, float glow, float4 col, float open) {
    float2 p = c;
    float body = sd_box(p - float2(0.0, -0.2), float2(0.62, 0.5), 0.05);
    float aa = fwidth(body) + 1e-4;
    float inside = 1.0 - smoothstep(-aa, aa, body);
    float lum = dot(col.rgb, float3(0.33)) / 0.33;                               // the scene's light
    // iron: dark green-grey, rust blooming from the edges and the rivets, light from above
    float edge = smoothstep(0.12, 0.0, -body);
    float rustN = vnoise(p * 7.0) * 0.6 + vnoise(p * 21.0) * 0.4;
    float rust = smoothstep(0.5, 0.75, rustN + edge * 0.35);
    float3 iron = mix(float3(0.17, 0.19, 0.19), float3(0.36, 0.2, 0.11), rust) * (0.8 + 0.35 * vnoise(p * 45.0));
    iron *= 0.65 + 0.45 * smoothstep(-0.7, 0.3, p.y);
    iron += float3(0.12) * (1.0 - smoothstep(0.0, 0.04, abs(p.y - 0.27))) * step(abs(p.x), 0.6);   // the top edge catches light
    // the door: an inset panel, hinged on the right; it swings open, getting narrower as seen from the front
    float sw = 1.0 - 0.85 * clamp(open, 0.0, 1.0);
    float dl = 0.46 - 0.92 * sw;
    float2 dc = float2((dl + 0.46) * 0.5, -0.2);
    float door = sd_box(p - dc, float2(0.46 * sw, 0.4), 0.03);
    float hole = sd_box(p - float2(0.0, -0.2), float2(0.47, 0.41), 0.03);
    float inHole = (1.0 - smoothstep(-aa, aa, hole)) * inside;
    float inDoor = (1.0 - smoothstep(-aa, aa, door)) * inside;
    float3 c3 = iron;
    // behind the door: the dark inside, gold stacked at the bottom glittering, and its light
    float pulse = (0.6 + 0.4 * sin(phase * 1.3)) * glow;
    float2 cg = p * float2(12.0, 16.0);
    float coin = 1.0 - smoothstep(0.25, 0.42, length(fract(cg + float2(floor(cg.y) * 0.5, 0.0)) - 0.5));
    float twinkle = pow(max(0.0, sin(phase * 3.0 + floor(cg.x) * 1.7 + floor(cg.y) * 2.3)), 8.0);
    float heap = step(p.y, -0.42 + 0.12 * (1.0 - pow(p.x / 0.47, 2.0)));
    float3 goldC = mix(float3(0.85, 0.6, 0.18), float3(1.0, 0.88, 0.45), coin) * lum + float3(1.0) * twinkle * 0.5;
    float3 cave = mix(float3(0.03, 0.03, 0.03) + float3(1.0, 0.75, 0.3) * 0.25 * pulse * smoothstep(0.2, -0.5, p.y), goldC, heap);
    c3 = mix(c3, cave, inHole);
    // the door itself: a bevelled plate with a dial and a three-spoke handle (squeezed as it turns)
    float2 dp = float2((p.x - dc.x) / max(sw, 0.05), p.y - dc.y);
    float3 dC = iron * (0.9 + 0.2 * smoothstep(-0.4, 0.4, dp.y));
    dC *= 1.0 - 0.35 * (1.0 - smoothstep(0.0, 0.03, -door));
    float dial = length(dp - float2(0.12, 0.06));
    float ticks = step(0.75, fract(atan2(dp.y - 0.06, dp.x - 0.12) / 6.2832 * 24.0)) * step(0.09, dial) * step(dial, 0.13);
    dC = mix(dC, float3(0.75, 0.62, 0.35) * lum * (0.8 + 0.3 * smoothstep(0.13, 0.0, dial)), (1.0 - smoothstep(0.125, 0.135, dial)));
    dC = mix(dC, float3(0.2, 0.16, 0.1) * lum, ticks);
    dC = mix(dC, float3(0.15, 0.12, 0.08) * lum, 1.0 - smoothstep(0.03, 0.04, dial));
    float2 hp = dp - float2(-0.2, 0.06);
    float hub = length(hp);
    float spokes = 1e3;
    for (int i = 0; i < 3; i++) {
        float a = float(i) * 2.0944 + 0.4;
        spokes = min(spokes, sd_seg(hp, float2(0.0), float2(cos(a), sin(a)) * 0.13) - 0.016);
    }
    float handle = min(spokes, hub - 0.04);
    dC = mix(dC, float3(0.55, 0.5, 0.42) * lum * (0.7 + 0.5 * smoothstep(-0.1, 0.1, hp.y)), 1.0 - smoothstep(-0.005, 0.005, handle));
    c3 = mix(c3, dC, inDoor);
    // hinges on the right, rivets along the frame
    float hinge = min(sd_box(p - float2(0.5, 0.0), float2(0.03, 0.07), 0.01), sd_box(p - float2(0.5, -0.4), float2(0.03, 0.07), 0.01));
    c3 = mix(c3, float3(0.35, 0.3, 0.26) * lum, 1.0 - smoothstep(-0.005, 0.005, hinge));
    float2 rp = float2(abs(p.x) - 0.555, fract((p.y + 0.7) * 6.0) - 0.5);
    float rivet = (1.0 - smoothstep(0.018, 0.03, length(float2(rp.x, rp.y / 6.0)))) * step(p.y, 0.24) * step(-0.65, p.y);
    c3 = mix(c3, iron * 1.5 + 0.05, rivet * (1.0 - inHole));
    // closed: a thread of gold light leaking around the door
    float seam = (1.0 - smoothstep(0.0, 0.02, abs(hole))) * (1.0 - smoothstep(0.0, 0.1, open)) * pulse * 0.5;
    c3 += float3(1.0, 0.75, 0.3) * seam;
    float halo = exp(-max(body, 0.0) * 14.0) * (1.0 - inside) * open * pulse * 0.35 * step(-0.6, p.y);
    return float4(c3 * inside + float3(1.0, 0.8, 0.4) * halo, max(inside, halo * 0.6));
}

// mangrove prop roots (the lagoon's): arching down from the trunk above the water into the sand, bark gone grey,
// oysters and barnacles crusting them at the waterline, green algae fuzz below. The quad spans the tank's height;
// the surface is near c.y = 0.93. col: the water's tint for the parts further down.
float4 draw_mangrove(float2 c, float t, float4 col) {
    float2 p = c * float2(0.7, 1.0);
    float d = sd_box(p - float2(-0.7, 1.12), float2(0.07, 0.16), 0.03), along = 0.0, which = 0.0;   // the trunk
    // the trunk stands above the water at the bank (left); the roots spring from it just over the surface and arch
    // down to the sand, the longer ones reaching further out
    for (int r = 0; r < 7; r++) {
        float fr = float(r);
        float2 a = float2(-0.68 + 0.02 * fr, 1.0 - 0.04 * fract(fr * 0.618));
        float2 b = float2(-0.6 + 0.18 * fr + 0.05 * sin(fr * 5.3), -0.86 + 0.03 * sin(fr * 1.7));
        float2 m = float2(b.x + 0.04, 1.02 + 0.02 * fr);                 // out first, then the knee, then down
        float2 prev = a;
        for (int i = 1; i <= 8; i++) {
            float u = float(i) / 8.0;
            float2 q = mix(mix(a, m, u), mix(m, b, u), u);
            float w = mix(0.04, 0.022, u) * (1.0 - 0.2 * fr / 6.0);
            float2 pa = p - prev, ba = q - prev;
            float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
            float dd = length(pa - ba * h) - w;
            if (dd < d) { d = dd; along = (float(i) - 1.0 + h) / 8.0; which = fr; }
            prev = q;
        }
    }
    float aa = fwidth(d) * 1.5 + 0.004;
    float a = 1.0 - smoothstep(-aa, aa, d);
    if (a <= 0.001) return float4(0.0);
    // bark: grey-brown, ridged along the root, lit from above, rounder in the middle
    float3 bark = float3(0.36, 0.3, 0.24) * (0.8 + 0.25 * vnoise(float2(along * 40.0, which * 7.0)));
    bark *= 0.75 + 0.35 * smoothstep(0.0, -0.03, d);
    // oysters and barnacles crusting the roots around the waterline; green fuzz below it
    float band = smoothstep(0.7, 0.82, p.y) * (1.0 - smoothstep(0.9, 0.95, p.y));
    float2 cg = p * 60.0 + float2(vnoise(p * 9.0), vnoise(p * 9.0 + 4.0)) * 2.0;
    float2 cj = float2(hash21(floor(cg)), hash21(floor(cg) + 3.7)) * 0.4 + 0.3;
    float crust = (1.0 - smoothstep(0.2, 0.35, length(fract(cg) - cj))) * step(0.45, hash21(floor(cg) + which));
    bark = mix(bark, float3(0.6, 0.58, 0.52), band * crust * 0.7);
    float fuzz = smoothstep(0.7, 0.2, p.y) * smoothstep(0.4, 0.7, vnoise(p * 50.0 + 3.0));
    bark = mix(bark, float3(0.22, 0.36, 0.16), fuzz * 0.5);
    // further back than the fish: the water in between takes its color, more the deeper
    float under = smoothstep(0.93, 0.4, p.y);
    bark = mix(bark, col.rgb, 0.2 + under * 0.4);
    float aw = a * mix(0.95, 0.75, under);
    return float4(bark * aw, aw);
}

// a manatee (the lagoon's): a big, slow, grey-brown body with a round paddle tail, small flippers, a whiskery snout,
// wrinkled skin with algae and old scars. phase: time; faces +x.
float4 draw_manatee(float2 c, float phase, float4 col) {
    float2 p = c * float2(1.7, 0.8);
    // the whole body undulates gently; the paddle tail moves the most
    float wave = sin(phase * 0.9);
    p.y -= wave * 0.035 * (p.x * p.x * 0.25) + wave * 0.09 * smoothstep(-0.3, -1.6, p.x) * smoothstep(-0.3, -1.6, p.x);
    float fat = 0.42 + 0.05 * smoothstep(0.6, -0.3, p.x) - 0.1 * smoothstep(-0.7, -1.2, p.x);
    float body = (length((p - float2(-0.05, 0.0)) / float2(1.18, fat)) - 1.0) * 0.4;
    float head = (length((p - float2(1.1, -0.04)) / float2(0.36, 0.28)) - 1.0) * 0.2;
    float snout = (length((p - float2(1.36, -0.1)) / float2(0.19, 0.18)) - 1.0) * 0.12;
    float tail = (length((p - float2(-1.4, 0.02)) / float2(0.3, 0.17)) - 1.0) * 0.15;
    float d = smin_k(smin_k(body, head, 0.14), snout, 0.08);
    d = smin_k(d, tail, 0.12);
    float2 fp = p - float2(0.6, -0.26);
    float fa = -1.0 + sin(phase * 0.7) * 0.18;
    fp = float2(fp.x * cos(fa) - fp.y * sin(fa), fp.x * sin(fa) + fp.y * cos(fa));
    float flip = (length((fp - float2(0.17, 0.0)) / float2(0.21, 0.075)) - 1.0) * 0.06;
    d = min(d, flip);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    if (a <= 0.001) return float4(0.0);
    // round: a normal from the body's ellipse, lit from above and a little ahead
    float2 bq = (p - float2(-0.05, 0.0)) / float2(1.18, fat);
    float z = sqrt(max(0.0, 1.0 - min(1.0, dot(bq, bq))));
    float diff = 0.4 + 0.7 * max(0.0, dot(normalize(float3(bq.x * 0.5, bq.y, z + 0.15)), normalize(float3(0.2, 0.75, 0.6))));
    // smooth grey-brown skin: big soft blotches, a faint fine grain, the belly paler
    float3 c3 = col.rgb * mix(0.95, 1.12, smoothstep(0.1, -0.5, bq.y));
    c3 *= 0.9 + 0.14 * vnoise(p * 3.5 + 1.0);
    c3 *= 0.97 + 0.05 * vnoise(p * 30.0);
    c3 *= diff;
    // a light dusting of green algae on the back, and two old pale scars
    float algae = smoothstep(0.55, 0.8, vnoise(p * 4.0 + 7.0)) * smoothstep(0.1, 0.6, bq.y);
    c3 = mix(c3, float3(0.32, 0.42, 0.24) * diff * dot(col.rgb, float3(0.7)), algae * 0.35);
    for (int i = 0; i < 2; i++) {
        float fi = float(i);
        float sc = abs(p.y - (0.18 + fi * 0.08) - 0.04 * sin(p.x * 3.0 + fi)) ;
        c3 = mix(c3, col.rgb * 1.3, (1.0 - smoothstep(0.004, 0.012, sc)) * step(-0.7 + fi * 0.3, p.x) * step(p.x, -0.2 + fi * 0.25) * 0.45);
    }
    // soft neck folds
    c3 *= 1.0 - 0.06 * (0.5 + 0.5 * sin(p.x * 30.0)) * smoothstep(0.55, 0.85, p.x) * (1.0 - smoothstep(0.85, 1.05, p.x));
    if (flip < 0.0 && body > 0.0) c3 = col.rgb * 0.75 * (0.85 + 0.15 * vnoise(fp * 20.0));
    // the face: a small dark eye with a glint, a nostril on top of the snout, a few whisker dots
    float er = length(p - float2(1.17, 0.05));
    c3 = mix(c3, float3(0.04), 1.0 - smoothstep(0.022, 0.03, er));
    c3 = mix(c3, float3(0.8), 1.0 - smoothstep(0.004, 0.008, length(p - float2(1.177, 0.058))));
    c3 *= 1.0 - 0.45 * (1.0 - smoothstep(0.014, 0.022, length((p - float2(1.47, 0.0)) / float2(1.0, 0.6))));
    for (int i = 0; i < 6; i++) {
        float2 wpos = float2(1.38 + 0.035 * float(i % 3), -0.12 - 0.04 * float(i / 3) + 0.01 * float(i % 2));
        c3 *= 1.0 - 0.35 * (1.0 - smoothstep(0.006, 0.011, length(p - wpos)));
    }
    c3 += col.rgb * 0.18 * (1.0 - smoothstep(0.0, 0.04, -d)) * smoothstep(0.0, 0.6, bq.y);
    return float4(c3 * a, a);
}

// a sunken ship far away (the deep sea's): a dark silhouette lying tilted on the bottom, its bow raised, a mast
// standing, another broken and fallen, a hole in the hull, the keel buried. Soft and faded by the distance.
float4 draw_wreck(float2 c, float phase, float4 col) {
    float2 p = c * float2(2.2, 1.0);
    float ang = -0.1;
    p = float2(p.x * cos(ang) - p.y * sin(ang), p.x * sin(ang) + p.y * cos(ang));
    float hull = max((length(p / float2(1.75, 0.5)) - 1.0) * 0.4, p.y - 0.06 - 0.12 * smoothstep(1.0, 1.7, p.x));
    hull = min(hull, sd_tri(p, float2(1.3, 0.12), float2(1.98, 0.32), float2(1.45, -0.32)));       // the bow
    hull = min(hull, sd_box(p - float2(-1.3, 0.16), float2(0.36, 0.14), 0.02));                     // the stern castle
    hull = max(hull, -((length((p - float2(0.3, -0.14)) / float2(0.24, 0.11)) - 1.0) * 0.1));       // a breach
    float mast = sd_seg(p, float2(-0.35, 0.05), float2(-0.28, 0.9)) - 0.03;
    mast = min(mast, sd_seg(p, float2(-0.62, 0.62), float2(0.02, 0.68)) - 0.015);                   // a yard
    mast = min(mast, sd_seg(p, float2(0.55, 0.05), float2(0.66, 0.46)) - 0.028);                    // broken
    mast = min(mast, sd_seg(p, float2(0.7, 0.44), float2(1.15, 0.12)) - 0.022);                     // its fallen top
    float rig = min(sd_seg(p, float2(-0.28, 0.9), float2(1.9, 0.3)), sd_seg(p, float2(-0.28, 0.9), float2(-1.55, 0.3))) - 0.006;
    float d = min(min(hull, mast), rig);
    float a = 1.0 - smoothstep(-0.02, 0.04, d);
    a *= smoothstep(-0.5, -0.3, p.y);                                       // the keel sinks into the sand
    // a dark shape, a little lighter on top where the faint light from above falls, some planks showing
    float3 c3 = col.rgb * (0.75 + 0.5 * smoothstep(-0.4, 0.3, p.y));
    c3 *= 0.9 + 0.1 * step(0.5, fract(p.y * 14.0)) * step(hull, 0.0);
    c3 += col.rgb * 0.5 * (1.0 - smoothstep(0.0, 0.04, -d)) * smoothstep(0.0, 0.3, p.y);
    float aw = a * col.a;
    return float4(c3 * aw, aw);
}

// a fishermen's trap (the lagoon's chest): a woven basket lying on the sand, its strips crossing over and under,
// three hoops, a funnel mouth at one end and a hatch on top tied shut. Light glows through the gaps between the strips;
// open (0…1), the hatch swings up on shells and pearls. Sand line at y ≈ -0.3 like the chest's.
float4 draw_fish_trap(float2 c, float phase, float glow, float4 col, float open) {
    float2 p = c;
    float lum = dot(col.rgb, float3(0.33)) / 0.32;
    float body = sd_seg(p, float2(-0.5, -0.3), float2(0.5, -0.3)) - 0.36 + 0.05 * smoothstep(0.3, 0.8, p.x);
    float aa = fwidth(body) + 1e-4;
    float inB = 1.0 - smoothstep(-aa, aa, body);
    // the weave: two sets of strips crossing diagonally, over and under; dark gaps where the inside shows
    float2 w = float2(p.x + p.y, p.x - p.y) * 7.0;
    float2 f = fract(w), cell = floor(w);
    float gap = max(smoothstep(0.78, 0.9, f.x), smoothstep(0.78, 0.9, f.y));
    float over = step(0.5, fract((cell.x + cell.y) * 0.5));
    float strip = over > 0.5 ? f.x : f.y;
    float3 straw = mix(float3(0.62, 0.52, 0.34), float3(0.5, 0.5, 0.46), 0.35) * lum;
    float3 c3 = straw * (0.78 + 0.3 * sin(strip * 3.1416)) * (0.85 + 0.25 * hash21(cell));
    // round: lit from above, darker toward the sand; green algae creeping up from below
    c3 *= 0.65 + 0.45 * smoothstep(-0.66, 0.06, p.y);
    c3 = mix(c3, float3(0.24, 0.36, 0.18) * lum, smoothstep(-0.45, -0.66, p.y) * smoothstep(0.4, 0.7, vnoise(p * 14.0)) * 0.7);
    // light from inside, through the gaps (a little when closed, a lot when open)
    float pulse = (0.6 + 0.4 * sin(phase * 1.3)) * glow;
    float3 inside = float3(0.06, 0.05, 0.03) + float3(1.0, 0.8, 0.4) * pulse * (0.08 + 0.45 * open);
    c3 = mix(c3, inside, gap * 0.85);
    // three hoops binding it, and the funnel mouth at the right end (rings narrowing inward)
    float hoop = 1e3;
    for (int i = 0; i < 3; i++) hoop = min(hoop, abs(p.x - (-0.5 + 0.5 * float(i))) - 0.035);
    c3 = mix(c3, straw * 0.7 * (0.8 + 0.3 * smoothstep(-0.6, 0.0, p.y)), (1.0 - smoothstep(0.0, 0.01, hoop)));
    float2 mq = (p - float2(0.78, -0.3)) / float2(0.12, 0.33);
    float mr = length(mq);
    float mouth = 1.0 - smoothstep(0.95, 1.0, mr);
    float rings = 0.75 + 0.25 * sin(mr * 22.0);
    c3 = mix(c3, mix(inside, straw * rings * 0.8, smoothstep(0.15, 0.5, mr)), mouth * inB);
    // the hatch on top, hinged at its left end; tied shut with a cord when closed, swinging up when open
    float ang = open * 1.9;
    float2 hp = p - float2(-0.3, 0.06);
    hp = float2(hp.x * cos(ang) + hp.y * sin(ang), -hp.x * sin(ang) + hp.y * cos(ang));
    float hatch = sd_box(hp - float2(0.3, 0.0), float2(0.3, 0.045), 0.02);
    float inH = 1.0 - smoothstep(-aa, aa, hatch);
    float3 hatchC = straw * (0.8 + 0.25 * sin(fract(hp.x * 14.0) * 3.1416)) * (0.9 + 0.2 * smoothstep(-0.05, 0.05, hp.y));
    float cord = (1.0 - smoothstep(0.008, 0.016, abs(p.x - 0.26))) * step(-0.02, p.y) * step(p.y, 0.1) * (1.0 - smoothstep(0.05, 0.2, open));
    // open: the hole on top shows the shells and pearls inside, glowing
    float hole = sd_box(p - float2(0.0, 0.03), float2(0.29, 0.05), 0.02);
    float inHole = (1.0 - smoothstep(-aa, aa, hole)) * smoothstep(0.05, 0.3, open);
    float2 pg = p * float2(16.0, 18.0);
    float pearl = 1.0 - smoothstep(0.28, 0.42, length(fract(pg) - 0.5));
    float hue = hash21(floor(pg));
    float3 treasure = mix(float3(0.95, 0.9, 0.82), float3(1.0, 0.75, 0.6), step(0.6, hue)) * (0.6 + 0.6 * pearl) * lum
                    + float3(1.0, 0.85, 0.5) * pulse * 0.4;
    float3 outc = c3 * inB;
    float a = inB;
    outc = mix(outc, treasure, inHole);
    a = max(a, inHole);
    outc = mix(outc, hatchC, inH);
    a = max(a, inH);
    outc = mix(outc, float3(0.35, 0.28, 0.18) * lum, cord);
    outc *= 1.0 - (1.0 - smoothstep(0.0, 0.04, -min(body, hatch))) * 0.3 * a;
    float halo = exp(-max(p.y - 0.06, 0.0) * 5.0) * step(0.06, p.y) * (1.0 - smoothstep(0.2, 0.5, abs(p.x))) * open * pulse * 0.45 * (1.0 - a);
    outc += float3(1.0, 0.82, 0.45) * halo;
    return float4(outc, max(a, halo * 0.6));
}

// an old diving helmet lying on the sand (the deep sea's, only scenery): copper gone green, a round grilled faceplate,
// a small side window, the breastplate with its bolts. Sand line at y ≈ -0.3.
float4 draw_diving_helmet(float2 c, float phase, float4 col) {
    float ang = 0.22;
    float2 p = float2(c.x * cos(ang) + c.y * sin(ang), -c.x * sin(ang) + c.y * cos(ang)) - float2(0.0, 0.05);
    float dome = length(p - float2(0.0, 0.12)) - 0.42;
    float breast = sd_box(p - float2(0.0, -0.3), float2(0.58 - 0.12 * smoothstep(-0.45, -0.15, p.y), 0.13), 0.08);
    float neck = sd_box(p - float2(0.0, -0.17), float2(0.36, 0.06), 0.02);
    float valve = sd_box(p - float2(0.0, 0.58), float2(0.06, 0.06), 0.02);
    float d = min(min(dome, breast), min(neck, valve));
    float aa = fwidth(d) + 1e-4;
    float inside = 1.0 - smoothstep(-aa, aa, d);
    float lum = dot(col.rgb, float3(0.33)) / 0.33;
    // copper with verdigris: green patina in blotches, brighter copper where it's worn
    float pat = smoothstep(0.4, 0.7, vnoise(p * 6.0) * 0.65 + vnoise(p * 17.0) * 0.35);
    float3 metal = mix(float3(0.46, 0.29, 0.19), float3(0.24, 0.38, 0.34), pat) * (0.7 + 0.3 * vnoise(p * 50.0));
    // the dome is round: lit from the upper left
    float2 dq = (p - float2(0.0, 0.12)) / 0.42;
    float z = sqrt(max(0.0, 1.0 - dot(dq, dq)));
    float diff = 0.35 + 0.8 * max(0.0, dot(normalize(float3(dq, z)), normalize(float3(-0.4, 0.6, 0.7))));
    float3 c3 = metal * (dome < 0.0 ? diff : 0.55 + 0.4 * smoothstep(-0.45, -0.15, p.y));
    c3 *= 1.0 - 0.25 * (1.0 - smoothstep(0.0, 0.01, abs(neck))) ;
    // bolts along the breastplate
    float2 bp = float2(fract((p.x + 0.6) * 5.0) - 0.5, p.y + 0.3);
    float bolt = (1.0 - smoothstep(0.02, 0.035, length(float2(bp.x / 5.0, bp.y)))) * step(breast, 0.0) * step(abs(p.x), 0.5);
    c3 = mix(c3, float3(0.5, 0.42, 0.3), bolt);
    // the faceplate: a thick brass ring, dark glass, three bars across it; a little side window
    float2 fp = p - float2(0.14, 0.1);
    float fr = length(fp / float2(0.85, 1.0));
    float glass = 1.0 - smoothstep(0.17, 0.18, fr);
    float ring = (1.0 - smoothstep(0.215, 0.225, fr)) * (1.0 - glass);
    float bars = (1.0 - smoothstep(0.012, 0.02, abs(fract(fp.x * 9.0 + 0.5) - 0.5) / 9.0)) * glass * step(abs(fp.x), 0.15);
    float3 glassC = float3(0.03, 0.06, 0.07) + float3(0.25, 0.35, 0.35) * smoothstep(0.1, 0.0, length(fp - float2(-0.06, 0.07))) * 0.6;
    c3 = mix(c3, glassC, glass);
    c3 = mix(c3, float3(0.5, 0.4, 0.24) * (0.7 + 0.5 * smoothstep(-0.2, 0.2, fp.y)), max(ring, bars));
    float2 sp = p - float2(-0.27, 0.16);
    float sr = length(sp / float2(0.55, 1.0));
    c3 = mix(c3, glassC, 1.0 - smoothstep(0.08, 0.09, sr));
    c3 = mix(c3, float3(0.45, 0.36, 0.22), (1.0 - smoothstep(0.105, 0.115, sr)) * smoothstep(0.08, 0.09, sr));
    c3 *= lum;
    c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.03, -d)) * 0.3;
    return float4(c3 * inside, inside);
}

// A clutch of eggs laid on the sand: where the sessions started from the aquarium hatch. Translucent shells, each
// with its embryo turning inside; glow: how stirred they are (one is about to hatch, or just did).
// look: 0 the heap of eggs, 1 the deep sea's egg case (a shark's "mermaid's purse", its embryo lit inside),
// 2 the lagoon's eggs along a mangrove root.
float4 draw_eggs(float2 c, float phase, float glow, float4 col, float look) {
    float2 p = c * float2(1.25, 0.85);
    if (look > 0.5 && look < 1.5) {
        float2 q = p - float2(0.0, 0.1);
        q.x += 0.04 * sin(q.y * 3.0 + phase * 0.6) * (0.4 + q.y);          // it sways from where it's anchored
        float body = length(q / float2(0.4, 0.5)) - 1.0;
        // its four corners drawn out into curling tendrils
        float horns = 1e3;
        for (int i = 0; i < 4; i++) {
            float sx = i < 2 ? -1.0 : 1.0, sy = (i == 0 || i == 2) ? -1.0 : 1.0;
            float2 h = q - float2(sx * 0.24, sy * 0.4);
            float t = clamp(h.y * sy / 0.3, 0.0, 1.0);
            horns = min(horns, length(h - float2(sx * 0.13 * t * t, sy * 0.3 * t)) - 0.04 * (1.0 - t * 0.75));
        }
        float d = min(body * 0.4, horns);
        float aa = fwidth(d) + 1e-4;
        float inside = 1.0 - smoothstep(-aa, aa, d);
        float deep = clamp(-body, 0.0, 1.0);                                // 0 at the wall, 1 in the middle
        float within = step(body, 0.0);
        // a thin leathery wall, ribbed, lit from inside
        float3 e = mix(col.rgb * 0.3, col.rgb * 0.85, deep) * (0.86 + 0.14 * sin(q.x * 30.0));
        // the yolk, and the embryo curled over it, turning slowly
        float yolk = (1.0 - smoothstep(0.14, 0.22, length(q - float2(0.0, -0.16)))) * within;
        e = mix(e, float3(1.0, 0.8, 0.45) * (0.8 + 0.15 * sin(phase * 1.4) + 0.4 * glow), yolk * 0.85);
        float turn = phase * 0.6 + 0.4 * sin(phase * 2.3) * glow;
        float2 m = q - float2(0.0, 0.02);
        float arc = (1.0 - smoothstep(0.03, 0.055, abs(length(m) - 0.17))) * step(sin(atan2(m.y, m.x) - turn), 0.55) * within;
        e = mix(e, col.rgb * 0.1, arc);
        float2 head = m - float2(cos(turn + 2.2), sin(turn + 2.2)) * 0.17;
        e = mix(e, col.rgb * 0.1, (1.0 - smoothstep(0.05, 0.075, length(head))) * within);
        e += float3(1.0, 0.85, 0.6) * glow * 0.35 * deep;
        e += (1.0 - smoothstep(0.05, 0.2, length(q - float2(-0.16, 0.24)))) * 0.25 * within;
        return float4(e * inside, inside);
    }
    float3 acc = float3(0.0);
    float alpha = 0.0;
    bool root = look > 1.5;
    if (root) {
        // the mangrove root they're laid along, rising across the quad
        float tt = clamp((p.x + 0.95) / 1.9, 0.0, 1.0);
        float ry = -0.5 + 0.95 * tt + 0.1 * sin(tt * 6.0);
        float dr = abs(p.y - ry) - (0.075 - 0.03 * tt);
        float ar = fwidth(dr) + 1e-4;
        float on = (1.0 - smoothstep(-ar, ar, dr)) * step(abs(p.x), 1.0);
        float3 bark = float3(0.33, 0.24, 0.16) * (0.75 + 0.25 * sin(p.x * 23.0 + p.y * 9.0)) * (0.6 + 0.4 * dot(col.rgb, float3(0.33)));
        acc = bark * on;
        alpha = on;
    }
    for (int i = 0; i < 11; i++) {
        float fi = float(i);
        float2 h = float2(fract(sin(fi * 12.9898) * 43758.5453), fract(sin(fi * 78.233) * 12543.123));
        // a little heap: five at the bottom, four on them, two on top
        float row = i < 5 ? 0.0 : (i < 9 ? 1.0 : 2.0);
        float n = i < 5 ? 5.0 : (i < 9 ? 4.0 : 2.0);
        float j = i < 5 ? fi : (i < 9 ? fi - 5.0 : fi - 9.0);
        float stir = sin(phase * (5.0 + h.x * 3.0) + fi * 2.1) * 0.012 * glow;
        float2 at = float2((j - (n - 1.0) * 0.5) * 0.36 + (h.x - 0.5) * 0.05 + stir, row * 0.29 + (h.y - 0.5) * 0.04);
        float r = 0.185 + h.y * 0.025;
        if (root) {
            // along the root, on one side and the other
            float tt = 0.12 + 0.76 * fi / 10.0;
            float side = (i % 2 == 0) ? 1.0 : -1.0;
            at = float2(-0.95 + 1.9 * tt + stir, -0.5 + 0.95 * tt + 0.1 * sin(tt * 6.0) + side * (0.13 + h.y * 0.03));
            r = 0.115 + h.x * 0.02;
        }
        float2 q = (p - at) / r;
        float d = length(q);
        float aa = fwidth(d) + 1e-4;
        float a = 1.0 - smoothstep(1.0 - aa, 1.0 + aa, d);
        if (a <= 0.0) continue;
        float rim = smoothstep(0.5, 1.0, d);
        float pulse = 0.5 + 0.5 * sin(phase * 1.4 + fi * 1.7);
        // the shell, lighter at the rim and lit from inside
        float3 e = mix(col.rgb * 0.8, col.rgb * 1.2 + 0.12, rim);
        e += col.rgb * (0.12 + 0.22 * pulse) * (1.0 - rim) + float3(1.0, 0.85, 0.6) * glow * 0.45 * (1.0 - rim * 0.5);
        // the embryo: a dark comma that turns slowly, with its eye
        float turn = phase * 0.5 + fi * 1.3;
        float2 m = q - float2(cos(turn), sin(turn)) * 0.14;
        float body = 1.0 - smoothstep(0.34, 0.44, length(m));
        e = mix(e, col.rgb * 0.22, body * 0.85);
        float eye = 1.0 - smoothstep(0.08, 0.12, length(m - float2(cos(turn + 1.2), sin(turn + 1.2)) * 0.17));
        e = mix(e, float3(0.02), eye * body);
        // a wet highlight
        e += (1.0 - smoothstep(0.08, 0.26, length(q - float2(-0.36, 0.4)))) * 0.55;
        float op = a * (0.8 + 0.2 * rim);
        acc = acc * (1.0 - op) + e * op;
        alpha = alpha + op * (1.0 - alpha);
    }
    return float4(acc, alpha);
}

// ---------- the music fish (a betta with a flowing, iridescent tail) and the notes it lets out ----------

"""#

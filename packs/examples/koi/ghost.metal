// A ghost koi, facing +x: the pond's koi (the same heavy-shouldered carp as draw_koi), but an apparition that only
// crosses at night: a white, faintly blue body you can half see through, a pearly sheen along the flank, a few
// barely paler patches, long trailing fins more see-through still, and a quiet glow around it that dies well
// before the quad's edge. col is its pale color lit by the hour: it tints the fish, which keeps a light of its own.
// p = c * (1.5, 1.0).
float4 draw_koi_ghost(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.5, 1.0);
    float fade = 1.0 - smoothstep(0.55, 0.98, max(abs(c.x), abs(c.y)));
    float seed = extra.y;
    // the body swims in a slow wave, wider toward the tail
    p.y -= sin(phase - p.x * 2.2) * (0.012 + 0.08 * (1.0 - smoothstep(-1.0, 0.3, p.x)));

    // the koi's body: full at the shoulders, tapering into a long tail stock; a blunt, rounded head
    float cx = 0.22, rx = 0.84, ry = 0.23;
    float rear = smoothstep(cx + 0.2, cx - rx, p.x);
    float ryx = ry * (1.0 - 0.55 * rear) * (1.0 + 0.12 * smoothstep(cx + 0.02, cx + 0.37, p.x) * step(0.0, p.y));
    float2 b = (p - float2(cx, 0.0)) / float2(rx, ryx);
    float body = (length(b) - 1.0) * min(rx, ryx);
    // the tail: the koi's fan, drawn out long, its lobes trailing and waving
    float bx = cx - rx * 0.92;
    float sw = sin(phase - 1.2) * 0.07;
    float2 tq = p - float2(bx, 0.0);
    tq.y -= sw * smoothstep(0.0, -0.6, tq.x) + sin(phase * 0.9 + tq.x * 5.0) * 0.03 * smoothstep(-0.2, -0.7, tq.x);
    float tail = sd_tri(tq, float2(0.06, 0.0), float2(-0.74, 0.34), float2(-0.74, -0.34));
    tail = max(tail, length(tq - float2(0.06, 0.0)) - 0.8);
    tail = max(tail, -(length((tq - float2(-0.78, 0.0)) / float2(0.36, 0.12)) - 1.0) * 0.12);
    tail -= 0.015 + 0.012 * sin(tq.y * 18.0 + phase * 1.3) * smoothstep(-0.2, -0.6, tq.x);
    // a long dorsal fin, a long pectoral fin trailing like a sleeve, pelvic and anal fins drawn out behind
    float dors = sd_tri(p, float2(cx + 0.3, ry * 0.85), float2(cx - 0.56, ry * 0.4), float2(cx - 0.5, ry + 0.11 + 0.015 * sin(phase * 1.3))) - 0.014;
    float pang = -0.5 + sin(phase * 0.9) * 0.2;
    float2 pq = p - float2(cx + rx * 0.42, -ry * 0.55);
    pq = float2(pq.x * cos(pang) - pq.y * sin(pang), pq.x * sin(pang) + pq.y * cos(pang));
    float pect = (length((pq - float2(-0.25, 0.0)) / float2(0.31, 0.09)) - 1.0) * 0.09;
    float pelv = sd_tri(p, float2(cx - 0.05, -ry * 0.75), float2(cx - 0.22, -ry * 0.7), float2(cx - 0.4, -ry - 0.17 + 0.02 * sin(phase * 1.1))) - 0.012;
    float anal = sd_tri(p, float2(cx - rx * 0.52, -ryx * 0.6), float2(cx - rx * 0.7, -ry * 0.3), float2(cx - rx * 0.86, -ry * 0.6 - 0.12 + 0.02 * sin(phase * 1.1 + 1.0))) - 0.01;
    float fins = min(min(dors, pelv), min(anal, tail));
    float barb = 1e3;
    for (int i = 0; i < 2; i++) {
        float2 a0 = float2(cx + rx * 0.93, -ry * 0.25), a1 = a0 + float2(0.05 + 0.03 * float(i), -0.07 - 0.03 * float(i) + sin(phase * 0.8 + float(i)) * 0.01);
        barb = min(barb, sd_seg(p, a0, a1) - 0.007);
    }
    float d = min(min(body, fins), min(pect, barb));
    float aa = fwidth(d) + 1e-4;
    float inside = 1.0 - smoothstep(-aa, aa, d);

    // its light: col's tint, never quite as dark as the night
    float top = max(col.r, max(col.g, col.b));
    float3 tint = col.rgb / max(top, 0.05);
    float lum = mix(top, 1.0, 0.55);
    float3 pale = mix(float3(0.9, 0.94, 1.0), tint, 0.5) * lum;
    float3 blue = float3(0.62, 0.76, 1.0) * lum;
    float3 c3 = pale;
    float al;
    if (body < 0.0) {
        float yn = p.y / max(ryx, 0.02);
        // barely there: paler patches where a koi's color would be, a faint net of scales
        float2 np = p * float2(2.6, 3.4) + seed * 17.0;
        float patch = smoothstep(0.45, 0.62, vnoise(np) * 0.7 + vnoise(np * 2.3) * 0.3);
        c3 = mix(pale * 0.86, pale * 1.04, patch);
        c3 = mix(c3, blue, 0.2 + 0.25 * smoothstep(0.3, -0.9, yn));                      // bluer toward the belly
        float2 sq = p * float2(16.0, 18.0); sq.x += fmod(floor(sq.y), 2.0) * 0.5;
        float sr = length(fract(sq) - float2(0.5, 0.0));
        c3 *= 1.0 - smoothstep(0.4, 0.47, sr) * (1.0 - smoothstep(0.5, 0.57, sr)) * 0.07;
        // round, softly: a lit back, and the pearly sheen: a long band on the shoulder that shifts between rose and green
        c3 *= 0.8 + 0.26 * smoothstep(-1.0, 0.8, yn);
        float2 hs = (p - float2(cx + 0.1, ryx * 0.38)) / float2(0.6, 0.11);
        float sheen = pow(max(0.0, 1.0 - dot(hs, hs)), 2.0);
        float3 pearl = 0.5 + 0.5 * cos(6.2832 * (p.x * 1.3 + phase * 0.05 + float3(0.0, 0.33, 0.67)));
        c3 += mix(float3(1.0), pearl, 0.45) * sheen * 0.22 * lum;
        float edge = 1.0 - smoothstep(0.0, 0.04, -body);
        c3 += float3(0.8, 0.9, 1.0) * edge * 0.13 * lum;                                 // a rim of light all round
        // the gill cover, and a dark, quiet eye
        float2 gc = float2(cx + rx * 0.62, -0.02);
        float garc = abs(length((p - gc) * float2(1.0, 0.8)) - 0.13);
        c3 *= 1.0 - (1.0 - smoothstep(0.004, 0.014, garc)) * step(p.x, gc.x) * 0.12;
        float2 eye = float2(cx + rx * 0.8, ry * 0.08);
        float re = length(p - eye);
        c3 = mix(c3, blue * 0.75, (1.0 - smoothstep(0.03, 0.04, re)) * 0.6);
        c3 = mix(c3, float3(0.05, 0.07, 0.14), (1.0 - smoothstep(0.018, 0.026, re)) * 0.85);
        c3 = mix(c3, float3(1.0), 1.0 - smoothstep(0.004, 0.009, length(p - eye - float2(0.006, 0.008))));
        // see-through, more so in the middle of the flank than along its outline
        al = mix(0.68, 0.84, edge);
        al = max(al, (1.0 - smoothstep(0.03, 0.045, re)) * 0.95);
    } else {
        // the fins: veils, rayed, thinning out toward their trailing edges
        float2 rr = p - float2(bx + 0.05, 0.0);
        float rays = 0.5 + 0.5 * cos(atan2(rr.y, -rr.x) * 30.0);
        if (pect < min(fins, barb)) rays = 0.5 + 0.5 * cos(atan2(pq.y, pq.x + 0.3) * 22.0);
        c3 = mix(pale, blue, 0.35) * (0.8 + 0.2 * rays);
        float rimF = smoothstep(-0.035, -0.004, d);
        c3 += float3(0.85, 0.92, 1.0) * rimF * 0.18 * lum;
        float trail = smoothstep(cx - 0.4, cx - 1.5, p.x);
        al = (0.3 + 0.16 * rays + 0.14 * rimF) * (1.0 - 0.5 * trail);
        if (barb < min(fins, pect)) al = 0.6;
    }
    float a = inside * al;
    // the glow: close and faint, a breath of it further out, gone before the edge
    float dd = max(d, 0.0);
    float pulse = 0.9 + 0.1 * sin(phase * 0.5);
    float halo = (exp(-dd * 16.0) * 0.16 + exp(-dd * 5.0) * 0.07) * pulse * fade * (1.0 - inside);
    float3 rgb = c3 * a + blue * halo;
    float alpha = a + halo * 0.5;
    return float4(rgb * col.a, min(alpha, 1.0) * col.a);
}

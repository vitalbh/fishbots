// Desk tank: the goldfish, the bubble-eye and the guppy (fish kinds), the pleco on the glass and the apple snail.

// Goldfish (a comet): a plump orange body in the color it's given, a long flowing forked tail, a tall dorsal fin,
// big scales that catch the light, a round eye. extra.y: the pattern (0 plain, 1 white belly and tail, 2 a white
// saddle and red cap, 3 calico spots). extra.w: fullness, + 2 while asleep.
float4 draw_desk_goldfish(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.25, 0.8);
    int pat = int(extra.y + 0.5) % 4;
    bool asleep = extra.w > 1.5;
    float fat = clamp(extra.w - (asleep ? 2.0 : 0.0), 0.0, 1.0);
    p.y -= sin(phase - p.x * 2.4) * 0.045 * smoothstep(0.3, -1.0, p.x);
    float thin = mix(0.36, 1.0, smoothstep(-0.55, 0.15, p.x));
    float ry = 0.33 * thin * (1.0 + 0.4 * fat);
    float body = (length((p - float2(0.3, 0.0)) / float2(0.56, ry)) - 1.0) * ry;
    // the tail: two long soft lobes that trail and ripple
    float2 tq = p - float2(-0.2, 0.0);
    float rip = sin(phase * 1.2 - tq.x * 6.0) * 0.05 * smoothstep(0.0, -0.8, tq.x);
    float up = sd_tri(tq + float2(0.0, -rip), float2(0.1, 0.02), float2(-0.5, 0.06), float2(-0.98, 0.52)) - 0.03;
    float dn = sd_tri(tq + float2(0.0, rip), float2(0.1, -0.02), float2(-0.5, -0.06), float2(-0.98, -0.5)) - 0.03;
    float tail = min(up, dn);
    float dors = sd_tri(p, float2(0.52, 0.26), float2(0.0, 0.2), float2(0.08, 0.6 + 0.02 * sin(phase * 1.3))) - 0.02;
    float vent = sd_tri(p, float2(0.34, -0.28), float2(0.14, -0.26), float2(0.1, -0.52)) - 0.015;
    float anal = sd_tri(p, float2(0.0, -0.2), float2(-0.18, -0.14), float2(-0.24, -0.42)) - 0.015;
    float pang = -0.5 + sin(phase * 1.9) * 0.4;
    float2 pq = p - float2(0.5, -0.12);
    pq = float2(pq.x * cos(pang) - pq.y * sin(pang), pq.x * sin(pang) + pq.y * cos(pang));
    float pect = (length((pq - float2(-0.12, 0.0)) / float2(0.15, 0.05)) - 1.0) * 0.05;
    float fins = min(min(tail, pect), min(dors, min(vent, anal)));
    float d = min(body, fins);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float3 orange = mix(float3(1.0, 0.48, 0.1), col.rgb, 0.4), white = float3(0.98, 0.95, 0.9);
    float yn = p.y / max(ry, 0.05);
    float3 c3 = orange;
    if (pat == 1) c3 = mix(white, orange, smoothstep(-0.5, 0.1, yn + 0.25 * vnoise(p * 5.0)));
    if (pat == 2) c3 = mix(white, float3(0.92, 0.16, 0.1), smoothstep(0.48, 0.62, vnoise(p * 3.0 + 2.0) + 0.25 * smoothstep(0.4, 0.75, p.x) * step(0.0, yn)));
    if (pat == 3) {
        c3 = mix(white, orange, smoothstep(0.42, 0.55, vnoise(p * 4.0 + 5.0)));
        float2 sg = p * 11.0;
        c3 = mix(c3, float3(0.08, 0.08, 0.12), (1.0 - smoothstep(0.14, 0.24, length(fract(sg) - 0.5))) * step(0.72, hash21(floor(sg))));
    }
    // big scales: each one a little arc of light
    float2 sc = p * float2(11.0, 13.0);
    sc.x += fmod(floor(sc.y), 2.0) * 0.5;
    float sr = length(fract(sc) - float2(0.5, 0.0));
    c3 *= 1.0 - smoothstep(0.4, 0.48, sr) * (1.0 - smoothstep(0.5, 0.58, sr)) * 0.22;
    c3 += float3(1.0, 0.9, 0.6) * smoothstep(0.3, 0.38, sr) * (1.0 - smoothstep(0.38, 0.46, sr)) * 0.1 * smoothstep(-0.2, 0.6, yn);
    c3 = fish_round(c3 * 1.08, float2((p.x - 0.3) / 0.56, yn), body);
    float gc = abs(length((p - float2(0.6, -0.02)) * float2(1.0, 0.75)) - 0.17);
    c3 *= 1.0 - (1.0 - smoothstep(0.005, 0.02, gc)) * step(p.x, 0.6) * step(body, 0.0) * 0.22;
    c3 = mix(c3, c3 * 0.35, (1.0 - smoothstep(0.0, 0.012, abs(p.y + 0.1 + (p.x - 0.82) * 0.3) - 0.006)) * step(0.76, p.x) * step(body, 0.0));
    float al = a;
    if (body > 0.0) {
        float3 fin = pat == 0 ? orange * 1.05 + 0.08 : mix(white, orange, pat == 3 ? 0.5 : 0.25);
        float rays = tail < min(pect, min(dors, min(vent, anal))) ? cos(atan2(tq.y, -(tq.x - 0.1)) * 44.0) : cos(p.x * 60.0 - p.y * 30.0);
        c3 = fin * (0.82 + 0.18 * rays);
        c3 = mix(c3, c3 + 0.2, smoothstep(-0.05, 0.0, d));                           // lighter at the edge
        al *= 0.78;
    }
    c3 = fish_eye(c3, p, float2(0.68, 0.07), 0.07, float3(1.0, 0.75, 0.3), asleep ? 1.0 : 0.0);
    c3 += col.rgb * glow * 0.45;
    float fade = 1.0 - smoothstep(0.6, 1.0, max(abs(c.x), abs(c.y)));
    float halo = exp(-max(d, 0.0) * 12.0) * glow * (1.0 - a) * fade;
    return float4((c3 * al + col.rgb * halo * 0.9) * col.a, min(al + halo * 0.55, 1.0) * col.a);
}

// Bubble-eye goldfish: an egg of a body with no fin on its back, eyes that look straight up, and under each one a
// big wobbling sac of fluid, bigger than its head; a double fan of a tail. The color it's given.
// extra.y: the pattern (0 plain, 1 white, 2 red and white, 3 black and orange). extra.w: fullness, + 2 asleep.
float4 draw_desk_bubbleeye(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.25, 0.8);
    int pat = int(extra.y + 0.5) % 4;
    bool asleep = extra.w > 1.5;
    p.y -= sin(phase - p.x * 2.2) * 0.03 * smoothstep(0.2, -1.0, p.x);
    float body = (length((p - float2(0.12, 0.02)) / float2(0.52, 0.38 * mix(0.5, 1.0, smoothstep(-0.5, 0.0, p.x)))) - 1.0) * 0.38;
    float2 tq = p - float2(-0.34, 0.02);
    float rip = sin(phase * 1.2 - tq.x * 7.0) * 0.04 * smoothstep(0.0, -0.6, tq.x);
    float tail = min(sd_tri(tq + float2(0.0, -rip), float2(0.08, 0.02), float2(-0.3, 0.04), float2(-0.72, 0.46)),
                     sd_tri(tq + float2(0.0, rip), float2(0.08, -0.02), float2(-0.3, -0.04), float2(-0.72, -0.44))) - 0.04;
    float vent = sd_tri(p, float2(0.18, -0.3), float2(0.0, -0.28), float2(-0.04, -0.5)) - 0.015;
    float pang = -0.5 + sin(phase * 2.0) * 0.4;
    float2 pq = p - float2(0.36, -0.14);
    pq = float2(pq.x * cos(pang) - pq.y * sin(pang), pq.x * sin(pang) + pq.y * cos(pang));
    float pect = (length((pq - float2(-0.11, 0.0)) / float2(0.13, 0.045)) - 1.0) * 0.045;
    // the sac under the eye: it lags behind as the fish swims, and jiggles
    float jig = sin(phase * 2.3) * 0.02;
    float2 sacC = float2(0.62 - jig, -0.07 + jig * 0.6);
    float sac = (length((p - sacC) / float2(0.2 + jig * 0.5, 0.21 - jig * 0.5)) - 1.0) * 0.2;
    float fins = min(tail, min(vent, pect));
    float d = min(min(body, fins), sac);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float3 orange = mix(float3(1.0, 0.5, 0.12), col.rgb, 0.4), white = float3(0.98, 0.95, 0.9);
    float3 c3 = pat == 1 ? white : orange;
    if (pat == 2) c3 = mix(white, float3(0.92, 0.18, 0.1), smoothstep(0.45, 0.58, vnoise(p * 3.2 + 1.0)));
    if (pat == 3) c3 = mix(orange, float3(0.08, 0.08, 0.1), smoothstep(0.42, 0.56, vnoise(p * 3.5 + 4.0) + 0.3 * smoothstep(0.0, 0.3, p.y)));
    float3 skin = c3;
    float2 sc = p * float2(11.0, 13.0);
    sc.x += fmod(floor(sc.y), 2.0) * 0.5;
    float sr = length(fract(sc) - float2(0.5, 0.0));
    c3 *= 1.0 - smoothstep(0.4, 0.48, sr) * (1.0 - smoothstep(0.5, 0.58, sr)) * 0.2;
    c3 = fish_round(c3 * 1.08, (p - float2(0.12, 0.02)) / float2(0.52, 0.38), body);
    c3 = mix(c3, c3 * 0.35, (1.0 - smoothstep(0.0, 0.012, abs(p.y + 0.02 + (p.x - 0.62) * 0.3) - 0.006)) * step(0.56, p.x) * step(body, 0.0) * step(sac, 1.0) * step(0.0, sac));
    float al = a;
    if (body > 0.0 && sac > 0.0) {
        c3 = (skin * 0.9 + 0.12) * (0.82 + 0.18 * cos(atan2(tq.y, -(tq.x - 0.08)) * 40.0));
        al *= 0.78;
    }
    // the sac: thin skin full of fluid, see-through, a bright rim and a soft highlight
    if (sac < 0.0) {
        float2 sb = (p - sacC) / float2(0.2, 0.21);
        float rim = smoothstep(0.55, 1.0, length(sb));
        float3 sk = mix(skin * 0.9 + 0.15, skin * 1.2 + 0.1, rim);
        sk += float3(1.0) * (1.0 - smoothstep(0.0, 0.35, length(sb - float2(-0.3, 0.35)))) * 0.45;
        float sa = 0.55 + 0.35 * rim;
        c3 = mix(c3, sk, body < 0.0 ? sa : 1.0);
        if (body > 0.0) al = a * sa;
    }
    // the eye sits on top of the sac, looking up
    c3 = fish_eye(c3, p, float2(0.56, 0.16), 0.062, float3(1.0, 0.75, 0.3), asleep ? 1.0 : 0.0);
    if (!asleep) c3 = mix(c3, float3(0.02), 1.0 - smoothstep(0.02, 0.03, length(p - float2(0.565, 0.185))));
    c3 += col.rgb * glow * 0.45;
    float fade = 1.0 - smoothstep(0.6, 1.0, max(abs(c.x), abs(c.y)));
    float halo = exp(-max(d, 0.0) * 12.0) * glow * (1.0 - a) * fade;
    return float4((c3 * al + col.rgb * halo * 0.9) * col.a, min(al + halo * 0.55, 1.0) * col.a);
}

// Guppy: a tiny plain body and a tail bigger than the rest of it, a wide fan in the color it's given, spotted and
// edged in black, rippling; a matching flag of a dorsal fin. The tank's schools. extra.w > 1.5: asleep.
float4 draw_desk_guppy(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.25, 0.8);
    p.y -= sin(phase - p.x * 2.6) * 0.04 * smoothstep(0.4, -1.0, p.x);
    float thin = mix(0.4, 1.0, smoothstep(-0.3, 0.3, p.x));
    float ry = 0.17 * thin;
    float body = (length((p - float2(0.42, 0.0)) / float2(0.5, ry)) - 1.0) * ry;
    float2 tq = p - float2(-0.02, 0.0);
    float ang = atan2(tq.y, -tq.x);
    float r = length(tq);
    float edge = 0.86 + 0.06 * sin(ang * 7.0 - phase * 1.5) + 0.04 * sin(ang * 3.0 + phase);
    float tail = max(max(r - edge, abs(ang) - 0.62), tq.x - 0.02);
    float dors = sd_tri(p, float2(0.42, 0.14), float2(0.14, 0.12), float2(0.02, 0.42 + 0.03 * sin(phase * 1.4))) - 0.02;
    float fins = min(tail * 0.6, dors);
    float d = min(body, fins);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float3 base = col.rgb, silver = float3(0.78, 0.82, 0.78);
    float yn = p.y / max(ry, 0.04);
    float3 c3 = mix(silver, mix(silver, base, 0.6), smoothstep(0.3, -0.5, p.x));               // the color comes in toward the tail
    c3 = mix(c3, float3(0.3, 0.9, 1.0), (1.0 - smoothstep(0.5, 1.0, length((p - float2(0.3, 0.02)) / float2(0.1, 0.06)))) * 0.5);   // a blue shoulder spot
    c3 = fish_round(c3 * 1.08, float2((p.x - 0.42) / 0.5, yn), body);
    float al = a;
    if (body > 0.0) {
        float3 fin = mix(base, base.gbr, 0.25 * (0.5 + 0.5 * sin(r * 9.0)));
        fin *= 0.85 + 0.15 * cos(ang * 30.0);
        float2 sg = float2(ang * 6.0, r * 9.0);
        fin = mix(fin, float3(0.05, 0.04, 0.08), (1.0 - smoothstep(0.16, 0.26, length(fract(sg) - 0.5))) * step(0.5, hash21(floor(sg))) * 0.8);
        fin = mix(fin, float3(0.05, 0.04, 0.08), smoothstep(-0.05, -0.01, tail) * step(tail * 0.6, dors) * 0.7);       // a dark edge
        c3 = fin;
        al *= 0.85;
    }
    c3 = fish_eye(c3, p, float2(0.74, 0.03), 0.055, silver, extra.w > 1.5 ? 1.0 : 0.0);
    c3 += col.rgb * glow * 0.45;
    float fade = 1.0 - smoothstep(0.6, 1.0, max(abs(c.x), abs(c.y)));
    float halo = exp(-max(d, 0.0) * 12.0) * glow * (1.0 - a) * fade;
    return float4((c3 * al + col.rgb * halo * 0.9) * col.a, min(al + halo * 0.55, 1.0) * col.a);
}

// The pleco, stuck to the front glass and seen from its belly side: a flat wedge of a body, a wide sucker mouth
// working at the glass, pectoral and pelvic fins spread flat, a tail; mottled brown. It climbs slowly, cleaning.
// p = c * (1.6, 0.7); +x is the way it goes.
float4 draw_desk_pleco(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.6, 0.7);
    p.y -= sin(phase * 0.8 - p.x * 2.0) * 0.03 * smoothstep(0.2, -1.4, p.x);
    float taper = mix(0.14, 1.0, smoothstep(-1.2, 0.5, p.x));
    float body = (length((p - float2(0.2, 0.0)) / float2(1.05, 0.3 * taper)) - 1.0) * 0.3 * taper;
    float2 tq = p - float2(-0.95, sin(phase * 0.8 - 1.0) * 0.05);
    float tail = max(sd_tri(tq, float2(0.1, 0.0), float2(-0.42, 0.3), float2(-0.42, -0.3)), -(length((tq - float2(-0.55, 0.0)) / float2(0.25, 0.2)) - 1.0) * 0.2) - 0.012;
    float flap = sin(phase * 1.1) * 0.05;
    float pect = sd_tri(float2(p.x, abs(p.y)), float2(0.75, 0.2), float2(0.45, 0.24), float2(0.3, 0.58 + flap)) - 0.02;
    float pelv = sd_tri(float2(p.x, abs(p.y)), float2(0.0, 0.2), float2(-0.25, 0.18), float2(-0.35, 0.44 - flap)) - 0.018;
    float fins = min(tail, min(pect, pelv));
    float d = min(body, fins);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    if (a <= 0.001) return float4(0.0);
    float lum = max(col.r, max(col.g, col.b));
    float3 brown = col.rgb, pale = mix(col.rgb, float3(0.85, 0.8, 0.68) * lum, 0.6);
    // the belly, pale in the middle; mottled toward the edges and on the fins
    float mott = smoothstep(0.35, 0.65, vnoise(p * 9.0)) * 0.5 + (1.0 - smoothstep(0.2, 0.35, length(fract(p * 7.0) - 0.5))) * 0.4;
    float3 c3 = mix(pale, brown, smoothstep(0.3, 0.95, abs(p.y) / max(0.3 * taper, 0.05)));
    c3 = mix(c3, brown * 0.45, mott * (body > 0.0 ? 0.8 : 0.35));
    c3 *= 0.8 + 0.3 * (1.0 - smoothstep(0.0, 0.3, abs(p.y)));
    if (body > 0.0) c3 *= 0.85 + 0.15 * cos(atan2(abs(p.y) - 0.2, -(p.x - 0.5)) * 30.0);
    // the sucker: a round mouth with a pale lip, opening and closing as it rasps
    float2 m = p - float2(0.95, 0.0);
    float suck = 0.13 + 0.02 * sin(phase * 3.0);
    c3 = mix(c3, pale * 1.15, (1.0 - smoothstep(suck, suck + 0.03, length(m / float2(1.0, 1.1)))) * step(body, 0.0));
    c3 = mix(c3, float3(0.25, 0.1, 0.1) * lum, (1.0 - smoothstep(suck * 0.45, suck * 0.6, length(m))) * step(body, 0.0));
    c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.03, -d)) * 0.25;
    return float4(c3 * a * col.a, a * col.a);
}

// Apple snail: a round golden shell, coiled, with growth lines and a shine; a soft foot under it, two long feelers
// and two short ones waving ahead as it goes. p = c * (1.2, 1.0); the ground at p.y = -0.9. extra.w: 1 moving.
float4 draw_desk_snail(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.2, 1.0);
    float moving = clamp(extra.w, 0.0, 1.0);
    float lum = max(col.r, max(col.g, col.b));
    float stretch = 0.06 * moving * sin(phase * 1.5);
    float foot = sd_box(p - float2(0.1 + stretch * 0.5, -0.78), float2(0.72 + stretch, 0.1), 0.1);
    float2 sc = p - float2(-0.12, -0.2);
    float shell = length(sc / float2(0.62, 0.6)) - 1.0;
    float wave = sin(phase * 1.3) * 0.08 * moving;
    float feel = min(sd_seg(p, float2(0.72, -0.7), float2(1.05, -0.3 + wave)), sd_seg(p, float2(0.66, -0.68), float2(0.88, -0.2 - wave))) - 0.022;
    feel = min(feel, sd_seg(p, float2(0.78, -0.76), float2(1.0, -0.74 + wave * 0.5)) - 0.018);
    float d = min(min(foot, shell * 0.6), feel);
    d = max(d, -(p.y + 0.9));
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    if (a <= 0.001) return float4(0.0);
    float3 gold = col.rgb, flesh = mix(float3(0.95, 0.85, 0.6) * lum, col.rgb, 0.3);
    float3 c3 = flesh * (0.75 + 0.3 * smoothstep(-0.9, -0.6, p.y));
    if (shell < 0.0) {
        float2 b = sc / float2(0.62, 0.6);
        float3 n = normalize(float3(b, sqrt(max(0.02, 1.0 - dot(b, b)))));
        c3 = gold * (0.55 + 0.6 * max(0.0, dot(n, normalize(float3(-0.3, 0.8, 0.5)))));
        // the coil: a spiral of grooves winding in to the apex, and fine growth lines across it
        float2 q = sc - float2(-0.16, 0.1);
        float rr = length(q), th = atan2(q.y, q.x);
        float spiral = abs(fract(log(max(rr, 0.02)) * 1.6 - th / 6.2831) - 0.5);
        c3 *= 1.0 - (1.0 - smoothstep(0.02, 0.08, spiral)) * 0.3;
        c3 *= 0.94 + 0.06 * sin(th * 40.0 + rr * 30.0);
        c3 += float3(1.0) * pow(max(0.0, dot(reflect(-normalize(float3(-0.3, 0.8, 0.5)), n), float3(0.0, 0.0, 1.0))), 20.0) * 0.4;
    }
    // little dark eyes at the base of the long feelers
    c3 = mix(c3, float3(0.03), (1.0 - smoothstep(0.02, 0.035, length(p - float2(0.74, -0.64)))) * step(foot, 0.02));
    c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.03, -d)) * 0.2;
    return float4(c3 * a * col.a, a * col.a);
}

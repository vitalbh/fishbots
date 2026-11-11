// Amazon river creatures: the pirarucu, the pink river dolphin, the river stingray, the pleco and the electric eel;
// and the black caiman, a presence (the theme's look for the shark).

float2 amazon_c_rot(float2 p, float a) {
    float s = sin(a), k = cos(a);
    return float2(p.x * k - p.y * s, p.x * s + p.y * k);
}

float amazon_c_ell(float2 p, float2 ce, float2 r) {
    return (length((p - ce) / r) - 1.0) * min(r.x, r.y);
}

float amazon_c_limb(float2 p, float2 a, float2 b, float ra, float rb) {
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - mix(ra, rb, h);
}

// Pirarucu (arapaima): one of the biggest river fish there is. A long heavy cylinder of a body, a flat bony head
// with the mouth turned up, the dorsal and anal fins set far back against a small round tail, and big scales edged
// in red, more and more toward the tail. p = c * (2.3, 0.6). Crosses slowly.
float4 draw_amazon_pirarucu(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(2.3, 0.6);
    p.y -= sin(phase * 0.9 - p.x * 1.4) * 0.07 * smoothstep(0.8, -2.1, p.x);
    float thin = mix(0.55, 1.0, smoothstep(-2.0, -0.9, p.x)) * mix(0.6, 1.0, smoothstep(2.1, 1.25, p.x));
    float ry = 0.34 * thin;
    float body = amazon_c_ell(p, float2(0.05, 0.0), float2(2.08, ry));
    body = smin_k(body, amazon_c_ell(p, float2(1.72, -0.02), float2(0.36, 0.2)), 0.08);      // the blunt snout
    // the fins at the back: long and low, nearly meeting the tail
    float u = clamp((p.x + 1.9) / 1.25, 0.0, 1.0);
    float prof = pow(sin(u * 3.1416), 0.6);
    float flut = 0.012 * sin(p.x * 16.0 - phase * 2.0);
    float dors = max(max(p.x + 0.65, -1.9 - p.x), max(p.y - (0.16 + 0.3 * prof * (1.0 - 0.3 * u) + flut), -p.y));
    float anal = max(max(p.x + 0.8, -1.9 - p.x), max(-p.y - (0.16 + 0.27 * prof * (1.0 - 0.3 * u) - flut), p.y));
    float2 tq = p - float2(-2.0, 0.0);
    float tail = amazon_c_ell(tq, float2(0.0, 0.0), float2(0.2, 0.27));
    float2 pq = amazon_c_rot(p - float2(1.05, -0.2), -0.5 + sin(phase * 0.8) * 0.2);
    float pect = amazon_c_ell(pq, float2(-0.2, 0.0), float2(0.24, 0.075));
    float pelv = sd_tri(p, float2(-0.15, -0.3), float2(-0.5, -0.27), float2(-0.55, -0.46)) - 0.015;
    float fins = min(min(dors, anal), min(tail, pelv));
    float d = min(min(body, fins), pect);
    if (d > 0.05) return float4(0.0);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float lum = dot(col.rgb, float3(0.75));
    float3 olive = col.rgb;
    float3 red = float3(0.9, 0.2, 0.13) * lum;
    float3 cream = mix(col.rgb, float3(1.0, 0.95, 0.8) * lum, 0.7);
    float redness = smoothstep(0.7, -1.5, p.x);
    float yn = p.y / max(ry, 0.05);
    float3 c3;
    if (body < 0.0) {
        c3 = mix(olive, cream, smoothstep(-0.2, -0.95, yn));
        if (p.x < 1.25) {
            // the scales: big, each darker at its root and, toward the tail, with a red crescent on its edge
            float2 sq = p * float2(5.5, 8.5);
            sq.x += fmod(floor(sq.y), 2.0) * 0.5;
            float2 sf = fract(sq) - float2(0.62, 0.5);
            float sr = length(sf);
            float cres = smoothstep(0.26, 0.36, sr) * (1.0 - smoothstep(0.44, 0.54, sr)) * step(sf.x, 0.05);
            c3 *= 0.86 + 0.2 * smoothstep(0.5, 0.1, sr);
            c3 = mix(c3, red, cres * redness * smoothstep(1.0, -0.2, yn));
            c3 = mix(c3, olive * 0.45, cres * (1.0 - redness) * 0.5);
        } else {
            // the head: bony plates, a pale cheek and lower jaw
            c3 = mix(olive * 0.9, cream, smoothstep(0.1, -0.6, yn) * 0.8);
            c3 *= 0.86 + 0.14 * smoothstep(0.02, 0.08, vor_edge(p * float2(5.0, 8.0)));
            float garc = abs(length((p - float2(1.38, -0.02)) * float2(1.0, 0.8)) - 0.2);
            c3 *= 1.0 - (1.0 - smoothstep(0.005, 0.02, garc)) * step(p.x, 1.45) * 0.3;
        }
        float qy = clamp(yn, -1.0, 1.0);
        float3 n = normalize(float3(0.0, qy, sqrt(max(0.03, 1.0 - qy * qy))));
        float li = dot(n, normalize(float3(-0.3, 0.8, 0.5)));
        c3 *= 0.6 + 0.58 * li;
        c3 += float3(1.0, 0.98, 0.9) * pow(max(0.0, li), 7.0) * 0.14 * lum;
        float mouth = sd_seg(p, float2(1.8, -0.06), float2(2.08, 0.03));                 // turned up
        c3 = mix(c3, olive * 0.25, (1.0 - smoothstep(0.006, 0.018, mouth)) * 0.9);
        float re = length(p - float2(1.74, 0.07));
        c3 = mix(c3, float3(0.95, 0.75, 0.35) * lum, 1.0 - smoothstep(0.038, 0.048, re));
        c3 = mix(c3, float3(0.02), 1.0 - smoothstep(0.02, 0.028, re));
        float rim = 1.0 - smoothstep(0.0, 0.03, -body);
        c3 += cream * rim * smoothstep(0.2, 0.9, yn) * 0.2;
        c3 *= 1.0 - rim * smoothstep(0.0, -0.9, yn) * 0.3;
    } else if (min(tail, min(dors, anal)) < pelv) {
        // the back fins and the tail: dark, streaked and edged with red
        float streak = smoothstep(0.35, 0.75, vnoise(float2(p.x * 22.0 + abs(p.y) * 10.0, abs(p.y) * 5.0)));
        c3 = mix(olive * 0.4, red, 0.2 + 0.55 * streak);
        c3 = mix(c3, red * 1.15, smoothstep(-0.05, -0.005, min(tail, min(dors, anal))) * 0.7);
        c3 *= 0.8 + 0.3 * smoothstep(-0.4, 0.4, p.y);
    } else {
        c3 = mix(olive * 0.6, red, 0.35);
    }
    if (pect < 0.0) c3 = mix(c3, olive * 0.55 * (0.85 + 0.2 * cos(atan2(pq.y, pq.x + 0.5) * 24.0)), 0.85);
    c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.02, -d)) * 0.2;
    float al = a * col.a * (body < 0.0 ? 1.0 : 0.92);
    return float4(c3 * al, al);
}

// Boto (pink river dolphin): a heavy pink body going grey on the back, a round melon of a forehead, a long thin
// beak, a low ridge instead of a dorsal fin, wide paddles for flippers. It swims the way dolphins do, the tail
// beating up and down. p = c * (2.0, 0.8). Passes far away.
float4 draw_amazon_boto(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(2.0, 0.8);
    float beat = phase * 0.5;
    p.y -= sin(beat - p.x * 1.3) * 0.1 * smoothstep(0.5, -1.7, p.x) + sin(beat + 0.6) * 0.02;
    float thin = mix(0.24, 1.0, smoothstep(-1.5, -0.25, p.x));
    float ry = 0.35 * thin;
    float body = amazon_c_ell(p, float2(-0.05, 0.0), float2(1.3, ry));
    float melon = amazon_c_ell(p, float2(0.98, 0.1), float2(0.3, 0.26));
    float beak = amazon_c_limb(p, float2(1.15, -0.02), float2(1.84, -0.1), 0.075, 0.032);
    float d = smin_k(smin_k(body, melon, 0.14), beak, 0.06);
    float ridge = sd_tri(p, float2(0.05, 0.28), float2(-0.8, 0.2), float2(-0.42, 0.45)) - 0.04;
    d = smin_k(d, ridge, 0.08);
    float2 fq = amazon_c_rot(p - float2(0.55, -0.24), -0.95 + sin(beat) * 0.25);
    float flip = amazon_c_ell(fq, float2(0.26, 0.0), float2(0.32, 0.12));
    float2 tq = p - float2(-1.3, 0.0);
    tq = amazon_c_rot(tq, -cos(beat + 1.6) * 0.35);
    float fluke = sd_tri(tq, float2(0.12, 0.0), float2(-0.42, 0.2), float2(-0.36, -0.14)) - 0.03;
    d = min(smin_k(d, fluke, 0.05), flip);
    if (d > 0.05) return float4(0.0);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float3 pink = col.rgb;
    float3 grey = mix(col.rgb, float3(0.5, 0.5, 0.55) * dot(col.rgb, float3(0.6)), 0.75);
    float yn = p.y / max(ry, 0.08);
    float3 c3 = mix(pink * 1.1, grey, smoothstep(0.1, 0.9, yn + 0.4 * vnoise(p * float2(3.0, 5.0))));
    c3 = mix(c3, grey, smoothstep(0.75, 0.9, vnoise(p * 7.0)) * 0.35);                  // old scars and mottles
    c3 *= 0.68 + 0.42 * smoothstep(-1.0, 0.9, yn);
    c3 += float3(1.0) * pow(max(0.0, 1.0 - length((p - float2(0.3, 0.2)) / float2(0.8, 0.09))), 2.0) * 0.12 * dot(col.rgb, float3(0.6));
    if (flip < 0.0) c3 = mix(pink, grey, 0.4) * (0.6 + 0.3 * smoothstep(-0.1, 0.1, fq.y));
    float mouth = sd_seg(p, float2(1.12, -0.07), float2(1.8, -0.11));
    c3 *= 1.0 - (1.0 - smoothstep(0.004, 0.014, mouth)) * 0.5;
    c3 = mix(c3, float3(0.03), 1.0 - smoothstep(0.022, 0.032, length(p - float2(1.1, 0.05))));
    c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.03, -d)) * 0.22 * smoothstep(0.3, -0.5, yn);
    return float4(c3 * a * col.a, a * col.a);
}

// Ocellate river stingray (Potamotrygon motoro): a flat brown disc on the bottom, orange eye-spots ringed in black
// all over it, the eyes on two bumps, a thick tail with its sting. Seen from the side and a little from above; when
// it moves the edge of the disc ripples. p = c * (1.7, 0.45); the ground at p.y = -0.405.
float4 draw_amazon_stingray(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.7, 0.45);
    float moving = extra.w;
    float2 dc = float2(0.4, -0.2);
    float rimw = smoothstep(0.35, 0.9, abs(p.x - dc.x));
    p.y -= sin(phase * 1.4 - p.x * 5.0) * 0.04 * rimw * (0.25 + 0.75 * moving);
    float disc = amazon_c_ell(p, dc, float2(0.92, 0.2));
    float hump = amazon_c_ell(p, float2(0.46, -0.08), float2(0.46, 0.18));
    float body = smin_k(disc, hump, 0.12);
    float eyes = min(length(p - float2(0.78, 0.07)) - 0.06, length(p - float2(0.6, 0.09)) - 0.055);
    body = smin_k(body, eyes, 0.03);
    float sway = sin(phase * 0.7) * 0.05 * (0.4 + 0.6 * moving);
    float tail = amazon_c_limb(p, float2(-0.3, -0.27), float2(-1.58, -0.2 + sway), 0.075, 0.014);
    float sting = sd_tri(p, float2(-0.85, -0.2 + sway * 0.4), float2(-1.2, -0.08 + sway * 0.7), float2(-0.98, -0.22 + sway * 0.5)) - 0.005;
    float d = min(smin_k(body, tail, 0.05), sting);
    d = max(d, -p.y - 0.41);                                                          // flat on the ground
    if (d > 0.05) return float4(0.0);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float lum = dot(col.rgb, float3(0.85));
    float3 brown = col.rgb;
    float3 c3 = brown * (0.8 + 0.3 * vnoise(p * float2(9.0, 22.0)));
    // the eye-spots: orange hearts in black rings, flattened by the low view
    float2 sg = float2(p.x * 5.2, (p.y + 0.2) * 11.5);
    sg.x += 0.5 * fmod(floor(sg.y), 2.0);
    float2 sid = floor(sg);
    float2 sj = fract(sg) - 0.5 - (float2(hash21(sid), hash21(sid + 4.7)) - 0.5) * 0.3;
    float sr = length(sj);
    float onDisc = step(body, -0.015) * step(0.015, eyes);
    c3 = mix(c3, float3(0.07, 0.05, 0.04), (1.0 - smoothstep(0.31, 0.39, sr)) * onDisc);
    c3 = mix(c3, float3(1.0, 0.62, 0.15) * lum, (1.0 - smoothstep(0.17, 0.25, sr)) * onDisc);
    // lit from above: the top of the hump bright, the margin thin and paler, a shadow under the edge
    c3 *= 0.58 + 0.6 * smoothstep(-0.38, 0.05, p.y);
    c3 = mix(c3, brown * 1.5, (1.0 - smoothstep(0.0, 0.03, -body)) * smoothstep(-0.28, -0.08, p.y) * 0.5);
    if (tail < body && tail < 0.0) c3 = brown * (0.55 + 0.4 * smoothstep(-0.3, -0.15, p.y)) * (0.8 + 0.3 * step(0.5, fract(p.x * 8.0)));
    if (sting < 0.0 && sting < min(body, tail)) c3 = brown * 1.7;
    // the eyes: a gold ring and a dark pupil on each bump
    for (int i = 0; i < 2; i++) {
        float2 e = i == 0 ? float2(0.795, 0.085) : float2(0.61, 0.105);
        float re = length(p - e);
        c3 = mix(c3, float3(0.9, 0.75, 0.4) * lum, 1.0 - smoothstep(0.03, 0.04, re));
        c3 = mix(c3, float3(0.02), 1.0 - smoothstep(0.015, 0.024, re));
    }
    c3 *= 0.5 + 0.5 * smoothstep(-0.42, -0.3, p.y);                                    // contact shadow
    return float4(c3 * a * col.a, a * col.a);
}

// Pleco (cascudo), seen from its back as it holds on to the glass: a wide armored head, the body narrowing to a
// forked tail, round pectoral fins held out to the sides and smaller pelvic ones, pale spots all over. It faces +x,
// the way it climbs. p = c * (1.5, 0.8).
float4 draw_amazon_pleco(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.5, 0.8);
    float moving = extra.w;
    p.y -= sin(phase * 1.5 - p.x * 2.6) * 0.07 * smoothstep(0.3, -1.3, p.x) * (0.25 + 0.75 * moving);
    float ay = abs(p.y);
    float2 s = float2(p.x, ay);
    float head = amazon_c_ell(p, float2(0.8, 0.0), float2(0.52, 0.4));
    float trunk = amazon_c_limb(p, float2(0.7, 0.0), float2(-0.85, 0.0), 0.33, 0.07);
    float body = smin_k(head, trunk, 0.1);
    float fa = sin(phase * 1.5) * 0.12 * moving;
    float2 pp = amazon_c_rot(s - float2(0.62, 0.3), 0.95 + fa);
    float pect = amazon_c_ell(pp, float2(-0.24, 0.0), float2(0.28, 0.12));
    float2 vp = amazon_c_rot(s - float2(-0.18, 0.18), 0.7 + fa);
    float pelv = amazon_c_ell(vp, float2(-0.16, 0.0), float2(0.19, 0.08));
    float2 tq = p - float2(-0.85, 0.0);
    float tail = sd_tri(float2(tq.x, abs(tq.y)), float2(0.08, 0.0), float2(-0.52, 0.36), float2(-0.38, 0.0)) - 0.03;
    float fins = min(min(pect, pelv), tail);
    float d = min(body, fins);
    if (d > 0.05) return float4(0.0);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float lum = dot(col.rgb, float3(0.9));
    float3 brown = col.rgb;
    float3 pale = mix(col.rgb, float3(1.0, 0.88, 0.55) * lum, 0.8);
    float2 sg = p * float2(10.0, 10.0);
    sg.x += 0.5 * fmod(floor(sg.y), 2.0);
    float2 sid = floor(sg);
    float spot = 1.0 - smoothstep(0.15, 0.27, length(fract(sg) - 0.5 - (float2(hash21(sid), hash21(sid + 2.3)) - 0.5) * 0.4));
    float3 c3;
    if (body < 0.0) {
        float w = mix(0.07, 0.38, smoothstep(-0.85, 0.75, p.x));
        float yn = clamp(p.y / w, -1.0, 1.0);
        c3 = brown * (0.6 + 0.55 * sqrt(max(0.0, 1.0 - yn * yn)));                      // round across the back
        c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.25, abs(fract(p.x * 7.0) - 0.5))) * 0.14 * step(p.x, 0.5);   // rows of plates
        c3 = mix(c3, pale, spot * 0.75);
        // the dorsal fin folded along the back
        float dfin = amazon_c_ell(p, float2(0.0, 0.0), float2(0.38, 0.055));
        c3 = mix(c3, brown * 0.45, 1.0 - smoothstep(-0.01, 0.015, dfin));
        float re = length(s - float2(0.95, 0.23));
        c3 = mix(c3, float3(0.95, 0.75, 0.3) * lum, 1.0 - smoothstep(0.04, 0.05, re));
        c3 = mix(c3, float3(0.02), 1.0 - smoothstep(0.02, 0.03, re));
        c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.03, -body)) * 0.3;
    } else {
        float2 o = pect < min(pelv, tail) ? float2(0.62, 0.3) : (pelv < tail ? float2(-0.18, 0.18) : float2(-0.75, 0.0));
        float rays = 0.5 + 0.5 * cos(atan2(s.y - o.y, s.x - o.x) * 24.0);
        c3 = brown * (0.72 + 0.3 * rays);
        c3 = mix(c3, pale, spot * 0.55);
        c3 = mix(c3, pale * 0.9, smoothstep(-0.03, 0.0, fins) * 0.35);
    }
    float al = a * col.a * (body < 0.0 ? 1.0 : 0.86);
    return float4(c3 * al, al);
}

// Poraquê (electric eel): a long, thick, dark knifefish with a blunt flat head, an orange throat, and one fin
// rippling along the whole underside; now and then it lets out a discharge, and light crackles along its body.
// p = c * (2.2, 0.55). Crosses low, near the bottom.
float4 draw_amazon_poraque(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(2.2, 0.55);
    p.y -= sin(phase * 0.8 - p.x * 2.3) * 0.1 * smoothstep(1.9, -1.2, p.x);
    float h = clamp((1.6 - p.x) / 3.65, 0.0, 1.0);
    float rr = mix(0.22, 0.07, h);
    float body = amazon_c_limb(p, float2(1.6, 0.03), float2(-2.05, 0.0), 0.22, 0.07);
    float head = amazon_c_ell(p, float2(1.66, 0.02), float2(0.42, 0.21));
    body = smin_k(body, head, 0.08);
    float rip = 0.022 * sin(p.x * 13.0 - phase * 3.0);
    float fin = max(max(p.x - 1.15, -2.12 - p.x), max(p.y, -p.y - rr - 0.1 - rip));
    float d = min(body, fin);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float lum = dot(col.rgb, float3(1.0));
    float3 dark = col.rgb;
    float3 orange = float3(1.0, 0.5, 0.15) * lum * 1.1;
    float yn = clamp(p.y / rr, -1.0, 1.0);
    float3 c3;
    if (body < 0.0) {
        c3 = dark * (0.5 + 0.6 * smoothstep(-0.9, 0.7, yn));
        c3 = mix(c3, orange, smoothstep(0.1, -0.6, yn) * smoothstep(0.6, 1.4, p.x) * 0.9);     // the throat
        c3 += float3(1.0) * pow(max(0.0, 1.0 - abs(yn - 0.45) * 2.5), 2.0) * 0.1 * lum;
        // pits of the lateral line, the mouth, a tiny eye
        c3 *= 1.0 - (1.0 - smoothstep(0.1, 0.22, length(float2(fract(p.x * 8.0) - 0.5, (p.y - 0.02) * 8.0)))) * 0.3 * step(p.x, 1.25);
        float mouth = sd_seg(p, float2(1.76, -0.06), float2(2.06, -0.01));
        c3 *= 1.0 - (1.0 - smoothstep(0.005, 0.016, mouth)) * 0.7;
        float re = length(p - float2(1.84, 0.09));
        c3 = mix(c3, float3(0.75, 0.8, 0.85) * lum * 0.9, 1.0 - smoothstep(0.03, 0.04, re));
        c3 = mix(c3, float3(0.02), 1.0 - smoothstep(0.015, 0.024, re));
        c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.025, -body)) * 0.25 * step(yn, 0.0);
    } else {
        c3 = dark * 0.6 * (0.8 + 0.3 * cos(p.x * 60.0 + p.y * 30.0));
    }
    // the discharge: a few seconds dark, then light flickering along the body and just off it
    float pulse = pow(max(0.0, sin(phase * 0.22 + extra.y * 6.0)), 14.0);
    float flick = 0.45 + 0.55 * vnoise(float2(p.x * 7.0 - phase * 5.0, phase * 9.0));
    float bolt = 1.0 - smoothstep(0.0, 0.035, abs(p.y - rr * 0.2 - 0.12 * (vnoise(float2(p.x * 6.0, floor(phase * 5.0))) - 0.5)));
    float3 spark = float3(0.75, 0.92, 1.0);
    c3 += spark * pulse * flick * (0.25 + 0.9 * bolt * step(body, 0.0));
    float al = a * col.a * (body < 0.0 ? 1.0 : 0.8);
    float edge = 1.0 - smoothstep(0.6, 1.0, max(abs(c.x), abs(c.y)));
    float halo = pulse * flick * exp(-max(d, 0.0) * 16.0) * edge * (1.0 - a) * col.a * 0.8;
    return float4(c3 * al + spark * halo, min(1.0, al + halo * 0.5));
}

// Jacaré-açu (black caiman), swimming: legs folded back, the long tail doing the work, a flat head with the eyes and
// the nostrils on bumps, a saw of scutes down the back and the tail, pale bands on the flanks and the jaw, the teeth
// showing. A presence that swims (the theme's look for the shark): extra.w is its state (it shakes on an error) and
// glow rises when it wants attention. p = c * (2.0, 0.6).
float4 draw_amazon_jacare(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(2.0, 0.6);
    if (abs(extra.w - 5.0) < 0.5) p += float2(sin(phase * 40.0), cos(phase * 33.0)) * 0.012;
    p.y -= sin(phase * 1.4 - p.x * 2.4) * 0.085 * smoothstep(0.3, -1.8, p.x);
    float torso = amazon_c_ell(p, float2(0.2, -0.02), float2(0.8, 0.25));
    float tail = amazon_c_limb(p, float2(-0.3, 0.0), float2(-1.88, 0.0), 0.2, 0.025);
    float head = amazon_c_limb(p, float2(0.9, 0.02), float2(1.76, -0.03), 0.175, 0.09);
    float body = smin_k(smin_k(torso, tail, 0.12), head, 0.1);
    body = smin_k(body, length(p - float2(1.08, 0.18)) - 0.06, 0.04);                       // the eye's bump
    body = smin_k(body, length(p - float2(1.78, 0.05)) - 0.045, 0.03);                        // the nostrils
    // scutes: a saw along the back, taller on the tail
    float saw = abs(fract(p.x * 7.0) - 0.5) * 2.0;
    body -= (0.012 + 0.04 * saw) * step(0.0, p.y) * smoothstep(0.85, 0.6, p.x) * smoothstep(-1.9, -1.6, p.x) * (0.6 + 0.4 * smoothstep(0.0, -0.6, p.x));
    // legs, folded back along the body, paddling a little
    float pd = sin(phase * 1.4) * 0.05;
    float2 f0 = float2(0.62, -0.17), f1 = float2(0.36 + pd, -0.38), f2 = float2(0.18 + pd, -0.41);
    float fore = min(amazon_c_limb(p, f0, f1, 0.065, 0.04), amazon_c_limb(p, f1, f2, 0.04, 0.03));
    float2 h0 = float2(-0.25, -0.15), h1 = float2(-0.55 - pd, -0.36), h2 = float2(-0.8 - pd, -0.38);
    float hind = min(amazon_c_limb(p, h0, h1, 0.08, 0.05), amazon_c_limb(p, h1, h2, 0.05, 0.03));
    float legs = min(fore, hind);
    float d = min(body, legs);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float lum = dot(col.rgb, float3(1.1));
    float3 dark = col.rgb * 0.55;
    float3 pale = mix(col.rgb, float3(0.95, 0.9, 0.62) * lum, 0.75);
    float w = p.x > 0.85 ? mix(0.175, 0.09, clamp((p.x - 0.9) / 0.86, 0.0, 1.0)) : (p.x < -0.3 ? mix(0.2, 0.025, clamp((-0.3 - p.x) / 1.58, 0.0, 1.0)) : 0.25);
    float yn = p.y / max(w, 0.03);
    float3 c3;
    if (body < legs) {
        c3 = mix(pale, dark, smoothstep(-0.75, -0.1, yn));                                    // a pale belly
        // pale bands across the flanks and the tail, fading on the back
        float band = smoothstep(0.55, 0.9, cos(p.x * 9.5 + yn * 0.6)) * smoothstep(0.75, 0.0, yn) * smoothstep(0.9, 0.5, p.x);
        c3 = mix(c3, pale * 0.85, band * 0.4);
        c3 *= 0.8 + 0.2 * smoothstep(0.03, 0.1, vor_edge(p * float2(9.0, 13.0)));              // the hide's plates
        c3 *= 0.62 + 0.5 * smoothstep(-1.0, 0.9, yn);
        c3 += float3(0.8, 0.9, 0.8) * (1.0 - smoothstep(0.0, 0.03, -body)) * smoothstep(0.3, 1.0, yn) * 0.16 * lum;
        // the jaw line with its teeth, the banded lower jaw
        float tx = clamp((p.x - 1.05) / 0.76, 0.0, 1.0);
        float my = mix(-0.03, -0.06, tx);
        float mouth = abs(p.y - my) - 0.006;
        float inJaw = step(1.05, p.x) * step(p.x, 1.81);
        c3 = mix(c3, pale * (0.75 + 0.25 * step(0.5, fract(p.x * 6.0))), step(p.y, my) * inJaw * 0.7);
        c3 = mix(c3, dark * 0.3, (1.0 - smoothstep(0.0, 0.012, mouth)) * inJaw);
        float teeth = abs(fract(p.x * 13.0) - 0.5) * 0.07 - abs(p.y - my + 0.012);
        c3 = mix(c3, float3(0.97, 0.96, 0.88), step(0.0, teeth) * inJaw * step(1.15, p.x));
        // the eye: yellow, a slit pupil
        float2 e = p - float2(1.08, 0.185);
        float re = length(e);
        c3 = mix(c3, float3(0.95, 0.8, 0.25), 1.0 - smoothstep(0.03, 0.04, re));
        c3 = mix(c3, float3(0.02), (1.0 - smoothstep(0.006, 0.012, abs(e.x))) * step(re, 0.032));
    } else {
        c3 = dark * (0.7 + 0.4 * smoothstep(-0.4, -0.1, p.y)) * (0.85 + 0.15 * smoothstep(0.03, 0.1, vor_edge(p * float2(12.0, 14.0))));
    }
    c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.025, -d)) * 0.22 * step(p.y, 0.0);
    c3 += col.rgb * glow * 0.35;
    float edge = 1.0 - smoothstep(0.6, 1.0, max(abs(c.x), abs(c.y)));
    float halo = glow * exp(-max(d, 0.0) * 10.0) * edge;
    return float4(c3 * a + col.rgb * halo * (1.0 - a), a + halo * (1.0 - a) * 0.5);
}

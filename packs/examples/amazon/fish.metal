// Amazon river fish: the discus, the red-bellied piranha, the tucunaré (peacock bass) and the cardinal tetra.

float2 amazon_rot(float2 p, float a) {
    float s = sin(a), k = cos(a);
    return float2(p.x * k - p.y * s, p.x * s + p.y * k);
}

float amazon_ell(float2 p, float2 ce, float2 r) {
    return (length((p - ce) / r) - 1.0) * min(r.x, r.y);
}

// An eye with its iris and a glint; asleep it's a short curved line.
float3 amazon_eye(float3 c3, float2 p, float2 e, float r, float3 iris, bool asleep) {
    float re = length(p - e);
    if (asleep) {
        float lid = abs(p.y - e.y + (p.x - e.x) * (p.x - e.x) / r * 0.6) - r * 0.14;
        return mix(c3, float3(0.05), (1.0 - smoothstep(0.0, r * 0.2, lid)) * step(re, r));
    }
    c3 = mix(c3, iris, 1.0 - smoothstep(r * 0.85, r, re));
    c3 = mix(c3, float3(0.02), 1.0 - smoothstep(r * 0.45, r * 0.6, re));
    return mix(c3, float3(1.0), 1.0 - smoothstep(r * 0.12, r * 0.25, length(p - e - float2(r * 0.25, r * 0.3))));
}

// Discus (acará-disco): a tall disc of a fish, the dorsal and anal fins running all around the back of it, a small
// fan of a tail, two thin pelvic fins hanging, a red eye. The quad is 1.1 × 1.0. Variety by extra.y, always in the
// project's color: 0 wild (dark vertical bars, the Heckel's three stronger), 1 royal (wavy pale striations all
// over), 2 leopard (darker spots on a pale body), 3 solid, with a pale face and a dark band on the fins.
float4 draw_amazon_discus(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.1, 1.0);
    int pat = int(extra.y + 0.5) % 4;
    bool asleep = extra.w > 1.5;
    float seed = fract(dot(col.rgb, float3(12.9898, 78.233, 37.719)) * 43.758);
    p.y -= sin(phase - p.x * 2.0) * 0.045 * smoothstep(0.1, -1.0, p.x);
    float2 bc = float2(0.14, 0.0), br = float2(0.6, 0.55);
    float body = amazon_ell(p, bc, br);
    // the fins: a wider ring behind the forehead, open where the tail stock comes out
    float ring = amazon_ell(p, float2(0.03, 0.0), float2(0.68, 0.78));
    ring += 0.004 * sin(atan2(p.y, p.x - 0.1) * 46.0) * smoothstep(0.0, -0.3, p.x);          // the soft edge, scalloped
    float fins = max(ring, max(p.x - 0.36 - 0.25 * abs(p.y), 0.12 - abs(p.y)));
    fins = min(fins, sd_tri(float2(p.x, abs(p.y)), float2(-0.28, 0.5), float2(-0.5, 0.25), float2(-0.62, 0.58)) - 0.035);   // the fins' trailing tips
    float sw = sin(phase - 1.3) * 0.05;
    float2 tq = p - float2(-0.42, 0.0);
    tq.y -= sw * smoothstep(0.0, -0.4, tq.x);
    float tail = max(sd_tri(tq, float2(0.05, 0.0), float2(-0.5, 0.36), float2(-0.5, -0.36)), length(tq) - 0.5) - 0.012;
    // pelvic fins: two thin streamers, trailing a little
    float sway = sin(phase * 0.8) * 0.04;
    float pt = clamp((-0.46 - p.y) / 0.46, 0.0, 1.0);
    float pelv = min(sd_seg(p, float2(0.34, -0.44), float2(0.16 + sway, -0.93)),
                     sd_seg(p, float2(0.28, -0.46), float2(0.04 + sway, -0.86))) - mix(0.035, 0.008, pt);
    float2 pq = amazon_rot(p - float2(0.3, -0.12), -0.5 + sin(phase * 1.1) * 0.3);
    float pect = amazon_ell(pq, float2(-0.11, 0.0), float2(0.14, 0.07));
    float d = min(min(body, fins), min(tail, pelv));
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);

    float3 base = col.rgb;
    float3 pale = mix(base, float3(0.98, 0.9, 0.7), 0.6);
    float3 dark = base * 0.28 + float3(0.03, 0.02, 0.02);
    float3 skin = base;
    float wavy = sin(p.y * 62.0 + sin(p.x * 7.0 + seed * 6.0) * 2.4 + sin(p.x * 17.0 + p.y * 5.0) * 0.8 + seed * 9.0);
    if (pat == 0) {
        skin = mix(base, float3(0.72, 0.48, 0.24), 0.35);
        float bx = (p.x - 0.14) * 21.0;
        float bars = smoothstep(0.5, 0.9, cos(bx));
        float strong = max(max(exp(-pow((p.x - 0.5) * 11.0, 2.0)), exp(-pow((p.x - 0.14) * 11.0, 2.0))), exp(-pow((p.x + 0.38) * 11.0, 2.0)));
        skin = mix(skin, dark, bars * (0.12 + 0.55 * strong));
        skin = mix(skin, pale, smoothstep(0.5, 0.95, wavy) * 0.22);
    } else if (pat == 1) {
        skin = mix(base * 0.78, mix(pale, float3(0.75, 1.0, 0.98), 0.35) * 1.1, smoothstep(0.15, 0.75, wavy) * 0.85);
    } else if (pat == 2) {
        skin = pale;
        float2 sg = p * 12.0 + seed * 13.0;
        sg.x += 0.5 * fmod(floor(sg.y), 2.0);
        float2 sid = floor(sg);
        float2 jit = (float2(hash21(sid), hash21(sid + 7.3)) - 0.5) * 0.5;
        float sr = 0.14 + 0.16 * hash21(sid + 3.1);
        float spot = (1.0 - smoothstep(sr, sr + 0.1, length(fract(sg) - 0.5 - jit))) * step(0.22, hash21(sid + 9.7));
        skin = mix(skin, base * 0.72, spot * 0.9);
    } else {
        skin = mix(base, mix(base, float3(1.0, 0.9, 0.55), 0.7), smoothstep(0.25, 0.62, p.x));
        skin = mix(skin, base * 0.6, smoothstep(0.6, 0.95, cos((p.x - 0.14) * 21.0)) * 0.22 * smoothstep(0.4, 0.2, p.x));
    }
    float3 c3;
    bool finRing = body >= 0.0 && fins < 0.0 && fins <= min(tail, pelv);
    if (body < 0.0 || finRing) {
        // a flat disc, not a ball: lit from above, a soft sheen across the shoulder, the pattern running on into the fins
        c3 = skin * (0.74 + 0.36 * smoothstep(-0.75, 0.7, p.y));
        float2 hs = (p - float2(0.2, 0.2)) / float2(0.42, 0.2);
        c3 += float3(1.0, 0.97, 0.9) * pow(max(0.0, 1.0 - dot(hs, hs)), 2.0) * 0.13;
        if (finRing) {
            float w = clamp(-fins / 0.14, 0.0, 1.0), into = clamp(body / 0.16, 0.0, 1.0);
            c3 *= 1.0 - 0.2 * into;
            c3 = mix(c3, pale, smoothstep(0.2, 0.9, wavy) * 0.25);
            c3 *= 0.93 + 0.07 * cos(atan2(p.y, p.x - 0.1) * 60.0);                              // fin rays
            if (pat == 3) c3 = mix(c3, dark, smoothstep(0.25, 0.5, into) * (1.0 - smoothstep(0.7, 0.9, into)) * 0.8);
            c3 = mix(mix(base, float3(1.0, 0.5, 0.32), 0.5) * 1.15, c3, smoothstep(0.0, 0.32, w));   // the warm edge
        } else {
            // the gill cover, a few wavy lines on the forehead, the eye and the small mouth
            float garc = abs(length((p - float2(0.42, -0.03)) * float2(1.0, 0.75)) - 0.15);
            c3 *= 1.0 - (1.0 - smoothstep(0.004, 0.02, garc)) * step(p.x, 0.5) * step(abs(p.y + 0.03), 0.16) * 0.14;
            c3 = mix(c3, pale, smoothstep(0.3, 0.8, wavy) * smoothstep(0.2, 0.5, p.y) * smoothstep(0.1, 0.4, p.x) * (pat == 1 ? 0.0 : 0.4));
            c3 = amazon_eye(c3, p, float2(0.53, 0.1), 0.062, float3(0.85, 0.16, 0.1), asleep);
            c3 = mix(c3, dark, (1.0 - smoothstep(0.0, 0.012, sd_seg(p, float2(0.735, -0.03), float2(0.69, -0.04)))) * 0.7);
        }
        float rim = 1.0 - smoothstep(0.0, 0.03, -min(body, fins));
        c3 += float3(1.0, 0.92, 0.75) * rim * smoothstep(0.1, 0.5, p.y) * 0.22;
    } else if (pelv < tail) {
        c3 = mix(dark, base, 0.5 + 0.5 * pt);
    } else {
        float rays = 0.5 + 0.5 * cos(atan2(tq.y, -tq.x + 0.1) * 30.0);
        c3 = mix(pale, base, 0.35) * (0.82 + 0.18 * rays);
        c3 = mix(c3, dark, (1.0 - smoothstep(0.0, 0.12, -tq.x)) * 0.6);
    }
    if (pect < 0.0 && body < 0.0) c3 = mix(c3, pale * (0.85 + 0.15 * cos(atan2(pq.y, pq.x + 0.3) * 22.0)), 0.3);
    c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.02, -d)) * 0.25 * smoothstep(0.2, -0.4, p.y);
    c3 += col.rgb * glow * 0.45;
    float finA = body < 0.0 ? 1.0 : (finRing ? 0.94 : 0.84);
    float al = a * col.a * finA;
    float edge = 1.0 - smoothstep(0.6, 1.0, max(abs(c.x), abs(c.y)));
    float halo = glow * exp(-max(d, 0.0) * 12.0) * edge * (1.0 - a) * col.a;
    return float4(c3 * al + col.rgb * halo, min(al + halo * 0.55, 1.0));
}

// Red-bellied piranha: a deep, blunt fish with a bulldog jaw and a row of teeth, a steel back, glittering flanks and
// the belly, throat and anal fin in the project's color. Variety by extra.y: 0 red-bellied, 1 black piranha (dark all
// over, the color burning low on the belly and in the eye), 2 spotted (the young ones), 3 the color washed up the
// whole flank with a black blotch behind the gill.
float4 draw_amazon_piranha(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.25, 0.8);
    int pat = int(extra.y + 0.5) % 4;
    bool asleep = extra.w > 1.5;
    p.y -= sin(phase - p.x * 2.4) * 0.045 * smoothstep(0.2, -1.0, p.x);
    float thin = mix(0.26, 1.0, smoothstep(-0.8, -0.15, p.x));
    float2 bc = float2(0.05, -0.02);
    float2 br = float2(0.76, 0.47 * thin);
    float body = amazon_ell(p, bc, br);
    float head = amazon_ell(p, float2(0.5, 0.0), float2(0.36, 0.36));                 // a blunt, high forehead
    float jaw = amazon_ell(p, float2(0.78, -0.2), float2(0.15, 0.085));               // the lower jaw, sticking out
    body = smin_k(smin_k(body, head, 0.1), jaw, 0.05);
    float dors = sd_tri(p, float2(0.08, 0.4), float2(-0.42, 0.3), float2(-0.3, 0.64 + 0.015 * sin(phase * 1.3))) - 0.015;
    float adip = amazon_ell(p, float2(-0.6, 0.2 + 0.02), float2(0.06, 0.045));
    float anal = sd_tri(p, float2(-0.1, -0.4), float2(-0.66, -0.12), float2(-0.52, -0.56)) - 0.015;
    float2 tq = p - float2(-0.74, sin(phase - 1.2) * 0.05);
    float tail = sd_tri(tq, float2(0.08, 0.0), float2(-0.42, 0.36), float2(-0.42, -0.36));
    tail = max(tail, -amazon_ell(tq, float2(-0.5, 0.0), float2(0.13, 0.2))) - 0.012;
    float2 pq = amazon_rot(p - float2(0.34, -0.22), -0.6 + sin(phase) * 0.25);
    float pect = amazon_ell(pq, float2(-0.1, 0.0), float2(0.13, 0.055));
    float fins = min(min(dors, anal), min(tail, adip));
    float d = min(body, fins);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);

    float3 red = col.rgb;
    float3 steel = mix(float3(0.36, 0.41, 0.44), col.rgb, 0.12);
    float3 silver = mix(float3(0.8, 0.8, 0.74), col.rgb, 0.12);
    float yn = (p.y - bc.y) / max(br.y, 0.05);
    float3 c3;
    if (body < 0.0) {
        float belly = smoothstep(0.05, -0.55, yn);                                    // how far down toward the belly
        float up = pat == 3 ? smoothstep(0.75, -0.2, yn) : belly;
        float3 flank = mix(steel, silver, smoothstep(0.75, 0.0, yn));
        if (pat == 1) flank = mix(float3(0.1, 0.1, 0.12), float3(0.26, 0.26, 0.28), smoothstep(0.6, -0.4, yn));
        c3 = mix(flank, red, up * (pat == 1 ? 0.75 : 0.95) * smoothstep(-0.6, -0.1, p.x - 0.3 * yn));
        c3 = mix(c3, red, (1.0 - smoothstep(-0.02, 0.1, amazon_ell(p, float2(0.55, -0.22), float2(0.3, 0.16)))) * 0.85);   // the throat
        // glitter: scattered bright scales on the flank
        float2 sg = p * float2(17.0, 21.0);
        sg.x += 0.5 * fmod(floor(sg.y), 2.0);
        float2 gid = floor(sg);
        float sp = step(0.72, hash21(gid)) * (1.0 - smoothstep(0.05, 0.3, length(fract(sg) - 0.5 - (float2(hash21(gid + 1.7), hash21(gid + 5.1)) - 0.5) * 0.5)));
        c3 += float3(1.0, 0.98, 0.9) * sp * (pat == 1 ? 0.14 : 0.3) * smoothstep(-0.7, 0.2, yn) * smoothstep(0.55, 0.3, p.x);
        if (pat == 2) {
            float2 dg = p * 7.5;
            float2 did = floor(dg);
            float spot = step(0.35, hash21(did)) * (1.0 - smoothstep(0.12, 0.26, length(fract(dg) - 0.5 - (float2(hash21(did + 3.0), hash21(did + 5.0)) - 0.5) * 0.4)));
            c3 = mix(c3, float3(0.1, 0.11, 0.13), spot * smoothstep(-0.45, -0.1, yn) * 0.8);
        }
        if (pat == 3) c3 = mix(c3, float3(0.06), 1.0 - smoothstep(0.05, 0.11, length((p - float2(0.2, 0.06)) * float2(1.0, 0.7))));
        float2 q = clamp((p - bc) / float2(0.8, 0.5), -1.0, 1.0);
        float3 n = normalize(float3(q, sqrt(max(0.02, 1.0 - dot(q, q)))));
        float li = dot(n, normalize(float3(-0.3, 0.8, 0.5)));
        c3 *= 0.62 + 0.55 * li;
        c3 += float3(1.0) * pow(max(0.0, li), 8.0) * 0.14;
        // gill cover, the mouth with its teeth, the eye
        float garc = abs(length((p - float2(0.36, -0.04)) * float2(1.0, 0.7)) - 0.17);
        c3 *= 1.0 - (1.0 - smoothstep(0.004, 0.02, garc)) * step(p.x, 0.48) * step(abs(p.y + 0.04), 0.2) * 0.2;
        float2 m0 = float2(0.62, -0.17), m1 = float2(0.9, -0.1);
        float mouth = sd_seg(p, m0, m1);
        c3 = mix(c3, float3(0.08, 0.03, 0.03), 1.0 - smoothstep(0.012, 0.024, mouth));
        float tx = (p.x - m0.x) / (m1.x - m0.x);
        float ty = p.y - mix(m0.y, m1.y, tx);
        float teeth = abs(fract(tx * 5.0) - 0.5) * 0.07 - (ty + 0.002);               // a zigzag hanging from the lip
        c3 = mix(c3, float3(0.98, 0.97, 0.9), step(0.0, teeth) * step(-0.036, ty) * step(ty, 0.012) * step(0.02, tx) * step(tx, 0.98));
        c3 = amazon_eye(c3, p, float2(0.6, 0.1), 0.058, pat == 1 ? red * 1.2 : float3(0.95, 0.75, 0.3), asleep);
        float rim = 1.0 - smoothstep(0.0, 0.03, -body);
        c3 += float3(0.9, 0.95, 1.0) * rim * smoothstep(0.2, 0.9, yn) * 0.22;
        c3 *= 1.0 - rim * smoothstep(0.0, -0.9, yn) * 0.3;
        if (pect < 0.0) c3 = mix(c3, mix(red, float3(1.0), 0.35) * (0.85 + 0.15 * cos(atan2(pq.y, pq.x + 0.3) * 20.0)), 0.55);
    } else if (anal < min(dors, min(tail, adip))) {
        c3 = red * (0.75 + 0.25 * cos((p.x + p.y) * 60.0));
        c3 = mix(c3, float3(0.08), smoothstep(-0.03, 0.0, anal) * 0.7);                // a dark edge
    } else if (tail < min(dors, adip)) {
        float rays = 0.5 + 0.5 * cos(atan2(tq.y, -tq.x + 0.15) * 28.0);
        c3 = mix(steel * 1.3, silver, smoothstep(0.0, 0.25, -tq.x)) * (0.82 + 0.18 * rays);
        c3 = mix(c3, float3(0.06), smoothstep(-0.08, -0.02, tail) * step(tq.x, -0.2) * 0.85);
        if (pat == 1) c3 *= 0.45;
    } else {
        c3 = steel * (pat == 1 ? 0.4 : 0.8) * (0.93 + 0.08 * cos(p.x * 70.0 + p.y * 20.0));
    }
    c3 += col.rgb * glow * 0.45;
    float al = a * col.a * (body < 0.0 ? 1.0 : 0.88);
    float edge = 1.0 - smoothstep(0.6, 1.0, max(abs(c.x), abs(c.y)));
    float halo = glow * exp(-max(d, 0.0) * 12.0) * edge * (1.0 - a) * col.a;
    return float4(c3 * al + col.rgb * halo, min(al + halo * 0.55, 1.0));
}

// Tucunaré (peacock bass): a long, strong cichlid with a big mouth, a spiny dorsal fin and a soft one behind it,
// and the eye-spot ringed in gold at the root of the tail. The quad is 1.5 × 0.7. The back takes the project's
// color; the lower fins are orange. Variety by extra.y: 0 three black bars, 1 paca (rows of pale dashes), 2 three
// blotches along the side, 3 three ringed eye-spots.
float4 draw_amazon_tucunare(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.5, 0.7);
    int pat = int(extra.y + 0.5) % 4;
    bool asleep = extra.w > 1.5;
    p.y -= sin(phase - p.x * 2.0) * 0.05 * smoothstep(0.3, -1.3, p.x);
    float thin = mix(0.38, 1.0, smoothstep(-1.15, -0.2, p.x));
    float2 bc = float2(0.0, 0.0);
    float2 br = float2(1.08, 0.33 * thin);
    float body = amazon_ell(p, bc, br);
    float head = amazon_ell(p, float2(0.82, -0.01), float2(0.44, 0.25));
    float jaw = amazon_ell(p, float2(1.12, -0.11), float2(0.2, 0.075));
    body = smin_k(smin_k(body, head, 0.12), jaw, 0.05);
    // dorsal: the spiny part (a saw), then the taller soft lobe
    float spx = clamp((0.5 - p.x) / 0.72, 0.0, 1.0);
    float saw = 0.035 * abs(fract(p.x * 9.0) - 0.5);
    float spiny = max(max(p.x - 0.5, -0.22 - p.x), p.y - (0.3 + 0.17 * sin(spx * 3.1) - saw));
    spiny = max(spiny, 0.2 - p.y);
    float soft = amazon_ell(p, float2(-0.5, 0.24), float2(0.3, 0.26 + 0.012 * sin(phase * 1.2)));
    soft = max(soft, 0.14 - p.y);
    float anal = max(amazon_ell(p, float2(-0.52, -0.2), float2(0.26, 0.26)), p.y + 0.12);
    float pelv = sd_tri(p, float2(0.3, -0.28), float2(0.02, -0.3), float2(0.0, -0.52)) - 0.015;
    float2 tq = p - float2(-1.0, sin(phase - 1.4) * 0.05);
    float tail = max(sd_tri(tq, float2(0.1, 0.0), float2(-0.5, 0.42), float2(-0.5, -0.42)), length(tq - float2(0.05, 0.0)) - 0.46) - 0.012;
    float2 pq = amazon_rot(p - float2(0.46, -0.1), -0.45 + sin(phase) * 0.25);
    float pect = amazon_ell(pq, float2(-0.14, 0.0), float2(0.17, 0.065));
    float fins = min(min(spiny, soft), min(min(anal, pelv), tail));
    float d = min(body, fins);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);

    float3 back = mix(float3(0.42, 0.46, 0.14), col.rgb, 0.6) * 0.8;
    float3 gold = mix(float3(0.95, 0.8, 0.3), col.rgb, 0.35);
    float3 cream = float3(0.97, 0.93, 0.76);
    float3 orange = float3(0.98, 0.45, 0.12);
    float3 black = float3(0.05, 0.05, 0.04);
    float yn = p.y / max(br.y, 0.06);
    float3 c3;
    if (body < 0.0) {
        c3 = mix(gold, back, smoothstep(0.0, 0.75, yn));
        c3 = mix(c3, cream, smoothstep(-0.2, -0.8, yn));
        c3 = mix(c3, orange, smoothstep(-0.55, -0.95, yn) * smoothstep(0.75, 0.3, p.x) * 0.6);
        float mark = 0.0;
        if (pat == 0 || pat == 1) {
            // three bars from the back, tapering toward the belly
            for (int i = 0; i < 3; i++) {
                float bx = 0.36 - 0.42 * float(i);
                float w = 0.075 * smoothstep(-0.85, 0.5, yn);
                mark = max(mark, (1.0 - smoothstep(w * 0.6, w, abs(p.x - bx + 0.03 * yn))) * smoothstep(-0.7, -0.3, yn));
            }
            if (pat == 1) {
                mark *= 0.45;
                float2 dg = float2(p.x * 9.0, yn * 3.2);
                dg.x += 0.5 * fmod(floor(dg.y), 2.0);
                float dash = 1.0 - smoothstep(0.5, 1.0, length((fract(dg) - 0.5) / float2(0.34, 0.26)));
                c3 = mix(c3, cream, dash * step(abs(yn), 0.82) * smoothstep(0.75, 0.5, p.x) * 0.85);
            }
        } else {
            for (int i = 0; i < 3; i++) {
                float2 sc2 = float2(0.38 - 0.42 * float(i), 0.03);
                float r = length((p - sc2) * float2(pat == 2 ? 0.75 : 1.0, 1.0));
                if (pat == 2) mark = max(mark, 1.0 - smoothstep(0.09, 0.13, r));
                else {
                    c3 = mix(c3, cream * float3(1.0, 0.9, 0.5), 1.0 - smoothstep(0.1, 0.125, r));
                    mark = max(mark, 1.0 - smoothstep(0.065, 0.085, r));
                }
            }
        }
        c3 = mix(c3, black, mark * 0.92);
        // the eye-spot at the root of the tail, ringed in gold
        float ro = length(p - float2(-0.93, 0.05));
        c3 = mix(c3, float3(1.0, 0.82, 0.3), 1.0 - smoothstep(0.085, 0.105, ro));
        c3 = mix(c3, black, 1.0 - smoothstep(0.05, 0.068, ro));
        float2 q = clamp(p / float2(1.2, 0.36), -1.0, 1.0);
        float3 n = normalize(float3(q.x * 0.5, q.y, sqrt(max(0.02, 1.0 - q.y * q.y))));
        float li = dot(n, normalize(float3(-0.3, 0.8, 0.5)));
        c3 *= 0.66 + 0.5 * li;
        c3 += float3(1.0) * pow(max(0.0, li), 8.0) * 0.14;
        // scales, the gill cover, the big mouth, the eye
        float2 sq = p * float2(20.0, 24.0);
        sq.x += fmod(floor(sq.y), 2.0) * 0.5;
        c3 *= 1.0 - smoothstep(0.38, 0.5, length(fract(sq) - float2(0.5, 0.0))) * 0.1 * step(p.x, 0.6);
        float garc = abs(length((p - float2(0.62, -0.03)) * float2(1.0, 0.72)) - 0.17);
        c3 *= 1.0 - (1.0 - smoothstep(0.004, 0.02, garc)) * step(p.x, 0.75) * step(abs(p.y + 0.03), 0.17) * 0.18;
        float mouth = sd_seg(p, float2(0.98, -0.09), float2(1.33, -0.035));
        c3 = mix(c3, black, (1.0 - smoothstep(0.008, 0.02, mouth)) * 0.85);
        c3 = amazon_eye(c3, p, float2(0.94, 0.09), 0.058, float3(0.9, 0.25, 0.12), asleep);
        float rim = 1.0 - smoothstep(0.0, 0.03, -body);
        c3 += float3(1.0, 0.95, 0.8) * rim * smoothstep(0.2, 0.9, yn) * 0.22;
        c3 *= 1.0 - rim * smoothstep(0.0, -0.9, yn) * 0.25;
        if (pect < 0.0) c3 = mix(c3, mix(gold, cream, 0.5) * (0.85 + 0.15 * cos(atan2(pq.y, pq.x + 0.35) * 20.0)), 0.6);
    } else if (min(anal, pelv) < min(min(spiny, soft), tail)) {
        c3 = orange * (0.8 + 0.2 * cos(p.x * 60.0 - p.y * 30.0)) * (0.8 + 0.3 * smoothstep(-0.55, -0.2, p.y));
    } else if (tail < min(spiny, soft)) {
        float rays = 0.5 + 0.5 * cos(atan2(tq.y, -tq.x + 0.15) * 30.0);
        c3 = mix(orange, back * 1.15, smoothstep(-0.06, 0.06, tq.y)) * (0.8 + 0.2 * rays);
        float2 dg = tq * 14.0;
        c3 = mix(c3, cream, (1.0 - smoothstep(0.15, 0.3, length(fract(dg) - 0.5))) * step(0.0, tq.y) * 0.5);
    } else {
        c3 = back * (0.9 + 0.25 * cos(p.x * 56.0));
        float2 dg = p * 16.0;
        if (soft < spiny) c3 = mix(c3, cream, (1.0 - smoothstep(0.15, 0.3, length(fract(dg) - 0.5))) * 0.55);
        c3 = mix(c3, black, smoothstep(-0.025, 0.0, min(spiny, soft)) * 0.5);
    }
    c3 += col.rgb * glow * 0.45;
    float al = a * col.a * (body < 0.0 ? 1.0 : 0.88);
    float edge = 1.0 - smoothstep(0.6, 1.0, max(abs(c.x), abs(c.y)));
    float halo = glow * exp(-max(d, 0.0) * 12.0) * edge * (1.0 - a) * col.a;
    return float4(c3 * al + col.rgb * halo, min(al + halo * 0.55, 1.0));
}

// Cardinal tetra: a sliver of a fish with a line of light from the eye to the tail (the color it's given) over a
// red belly, an olive back, and fins you can barely see. Made for the schools.
float4 draw_amazon_cardinal(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.25, 0.8);
    bool asleep = extra.w > 1.5;
    p.y -= sin(phase - p.x * 2.6) * 0.05 * smoothstep(0.3, -1.0, p.x);
    float thin = mix(0.3, 1.0, smoothstep(-0.85, -0.1, p.x));
    float body = amazon_ell(p, float2(0.12, 0.0), float2(0.8, 0.23 * thin));
    float2 tq = p - float2(-0.62, sin(phase - 1.2) * 0.05);
    float tail = sd_tri(tq, float2(0.08, 0.0), float2(-0.4, 0.27), float2(-0.4, -0.27));
    tail = max(tail, -amazon_ell(tq, float2(-0.46, 0.0), float2(0.2, 0.1))) - 0.01;
    float dors = sd_tri(p, float2(0.08, 0.2), float2(-0.2, 0.18), float2(-0.16, 0.37)) - 0.012;
    float anal = sd_tri(p, float2(-0.1, -0.19), float2(-0.48, -0.09), float2(-0.38, -0.31)) - 0.012;
    float fins = min(tail, min(dors, anal));
    float d = min(body, fins);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float3 neon = mix(col.rgb, float3(0.7, 1.0, 1.0), 0.25) * 1.25;
    float3 red = float3(0.92, 0.12, 0.1);
    float3 c3;
    float al = a;
    if (body < 0.0) {
        float yn = p.y / max(0.23 * thin, 0.05);
        c3 = mix(red, float3(0.36, 0.3, 0.14), smoothstep(0.35, 0.6, yn));
        c3 = mix(c3, neon, (1.0 - smoothstep(0.16, 0.32, abs(yn - 0.2))) * smoothstep(-0.7, -0.5, p.x));
        c3 = mix(c3, float3(0.95, 0.9, 0.85), smoothstep(-0.75, -0.95, yn) * smoothstep(0.1, 0.5, p.x) * 0.6);
        c3 *= 0.8 + 0.3 * smoothstep(-1.0, 0.6, yn);
        c3 = amazon_eye(c3, p, float2(0.68, 0.04), 0.068, float3(0.85, 0.9, 0.9), asleep);
    } else {
        c3 = mix(float3(0.9, 0.85, 0.75), red, tail < min(dors, anal) ? (1.0 - smoothstep(0.0, 0.2, -tq.x)) * 0.8 : 0.25);
        al *= 0.42;
    }
    c3 += col.rgb * glow * 0.45;
    al *= col.a;
    float edge = 1.0 - smoothstep(0.6, 1.0, max(abs(c.x), abs(c.y)));
    float halo = glow * exp(-max(d, 0.0) * 12.0) * edge * (1.0 - a) * col.a;
    return float4(c3 * al + col.rgb * halo, min(al + halo * 0.55, 1.0));
}

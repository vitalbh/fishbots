// Abyssal trench creatures: the comb jelly, the siphonophore, the dumbo octopus, the hatchetfish, the giant isopod,
// and the lanternfish the sessions become down here.

float3 trench_rainbow(float h) {
    return 0.5 + 0.5 * cos(6.28318 * (h + float3(0.0, 0.33, 0.67)));
}

float2 trench_rot(float2 p, float a) {
    return float2(p.x * cos(a) - p.y * sin(a), p.x * sin(a) + p.y * cos(a));
}

// Comb jelly: a glass egg you only see by its rim, and four rows of beating combs that split what little light
// there is into rainbows running down its sides. p = c * (0.8, 1.0).
float4 draw_trench_combjelly(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(0.8, 1.0);
    float seed = extra.y;
    float beat = sin(phase * 1.1 + seed * 6.0);
    float2 q = p - float2(0.0, 0.08);
    float ry = 0.7 * (1.0 + 0.03 * beat);
    float rx = 0.46 * (1.0 - 0.03 * beat) * (1.0 - 0.18 * q.y);          // an egg: narrower on top
    float d = (length(q / float2(rx, ry)) - 1.0) * 0.46;
    // the mouth lobes below
    float lobes = min((length((q - float2(-0.17, -0.66)) / float2(0.17, 0.16)) - 1.0) * 0.16,
                      (length((q - float2(0.17, -0.66)) / float2(0.17, 0.16)) - 1.0) * 0.16);
    d = smin_k(d, lobes, 0.08);
    float aa = fwidth(d) + 1e-4;
    float inside = 1.0 - smoothstep(-aa, aa, d);
    float rim = smoothstep(-0.14, 0.0, d) * inside;
    float3 glass = float3(0.45, 0.7, 0.95);
    float3 c3 = glass * (0.25 + 0.75 * rim);
    float a = inside * (0.1 + 0.5 * rim);
    // the gut: a faint rosy thr down the middle
    float gut = (1.0 - smoothstep(0.015, 0.05, abs(q.x + 0.02 * sin(q.y * 9.0)))) * step(abs(q.y - 0.05), 0.42) * inside;
    c3 = mix(c3, float3(0.9, 0.5, 0.55), gut * 0.5);
    a = max(a, gut * 0.3);
    // the comb rows: lines of longitude on the egg, each a running rainbow of little plates
    float v = q.y / ry;
    float wv = sqrt(max(0.0, 1.0 - v * v)) * rx;
    float3 em = float3(0.0);
    float lineA = 0.0;
    for (int k = 0; k < 4; k++) {
        float fk = float(k);
        float s = (fk < 1.5 ? -1.0 : 1.0) * (fmod(fk, 3.0) < 0.5 ? 0.9 : 0.4);      // -0.9 -0.4 0.4 0.9
        float dl = abs(q.x - s * wv);
        float line = (1.0 - smoothstep(0.012, 0.035, dl)) * step(abs(v), 0.9);
        float soft = exp(-dl * 22.0) * step(abs(v), 0.95) * inside;
        float plate = 0.35 + 0.65 * pow(0.5 + 0.5 * sin(v * 44.0 - phase * 5.0 + fk * 1.3), 2.0);
        float3 hue = trench_rainbow(v * 1.2 - phase * 0.22 + fk * 0.19 + seed);
        em += hue * (line * plate * 1.25 + soft * 0.22);
        lineA = max(lineA, line * plate);
    }
    em *= inside;
    // two fine tentacles trailing
    float tn = 0.0;
    for (int k = 0; k < 2; k++) {
        float sx = (float(k) - 0.5) * 0.22;
        float ty = clamp(p.y, -0.96, -0.6);
        float tx = sx + sin(ty * 14.0 + phase * 1.3 + float(k) * 2.0) * 0.035 * smoothstep(-0.6, -0.95, ty);
        tn = max(tn, (1.0 - smoothstep(0.004, 0.014, length(p - float2(tx, ty)))) * smoothstep(-0.98, -0.85, p.y));
    }
    c3 = c3 * a + em + glass * tn * 0.3;
    a = max(max(a, lineA * 0.9), tn * 0.3);
    return float4(c3 * col.a, a * col.a);
}

// Siphonophore: not one animal but a colony in a line, a little float in front, swimming bells behind it, then a
// long glowing stem of feeding polyps each trailing a thr with a blue lure at its end; pulses of light run
// down the chain. p = c * (3.0, 0.5), head at +x.
float trench_siph_y(float x, float phase) {
    return 0.2 + sin(x * 2.1 - phase * 1.1) * (0.03 + 0.07 * smoothstep(2.4, -2.6, x));
}
float4 draw_trench_siphonophore(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(3.0, 0.5);
    float3 warm = col.rgb / max(0.05, max(col.r, max(col.g, col.b)));
    float3 blue = float3(0.35, 0.8, 1.0);
    float fade = smoothstep(-2.85, -1.6, p.x);                              // thinning out toward the tail
    float yc = trench_siph_y(p.x, phase);
    float stem = max(abs(p.y - yc) - 0.012, max(p.x - 2.5, -2.75 - p.x));
    // the float in front
    float2 fq = p - float2(2.62, trench_siph_y(2.5, phase));
    float flt = (length(fq / float2(0.15, 0.085)) - 1.0) * 0.085;
    // the units along the stem, one per cell
    float cw = 0.2;
    float id = floor(p.x / cw);
    float cx = (id + 0.5) * cw;
    float hs = hash21(float2(id, 4.0 + extra.y * 9.0));
    float cy = trench_siph_y(cx, phase);
    float2 l = p - float2(cx, cy);
    bool bell = cx > 1.55;
    float inRange = step(-2.7, cx) * step(cx, 2.45);
    float squeeze = 0.5 + 0.5 * sin(phase * 3.0 - id * 1.2);
    float unit = bell ? (length((l + float2(0.0, 0.035)) / float2(0.085 - 0.012 * squeeze, 0.07 + 0.012 * squeeze)) - 1.0) * 0.07
                      : length(l + float2(0.0, 0.03)) - (0.035 + 0.012 * hs);
    unit += (1.0 - inRange);
    // the thr under each polyp, and the lure at its end
    float len = 0.2 + 0.28 * hs;
    float ty = clamp(l.y, -len, -0.03);
    float tx = sin(ty * 22.0 + phase * 1.2 + id) * 0.03 * smoothstep(0.0, -0.3, ty);
    float thr = length(l - float2(tx, ty)) - 0.005;
    float2 lq = l - float2(sin(-len * 22.0 + phase * 1.2 + id) * 0.03 * smoothstep(0.0, -0.3, -len), -len);
    float lure = length(lq) - 0.016;
    if (bell || inRange < 0.5) { thr = 1e3; lure = 1e3; lq = float2(9.0); }
    float pulse = pow(0.5 + 0.5 * sin(id * 0.55 + phase * 1.6), 4.0);        // light running down the chain
    float body = min(min(stem, unit), flt);
    float aa = fwidth(p.y) * 1.2 + 1e-4;
    float aB = 1.0 - smoothstep(-aa, aa, body);
    float aT = (1.0 - smoothstep(-aa, aa, thr)) * 0.55;
    float aL = 1.0 - smoothstep(-aa, aa, lure);
    float3 c3 = warm * (0.55 + 0.6 * pulse);
    if (bell && unit < stem) c3 = mix(warm, float3(0.8, 0.9, 1.0), 0.55) * (0.35 + 0.3 * smoothstep(-0.05, 0.0, unit) + 0.3 * pulse);
    if (flt < min(stem, unit)) c3 = mix(warm, float3(1.0), 0.35) * (0.6 + 0.4 * smoothstep(-0.04, 0.05, fq.y));
    float3 rgb = c3 * aB;
    float a = aB * (bell && unit < stem ? 0.6 : 0.9);
    rgb = mix(rgb, warm * 0.5, aT * (1.0 - aB));
    a = max(a, aT * 0.6);
    float3 lc = mix(blue, float3(1.0), 0.5 * aL) * (0.5 + 0.8 * pulse);
    rgb = mix(rgb, lc, aL);
    a = max(a, aL);
    // the glow around the stem and the lures
    float edge = (1.0 - smoothstep(0.7, 1.0, abs(c.y))) * (1.0 - smoothstep(0.9, 1.0, abs(c.x)));
    float hStem = exp(-max(body, 0.0) * 30.0) * (0.12 + 0.3 * pulse);
    float hLure = exp(-dot(lq, lq) * 900.0) * (0.3 + 0.7 * pulse);
    rgb += (warm * hStem + blue * hLure) * (1.0 - a) * edge;
    a += (hStem + hLure) * 0.35 * (1.0 - a) * edge;
    return float4(rgb * fade * col.a, a * fade * col.a);
}

// Dumbo octopus: a soft bell of a body, two ear fins it flaps to fly, big dark eyes, a skirt of webbed arms that
// opens and closes. p = c * (1.2, 1.0).
float4 draw_trench_dumbo(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.2, 1.0);
    float flap = sin(phase * 1.6 + extra.y * 6.0);
    p.y -= 0.03 * flap;
    float mantle = (length((p - float2(0.0, 0.14)) / float2(0.5, 0.46)) - 1.0) * 0.46;
    // the skirt: wider when it opens, a scalloped hem
    float open = 0.5 + 0.5 * sin(phase * 0.8 + extra.y * 3.0);
    float sw = 0.56 + 0.12 * open;
    float skirt = (length((p - float2(0.0, -0.22)) / float2(sw, 0.42)) - 1.0) * 0.42;
    float hem = -0.5 + 0.06 * open - 0.07 * abs(sin(p.x / sw * 7.5));
    skirt = max(skirt, hem - p.y);
    float body = smin_k(mantle, skirt, 0.12);
    // the ears
    float ears = 1e3;
    for (int s = 0; s < 2; s++) {
        float sd = float(s) * 2.0 - 1.0;
        float2 e = trench_rot(float2((p.x * sd) - 0.36, p.y - 0.4), -(0.35 + 0.55 * flap));
        ears = min(ears, (length((e - float2(0.2, 0.0)) / float2(0.26, 0.11)) - 1.0) * 0.11);
    }
    float d = smin_k(body, ears, 0.04);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    if (a <= 0.001) return float4(0.0);
    float3 hue = col.rgb / max(0.05, max(col.r, max(col.g, col.b)));
    // round and soft, lit from above by nothing much: its own faint blush
    float2 nq = (p - float2(0.0, 0.05)) / float2(0.6, 0.6);
    float3 n = normalize(float3(nq, sqrt(max(0.02, 1.0 - dot(nq, nq)))));
    float lt = 0.45 + 0.55 * max(0.0, dot(n, normalize(float3(-0.3, 0.8, 0.5))));
    float3 c3 = hue * (0.25 + 0.6 * lt);
    c3 = mix(c3, hue * 0.9 + 0.1, pow(max(0.0, dot(n, normalize(float3(-0.25, 0.6, 0.75)))), 14.0) * 0.5);
    c3 *= 0.9 + 0.16 * vnoise(p * 16.0);
    if (ears < body) c3 *= 0.78 + 0.2 * sin(atan2(p.y - 0.4, abs(p.x) - 0.36) * 16.0);          // fin rays
    // the arms show through the web as darker ribs, the hem lighter and thin
    float ribsK = pow(abs(sin(p.x / sw * 7.5)), 6.0) * smoothstep(-0.1, -0.45, p.y);
    c3 *= 1.0 - 0.3 * (1.0 - ribsK) * smoothstep(-0.15, -0.5, p.y);
    float alpha = a * (1.0 - 0.3 * smoothstep(-0.38, -0.56, p.y));
    // the eyes
    for (int s = 0; s < 2; s++) {
        float2 e = p - float2((float(s) * 2.0 - 1.0) * 0.22, -0.0);
        float er = length(e);
        c3 = mix(c3, float3(0.02, 0.02, 0.05), 1.0 - smoothstep(0.075, 0.09, er));
        c3 = mix(c3, float3(0.9, 0.95, 1.0), 1.0 - smoothstep(0.018, 0.03, length(e - float2(-0.025, 0.03))));
    }
    c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.03, -d)) * 0.25;
    return float4(c3 * alpha * col.a, alpha * col.a);
}

// Hatchetfish: a sliver of mirror shaped like a hatchet blade, a huge eye looking up, and a row of blue lights
// along its belly that hide its shadow from below. Tiny: it reads as a silver flake with lights. p = c * (1.2, 1.0).
float4 draw_trench_hatchet(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.2, 1.0);
    p.y -= sin(phase - p.x * 2.5) * 0.05 * smoothstep(0.1, -1.0, p.x);
    float blade = (length((p - float2(0.2, 0.02)) / float2(0.55, 0.62)) - 1.0) * 0.5;
    blade = max(blade, p.y - 0.34);
    float stock = sd_seg(p, float2(-0.2, 0.12), float2(-0.78, 0.12)) - 0.085;
    float2 tq = p - float2(-0.8, 0.12 + sin(phase - 1.0) * 0.04);
    float tail = sd_tri(tq, float2(0.05, 0.0), float2(-0.3, 0.25), float2(-0.3, -0.25));
    float d = min(smin_k(blade, stock, 0.12), tail);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float3 c3 = col.rgb * (0.6 + 0.6 * smoothstep(-0.5, 0.35, p.y));
    c3 = fish_round(c3, (p - float2(0.2, 0.02)) / float2(0.55, 0.62), blade);
    c3 += col.rgb * 0.5 * pow(max(0.0, sin(p.x * 9.0 + p.y * 4.0 + phase * 0.5)), 6.0);          // a flash of mirror
    if (tail < 0.0 && tail < blade) c3 *= 0.6;
    float er = length(p - float2(0.45, 0.14));
    c3 = mix(c3, float3(0.8, 0.85, 0.9) * (0.4 + col.rgb), 1.0 - smoothstep(0.13, 0.15, er));
    c3 = mix(c3, float3(0.01), 1.0 - smoothstep(0.08, 0.1, er));
    c3 = mix(c3, float3(1.0), 1.0 - smoothstep(0.015, 0.03, length(p - float2(0.47, 0.17))));
    // the belly lights
    float3 blue = float3(0.3, 0.75, 1.0);
    float ph = 0.0;
    for (int i = 0; i < 5; i++) {
        float x = -0.12 + float(i) * 0.15;
        float y = 0.02 - 0.62 * sqrt(max(0.0, 1.0 - pow((x - 0.2) / 0.55, 2.0))) + 0.07;
        float2 q = p - float2(x, y);
        ph += exp(-dot(q, q) * 320.0);
    }
    ph = min(ph, 1.0);
    c3 = c3 * a + blue * ph * 1.2;
    float alpha = max(a, ph * 0.7);
    return float4(c3 * col.a, alpha * col.a);
}

// Giant isopod: a pill bug the size of a cat, a dome of overlapping pale plates, two triangular eyes that shine
// back, antennae sweeping ahead, seven pairs of legs stepping under it. p = c * (1.6, 0.8); the ground at y ≈ -0.72.
float4 draw_trench_isopod(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.6, 0.8);
    float moving = extra.w;
    float gy = -0.72;
    // the shell: a long dome, a little flatter toward the tail fan
    float dome = (length((p - float2(-0.1, gy + 0.14)) / float2(1.05, 0.56)) - 1.0) * 0.5;
    dome = max(dome, (gy + 0.12) - p.y);
    // the legs
    float legs = 1e3;
    for (int i = 0; i < 7; i++) {
        float fi = float(i);
        float x = -0.75 + fi * 0.24;
        float st = sin(phase * 3.0 + fi * 1.9) * 0.07 * moving;
        float lift = max(0.0, cos(phase * 3.0 + fi * 1.9)) * 0.04 * moving;
        legs = min(legs, sd_seg(p, float2(x, gy + 0.14), float2(x + 0.06 + st, gy + 0.005 + lift)) - 0.02);
    }
    // the antennae
    float sweep = sin(phase * 1.3) * 0.08;
    float ant = min(sd_seg(p, float2(0.85, gy + 0.3), float2(1.2, gy + 0.5 + sweep)),
                    sd_seg(p, float2(1.2, gy + 0.5 + sweep), float2(1.5, gy + 0.36 + sweep * 2.0))) - 0.012;
    ant = min(ant, sd_seg(p, float2(0.9, gy + 0.22), float2(1.3, gy + 0.16 - sweep)) - 0.01);
    float d = min(min(dome, legs), ant);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    if (a <= 0.001) return float4(0.0);
    float3 c3;
    if (dome <= min(legs, ant)) {
        // plates: each one overlaps the next, light on its front edge, a shadow under its back edge
        float2 nq = (p - float2(-0.1, gy + 0.14)) / float2(1.05, 0.56);
        float sx = (p.x + 0.04 * nq.y * nq.y) * 4.6 + 0.3;
        float seg = fract(sx);
        float isHead = step(0.72, p.x);
        float3 n = normalize(float3(nq, sqrt(max(0.02, 1.0 - dot(nq, nq)))));
        float lt = 0.35 + 0.75 * max(0.0, dot(n, normalize(float3(-0.2, 0.85, 0.45))));
        c3 = col.rgb * lt;
        c3 *= mix(0.72 + 0.4 * seg, 1.0, isHead);
        c3 *= 1.0 - 0.45 * (1.0 - smoothstep(0.0, 0.1, seg)) * (1.0 - isHead);
        c3 += col.rgb * pow(max(0.0, dot(n, normalize(float3(-0.2, 0.7, 0.7)))), 18.0) * 0.5;
        c3 *= 0.92 + 0.12 * vnoise(p * 30.0);
        // the tail fan
        c3 *= 1.0 - 0.25 * step(p.x, -0.85) * step(0.5, fract(p.y * 9.0));
        // the eye: a dark triangle with a glint, shining back like a cat's
        float eye = sd_tri(p, float2(0.74, gy + 0.36), float2(0.92, gy + 0.3), float2(0.8, gy + 0.22));
        c3 = mix(c3, float3(0.03, 0.05, 0.06), 1.0 - smoothstep(0.0, 0.015, eye));
        c3 += float3(0.5, 0.9, 0.8) * (1.0 - smoothstep(0.0, 0.035, length(p - float2(0.82, gy + 0.3)))) * 0.8;
    } else {
        c3 = col.rgb * 0.55;
    }
    c3 *= 0.6 + 0.4 * smoothstep(gy, gy + 0.2, p.y);
    c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.025, -d)) * 0.25;
    return float4(c3 * a * col.a, a * col.a);
}

// The trench lanternfish, what a session's fish becomes down here: a dark slender body with a big head and a
// bigger eye, and lights in the project's color: a row along the belly (pattern 0), with a second row on the flank
// (1), a glowing stripe (2), or scattered like stars (3). Asleep the lights go low.
float4 draw_trench_lantern(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.25, 0.8);
    bool asleep = extra.w > 1.5;
    float full = clamp(asleep ? extra.w - 2.0 : extra.w, 0.0, 1.0);
    p.y -= sin(phase - p.x * 2.6) * 0.05 * smoothstep(0.3, -1.0, p.x);
    float thin = mix(0.3, 1.0, smoothstep(-0.9, 0.0, p.x));
    float by = 0.27 * thin * (1.0 + 0.25 * full);
    float body = (length((p - float2(0.08, 0.0)) / float2(0.84, by)) - 1.0) * 0.27;
    float head = (length((p - float2(0.56, 0.02)) / float2(0.36, 0.3)) - 1.0) * 0.3;
    body = smin_k(body, head, 0.1);
    float2 tq = p - float2(-0.72, sin(phase - 1.2) * 0.05);
    float tail = max(sd_tri(tq, float2(0.06, 0.0), float2(-0.42, 0.3), float2(-0.42, -0.3)),
                     -sd_tri(tq, float2(-0.2, 0.0), float2(-0.5, 0.16), float2(-0.5, -0.16)));
    float dors = max((length((p - float2(-0.02, 0.2)) / float2(0.24, 0.17)) - 1.0) * 0.17, 0.2 - p.y);
    float anal = max((length((p - float2(-0.2, -0.18)) / float2(0.26, 0.14)) - 1.0) * 0.14, p.y + 0.18);
    float pect = (length(trench_rot(p - float2(0.3, -0.1), 0.5 + 0.2 * sin(phase * 2.0)) / float2(0.15, 0.05)) - 1.0) * 0.05;
    float fins = min(min(dors, anal), tail);
    float d = min(min(body, fins), pect);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float3 hue = col.rgb / max(0.05, max(col.r, max(col.g, col.b)));
    // dark, with a cold sheen along the flank and the project's color in the skin
    float3 c3 = mix(float3(0.035, 0.05, 0.085), hue, 0.2) * (0.55 + 0.9 * smoothstep(-0.3, 0.3, p.y));
    c3 += (float3(0.1, 0.14, 0.2) + hue * 0.12) * exp(-pow((p.y - 0.05) * 9.0, 2.0)) * smoothstep(-0.7, 0.2, p.x);
    float2 sc = p * float2(18.0, 22.0);
    c3 *= 0.9 + 0.14 * smoothstep(0.25, 0.5, length(fract(sc + float2(floor(sc.y) * 0.5, 0.0)) - 0.5)) * step(body, 0.0);
    if (fins < body) c3 = mix(c3 * 0.8, hue * 0.3, 0.35) * (0.85 + 0.15 * sin(atan2(p.y, p.x + 0.3) * 46.0));
    if (pect < 0.0) c3 = mix(c3, hue * 0.35, 0.5);
    c3 = mix(c3, hue * 0.5 + 0.1, (1.0 - smoothstep(0.0, 0.03, -d)) * 0.3 * step(0.0, p.y));
    // the lights
    int pat = int(extra.y + 0.5) % 4;
    float dim = (asleep ? 0.3 : 1.0);
    float ph = 0.0, core = 0.0;
    for (int i = 0; i < 8; i++) {
        float x = -0.52 + float(i) * 0.15;
        float th = mix(0.3, 1.0, smoothstep(-0.9, 0.0, x));
        float yb = -0.27 * th * (1.0 + 0.25 * full) * sqrt(max(0.0, 1.0 - pow((x - 0.08) / 0.84, 2.0))) + 0.055;
        if (x > 0.3) yb = min(yb, -0.2);
        float tw = 0.8 + 0.2 * sin(phase * 0.6 + float(i) * 1.7);
        if (pat != 2) {
            float2 q = p - float2(x, yb);
            ph += exp(-dot(q, q) * 420.0) * tw; core += exp(-dot(q, q) * 2600.0);
        }
        if (pat == 1 && i < 7) {
            float2 q = p - float2(x + 0.07, 0.03);
            ph += exp(-dot(q, q) * 800.0) * tw * 0.8; core += exp(-dot(q, q) * 4000.0) * 0.7;
        }
        if (pat == 3) {
            float2 q = p - float2(x + 0.05, (hash21(float2(float(i), 3.0)) - 0.4) * 0.3 * th);
            ph += exp(-dot(q, q) * 1100.0) * tw * 0.8; core += exp(-dot(q, q) * 5000.0) * 0.6;
        }
    }
    if (pat == 2) {
        float ly = 0.02 - 0.02 * smoothstep(0.0, -0.8, p.x);
        float band = exp(-pow((p.y - ly) * 22.0, 2.0)) * smoothstep(-0.72, -0.5, p.x) * (1.0 - smoothstep(0.3, 0.45, p.x));
        ph += band * (0.75 + 0.25 * sin(phase * 0.6 - p.x * 6.0)) * step(body, 0.02);
        core += band * band * 0.5 * step(body, 0.0);
    }
    float2 ck = p - float2(0.7, -0.12);                                    // the cheek light, under the eye
    ph += exp(-dot(ck, ck) * 700.0); core += exp(-dot(ck, ck) * 3500.0);
    ph = min(ph, 1.2) * dim; core = min(core, 1.0) * dim;
    // the eye: big, silver-ringed
    float er = length(p - float2(0.64, 0.08));
    if (asleep) c3 = mix(c3, float3(0.01), (1.0 - smoothstep(0.01, 0.02, abs(p.y - 0.07))) * step(er, 0.09));
    else {
        c3 = mix(c3, float3(0.55, 0.62, 0.7), 1.0 - smoothstep(0.1, 0.115, er));
        c3 = mix(c3, float3(0.01), 1.0 - smoothstep(0.065, 0.08, er));
        c3 = mix(c3, float3(1.0), 1.0 - smoothstep(0.012, 0.024, length(p - float2(0.665, 0.11))));
    }
    c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.025, -d)) * 0.2;
    c3 += hue * glow * 0.45;
    float3 light = hue * ph * 1.25 + float3(1.0) * core * 0.6;
    float edge = 1.0 - smoothstep(0.6, 1.0, max(abs(c.x), abs(c.y)));
    float halo = glow * exp(-max(d, 0.0) * 12.0) * edge * (1.0 - a);
    float3 rgb = c3 * a + light + hue * halo;
    float alpha = max(a, ph * 0.6) + halo * 0.55 * (1.0 - a);
    return float4(rgb * col.a, min(alpha, 1.0) * col.a);
}

// A tripod fish (Bathypterois), facing +x into the current: it stands still on the floor on three long stiff fin
// rays (the two pelvic fins and the lower lobe of the tail, each about as long as the body), its slim pale body held
// well above the sand, and its long thin pectoral rays raised and spread forward and up like antennae, feeling the
// water. Tiny eyes. It sways very slightly (phase). p = c * (1.3, 1.0); the floor at p.y = -0.9.
float4 draw_trench_tripod(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.3, 1.0);
    float gy = -0.9;
    if (p.y < gy - 0.07) return float4(0.0);
    // the sway: the feet stay put, the body leans a little with the current and comes back
    float lean = sin(phase * 1.3 + extra.y * 6.0) * 0.022 + sin(phase * 2.9) * 0.006;
    float2 q = p;
    q.x -= lean * (p.y - gy) / 0.85;
    float by = -0.04 + sin(phase * 0.9) * 0.008;
    // the body: slim, deepest behind the head, a long tail stock; a flattened head with a pointed snout
    float2 bc = float2(0.08, by);
    float taper = mix(0.42, 1.0, smoothstep(-0.62, 0.2, q.x));
    float ry = 0.125 * taper;
    float2 b = (q - bc) / float2(0.7, ry);
    float body = (length(b) - 1.0) * ry;
    float snout = sd_tri(q, float2(0.5, by + 0.085), float2(0.5, by - 0.09), float2(0.9, by - 0.03)) - 0.025;
    body = smin_k(body, snout, 0.06);
    // the three legs: stiff rays, a little bowed, thicker where they leave the body; the far pelvic ray behind
    float2 hip = float2(0.24, by - 0.09), tb = float2(-0.58, by - 0.02);
    float2 f1 = float2(0.74, gy), f2 = float2(0.5, gy), f3 = float2(-1.06, gy);
    float2 k1 = mix(hip, f1, 0.5) + float2(0.035, 0.02), k3 = mix(tb, f3, 0.5) + float2(-0.04, 0.03);
    float h1 = clamp((hip.y - p.y) / (hip.y - gy), 0.0, 1.0);
    float leg1 = min(sd_seg(q, hip, k1), sd_seg(q, k1, f1)) - mix(0.03, 0.017, h1);
    float2 k2 = mix(hip, f2, 0.5) + float2(0.02, 0.02);
    float leg2 = min(sd_seg(q, hip - float2(0.07, -0.01), k2), sd_seg(q, k2, f2)) - mix(0.026, 0.015, h1);
    float leg3 = min(sd_seg(q, tb, k3), sd_seg(q, k3, f3)) - mix(0.032, 0.017, h1);
    float legs = min(leg1, leg3);
    // the upper lobe of the tail and the small fins on the back and under the stock
    float tailUp = sd_tri(q, tb + float2(0.06, 0.03), tb + float2(-0.3, 0.26), tb + float2(-0.2, 0.0)) - 0.012;
    float dors = sd_tri(q, float2(0.12, by + 0.1), float2(-0.16, by + 0.085), float2(-0.1, by + 0.25)) - 0.012;
    float anal = sd_tri(q, float2(-0.2, by - 0.08), float2(-0.42, by - 0.05), float2(-0.4, by - 0.2)) - 0.01;
    float fins = min(min(tailUp, dors), anal);
    // the antennae: pectoral rays fanned forward and up from behind the head, each one swaying on its own
    float ant = 1e3, antT = 0.0;
    float2 sh = float2(0.4, by + 0.03);
    for (int i = 0; i < 4; i++) {
        float fi = float(i);
        float ang = 0.3 + fi * 0.3 + sin(phase * 2.1 + fi * 1.7 + extra.y * 4.0) * 0.08 + lean * 2.0;
        float len = 0.98 - 0.07 * fi;
        float2 dir = float2(cos(ang), sin(ang));
        // each ray an arc: up from the shoulder, bending forward to its tip
        float2 ctl = sh + dir * len * 0.5 + float2(-dir.y, dir.x) * 0.2;
        float2 tip = sh + dir * len + float2(sin(phase * 1.7 + fi * 2.3) * 0.03, 0.0);
        float2 prev = sh;
        for (int j = 1; j <= 5; j++) {
            float t = float(j) / 5.0;
            float2 pt = mix(mix(sh, ctl, t), mix(ctl, tip, t), t);
            float2 pa = q - prev, ba = pt - prev;
            float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
            float along = (float(j) - 1.0 + h) / 5.0;
            float dd = length(pa - ba * h) - mix(0.02, 0.01, along);
            if (dd < ant) { ant = dd; antT = along; }
            prev = pt;
        }
    }
    float back = min(min(leg2, ant), fins);
    float d = min(min(body, legs), back);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    // the contact shadows under the three ray tips
    float shd = 0.0;
    shd += exp(-pow((p.x - f1.x) / 0.1, 2.0)) + exp(-pow((p.x - f2.x) / 0.08, 2.0)) * 0.7 + exp(-pow((p.x - f3.x) / 0.1, 2.0));
    shd *= (1.0 - smoothstep(0.0, 0.035, abs(p.y - gy + 0.012))) * 0.45;
    if (a <= 0.001 && shd <= 0.003) return float4(0.0);
    float3 pale = col.rgb;
    float3 c3;
    float al = 1.0;
    if (body <= min(legs, back)) {
        c3 = mix(pale, pale * float3(0.72, 0.66, 0.74), smoothstep(0.3, -0.6, q.x) * 0.6);          // duskier toward the tail
        c3 *= 0.93 + 0.14 * vnoise(q * float2(9.0, 22.0) + extra.y * 5.0);
        c3 = fish_round(c3 * 1.12, float2(b.x * 0.8, clamp((q.y - by) / max(ry, 0.03), -1.0, 1.0) * 0.95), body);
        // the gill cover, the long mouth, the tiny eye
        float garc = abs(length((q - float2(0.5, by)) * float2(1.0, 0.75)) - 0.11);
        c3 *= 1.0 - (1.0 - smoothstep(0.004, 0.016, garc)) * step(q.x, 0.5) * 0.22;
        float mouth = abs(q.y - (by - 0.045 + (q.x - 0.7) * 0.08)) - 0.007;
        c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.012, mouth)) * step(0.62, q.x) * 0.5;
        float re = length(q - float2(0.66, by + 0.035));
        c3 = mix(c3, float3(0.02, 0.02, 0.04), 1.0 - smoothstep(0.016, 0.028, re));
        c3 += float3(0.8) * (1.0 - smoothstep(0.003, 0.01, length(q - float2(0.667, by + 0.043))));
    } else if (legs <= back) {
        // the standing rays: pale and bony, lit down one side, darker toward the sand
        c3 = pale * (0.74 + 0.3 * smoothstep(gy, by, p.y));
        c3 += pale * 0.2 * smoothstep(-0.006, -0.02, d);
    } else if (ant <= min(leg2, fins)) {
        c3 = pale * mix(0.82, 1.08, antT);                                                      // fine, catching light at their tips
        al = mix(0.95, 0.75, antT);
    } else if (leg2 <= fins) {
        c3 = pale * 0.55;                                                                       // the far leg, in shade
    } else {
        float2 rr = q - tb;
        c3 = pale * float3(0.7, 0.64, 0.72) * (0.85 + 0.15 * cos(atan2(rr.y, -rr.x) * 24.0));
        al = 0.8;
    }
    c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.02, -d)) * 0.15 * step(body, 0.0);
    a *= al * smoothstep(gy - 0.012, gy + 0.004, p.y);
    float alpha = a + shd * (1.0 - a);
    return float4(c3 * a * col.a, alpha * col.a);
}

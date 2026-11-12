// Desk tank: the room seen through the glass, and the plastic things on the gravel.

// The room behind the tank, out of focus and tinted by the water: a wall with a window (daylight, or the night
// outside), a desk lamp that comes on in the evening, a monitor with lines of code, a mug, the desk the tank stands
// on, and now and then a cat that comes to look in. uv 0…1 over the window (y up); extra.x the aspect, extra.y night.
float4 draw_desk_background(float2 uv, float t, float light, float2 gaze, float3 water, float4 extra) {
    float W = extra.x, night = extra.y, day = 1.0 - night;
    float2 q = float2((uv.x + gaze.x * 0.012) * W, uv.y + gaze.y * 0.006);        // the room shifts a little behind the glass
    float lit = mix(0.3, 1.0, day);
    float3 room = mix(float3(0.6, 0.53, 0.44), float3(0.8, 0.74, 0.64), uv.y) * lit;
    // the window, up on the left: sky and a cross of frame, its light spilling on the wall
    float2 wc = q - float2(W * 0.2, 0.68);
    float win = 1.0 - smoothstep(0.0, 0.05, sd_box(wc, float2(0.2, 0.2), 0.02));
    float3 sky = mix(float3(0.07, 0.09, 0.2), float3(0.72, 0.88, 1.0), day);
    float bars = max(1.0 - smoothstep(0.004, 0.022, abs(wc.x)), 1.0 - smoothstep(0.004, 0.022, abs(wc.y)));
    room = mix(room, mix(sky, float3(0.92, 0.9, 0.84) * lit, bars * 0.85), win);
    room += float3(1.0, 0.95, 0.85) * exp(-dot(wc, wc) * 3.0) * 0.2 * day;
    // the desk lamp, up on the right: its shade, and a warm cone of light that grows as the day goes
    float lampOn = 0.12 + 0.88 * smoothstep(0.1, 0.6, night);
    float2 lc = q - float2(W * 0.86, 0.86);
    float cone = smoothstep(0.9, 0.25, abs(lc.x) / max(0.04, 0.06 - lc.y * 0.8)) * step(lc.y, 0.02) * exp(lc.y * 1.5);
    room += float3(1.0, 0.72, 0.38) * cone * lampOn * 0.55;
    float shade = 1.0 - smoothstep(0.0, 0.03, sd_tri(q, float2(W * 0.86, 0.97), float2(W * 0.79, 0.86), float2(W * 0.93, 0.86)));
    room = mix(room, float3(0.16, 0.34, 0.3) * lit, shade * 0.9);
    // the monitor, right of the middle: a dark screen with rows of colored dashes, and its glow
    float2 mc = q - float2(W * 0.6, 0.52);
    float mon = 1.0 - smoothstep(0.0, 0.035, sd_box(mc, float2(0.27, 0.165), 0.02));
    float row = floor(mc.y * 26.0);
    float len = 0.08 + 0.36 * hash21(float2(row, 3.0)), ind = 0.03 * floor(hash21(float2(row, 7.0)) * 3.0);
    float dash = step(0.35, fract(mc.y * 26.0)) * step(-0.23 + ind, mc.x) * step(mc.x, -0.23 + ind + len) * step(0.25, hash21(float2(row, 5.0)));
    float3 ink = 0.55 + 0.45 * cos(6.2831 * (hash21(float2(row, 9.0)) + float3(0.0, 0.33, 0.67)));
    float3 scr = float3(0.07, 0.09, 0.14) + ink * dash * 0.55;
    room = mix(room, scr, mon);
    room += float3(0.3, 0.5, 0.85) * exp(-dot(mc, mc) * 4.5) * 0.1;
    float stand = 1.0 - smoothstep(0.0, 0.03, sd_box(q - float2(W * 0.6, 0.29), float2(0.03, 0.08), 0.01));
    room = mix(room, float3(0.12, 0.12, 0.14) * lit, stand);
    // the desk the tank stands on, and a mug on it
    float desk = smoothstep(0.235, 0.205, uv.y);
    float3 wood = float3(0.44, 0.29, 0.17) * (0.82 + 0.2 * vnoise(float2(q.x * 3.0, q.y * 40.0))) * lit;
    room = mix(room, wood, desk);
    float2 gc = q - float2(W * 0.4, 0.3);
    float mug = min(sd_box(gc, float2(0.055, 0.075), 0.02), abs(length(gc - float2(0.07, 0.0)) - 0.038) - 0.012);
    room = mix(room, float3(0.86, 0.34, 0.28) * lit, 1.0 - smoothstep(0.0, 0.03, mug));
    float steam = exp(-pow((gc.x - 0.012 * sin(gc.y * 18.0 - t * 1.5)) / 0.02, 2.0)) * smoothstep(0.09, 0.14, gc.y) * (1.0 - smoothstep(0.2, 0.34, gc.y));
    room += float3(1.0) * steam * 0.07 * day;
    // the cat: every couple of minutes it walks in from the left, sits behind the tank and stares at the fish
    float cyc = fract(t / 150.0 + 0.9);
    float there = smoothstep(0.06, 0.12, cyc) * (1.0 - smoothstep(0.26, 0.32, cyc));
    if (there > 0.001) {
        float2 cp = q - float2(mix(-0.3, W * 0.27, there), 0.2);
        float body = (length((cp - float2(0.0, 0.07)) / float2(0.13, 0.17)) - 1.0) * 0.13;
        float2 hp = cp - float2(0.02, 0.3 + 0.004 * sin(t * 1.3));
        float head = (length(hp / float2(0.105, 0.09)) - 1.0) * 0.09;
        float ears = min(sd_tri(hp, float2(-0.095, 0.03), float2(-0.03, 0.075), float2(-0.085, 0.15)),
                         sd_tri(hp, float2(0.095, 0.03), float2(0.03, 0.075), float2(0.085, 0.15)));
        float tail = abs(length(cp - float2(0.2, 0.1)) - 0.1) - 0.018 + step(cp.y, 0.02) + step(cp.x, 0.2) * 0.0;
        float cat = min(min(body, head), min(ears, tail));
        float ca = 1.0 - smoothstep(0.0, 0.025, cat);
        float3 fur = float3(0.2, 0.19, 0.2) * (0.8 + 0.3 * vnoise(cp * 30.0)) * lit;
        // the eyes follow the fish a little, and blink
        float blink = step(0.06, fract(t / 4.3));
        for (int k = -1; k <= 1; k += 2) {
            float2 ep = hp - float2(0.04 * float(k), 0.01);
            float eye = 1.0 - smoothstep(0.7, 1.0, length(ep / float2(0.024, 0.02 * blink + 0.002)));
            float pupil = 1.0 - smoothstep(0.5, 1.0, length((ep - float2(gaze.x * 0.006 + 0.004 * sin(t * 0.4), 0.0)) / float2(0.007, 0.018)));
            fur = mix(fur, mix(float3(0.75, 0.9, 0.3), float3(0.02), pupil), eye);
        }
        room = mix(room, fur, ca);
    }
    // through the glass and the water: tinted, soft, with a faint reflection across the back pane
    float3 c3 = mix(room, water, 0.4) * (0.5 + 0.5 * light);
    c3 += (1.0 - smoothstep(0.0, 0.06, abs(fract((uv.x * 0.7 + uv.y * 0.5) * 1.3) - 0.5) - 0.02)) * 0.03;
    return float4(c3 * 0.86, 0.86);
}

// shared: plastic catches the light in a hard little highlight
float3 desk_plastic(float3 base, float2 n2, float gloss) {
    float3 n = normalize(float3(n2, sqrt(max(0.05, 1.0 - dot(n2, n2)))));
    float diff = max(0.0, dot(n, normalize(float3(-0.3, 0.8, 0.5))));
    float spec = pow(max(0.0, dot(reflect(-normalize(float3(-0.3, 0.8, 0.5)), n), float3(0.0, 0.0, 1.0))), 22.0);
    return base * (0.55 + 0.6 * diff) + float3(1.0) * spec * gloss;
}

// A plastic castle: two towers with pointed roofs and little flags, a wall with battlements between them, an arched
// doorway and windows, all in one molded color (col), algae creeping up from the base.
// p = c * (0.9, 1.0); the ground at p.y = -0.9. extra.y: the seed (roof color, how much algae).
float4 draw_desk_castle(float2 c, float t, float glow, float4 col, float4 extra) {
    float2 p = c * float2(0.9, 1.0);
    float seed = extra.y;
    float wall = sd_box(p - float2(0.0, -0.5), float2(0.42, 0.4), 0.02);
    // battlements: notches along the top of the wall
    float notch = step(0.5, fract(p.x * 6.0 + 0.25)) * step(-0.14, p.y) * step(abs(p.x), 0.42);
    wall = max(wall, notch > 0.5 ? p.y + 0.18 : -1.0);
    float tl = sd_box(p - float2(-0.55, -0.3), float2(0.2, 0.6), 0.02);
    float tr = sd_box(p - float2(0.55, -0.38), float2(0.18, 0.52), 0.02);
    float rl = sd_tri(p, float2(-0.8, 0.3), float2(-0.3, 0.3), float2(-0.55, 0.78));
    float rr = sd_tri(p, float2(0.33, 0.14), float2(0.77, 0.14), float2(0.55, 0.56));
    float stone = min(wall, min(tl, tr));
    float roofs = min(rl, rr) - 0.01;
    // flags on the roofs, waving
    float fw = sin(t * 3.0 + p.x * 20.0) * 0.012;
    float flags = min(sd_box(p - float2(-0.55, 0.86), float2(0.008, 0.09), 0.0), sd_tri(p, float2(-0.545, 0.94), float2(-0.545, 0.84), float2(-0.38, 0.89 + fw)));
    flags = min(flags, min(sd_box(p - float2(0.55, 0.64), float2(0.008, 0.09), 0.0), sd_tri(p, float2(0.555, 0.72), float2(0.555, 0.62), float2(0.7, 0.67 + fw))));
    float d = min(stone, min(roofs, flags));
    d = max(d, -(p.y + 0.9));
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    if (a <= 0.001) return float4(0.0);
    float lum = max(col.r, max(col.g, col.b));
    float3 base = col.rgb;
    float3 c3 = desk_plastic(base, float2(clamp(p.x * 1.1, -0.9, 0.9), 0.2), 0.25);
    // molded bricks: shallow grooves
    float2 bg = float2(p.x * 9.0 + floor(p.y * 14.0) * 0.5, p.y * 14.0);
    float groove = max(1.0 - smoothstep(0.03, 0.08, abs(fract(bg.x) - 0.5) - 0.42), 1.0 - smoothstep(0.03, 0.09, abs(fract(bg.y) - 0.5) - 0.42));
    c3 *= 1.0 - groove * 0.14 * step(stone, 0.0);
    // towers rounder than the wall; the roofs a brighter plastic
    c3 *= 0.85 + 0.25 * smoothstep(0.2, 0.0, abs(abs(p.x) - 0.55)) * step(min(tl, tr), wall);
    float3 roofC = (0.55 + 0.45 * cos(6.2831 * (seed + float3(0.0, 0.33, 0.67)))) * lum;
    if (roofs < min(stone, flags)) c3 = desk_plastic(roofC, float2((abs(p.x) - 0.55) * 4.0, 0.3), 0.4);
    if (flags < min(stone, roofs)) c3 = float3(1.0, 0.85, 0.2) * lum;
    // the doorway and the windows: dark holes
    float door = max(sd_box(p - float2(0.0, -0.74), float2(0.11, 0.18), 0.0), -1.0);
    door = min(door, length(p - float2(0.0, -0.56)) - 0.11);
    float wins = min(min(sd_box(p - float2(-0.55, 0.05), float2(0.04, 0.075), 0.03), sd_box(p - float2(0.55, -0.1), float2(0.04, 0.07), 0.03)),
                     sd_box(p - float2(-0.55, -0.4), float2(0.04, 0.075), 0.03));
    float hole = 1.0 - smoothstep(-0.005, 0.01, min(door, wins));
    c3 = mix(c3, float3(0.03, 0.05, 0.08), hole * 0.9);
    // algae from the base up, more on some
    float alg = smoothstep(-0.3 + 0.3 * seed, -0.9, p.y) * smoothstep(0.35, 0.7, vnoise(p * 9.0 + seed * 5.0));
    c3 = mix(c3, float3(0.2, 0.42, 0.18) * lum, alg * 0.6 * (1.0 - hole));
    c3 *= 0.7 + 0.3 * smoothstep(-0.9, -0.6, p.y);                                   // darker at the gravel
    return float4(c3 * a, a);
}

// A plastic plant: a round base, stiff stems and identical leaves in a color no plant has (the seed picks it:
// neon green, pink, purple, orange), swaying all together, a little shine on each leaf.
// p = c * (0.6, 1.0); the ground at p.y = -0.9.
float4 draw_desk_plant(float2 c, float t, float glow, float4 col, float4 extra) {
    float2 p = c * float2(0.6, 1.0);
    float seed = extra.y;
    float lum = max(col.r, max(col.g, col.b));
    float pick = floor(seed * 3.99);
    float3 leafC = (pick < 0.5 ? float3(0.2, 0.95, 0.35) : pick < 1.5 ? float3(1.0, 0.35, 0.65) : pick < 2.5 ? float3(0.65, 0.4, 1.0) : float3(1.0, 0.6, 0.15)) * lum;
    float4 o = float4(0.0);
    // the base: a dome of plastic on the gravel
    float base = (length((p - float2(0.0, -0.88)) / float2(0.2, 0.08)) - 1.0) * 0.08;
    float ab = 1.0 - smoothstep(0.0, 0.012, base);
    o = float4(desk_plastic(float3(0.25, 0.22, 0.2) * lum, (p - float2(0.0, -0.88)) / float2(0.2, 0.08), 0.3) * ab, ab);
    for (int s = 0; s < 5; s++) {
        float fs = float(s);
        float lean = (fs - 2.0) * 0.16;
        float hgt = 1.2 + 0.5 * hash21(float2(fs, seed * 9.0));
        float y = clamp(p.y, -0.86, -0.86 + hgt);
        float u = (y + 0.86) / hgt;
        float sway = sin(t * 0.8 + seed * 6.0) * 0.05 * u * u;                     // all together: it's one piece
        float sx = lean * u * (1.0 + 0.4 * u) + sway;
        float stem = length(float2(p.x - sx, p.y - y)) - 0.012;
        // leaves in pairs, evenly spaced
        float n = floor(u * 7.0);
        float ly = -0.86 + (n + 0.5) / 7.0 * hgt;
        float lu = (n + 0.5) / 7.0;
        float lx = lean * lu * (1.0 + 0.4 * lu) + sin(t * 0.8 + seed * 6.0) * 0.05 * lu * lu;
        float2 lq = float2(abs(p.x - lx) - 0.075, p.y - ly - abs(p.x - lx) * 0.5);
        float leaf = (length(lq / float2(0.075, 0.035)) - 1.0) * 0.035;
        float dd = min(stem, u < 0.98 ? leaf : 1e3);
        float aa = fwidth(dd) + 1e-4;
        float a = 1.0 - smoothstep(-aa, aa, dd);
        float3 c3 = leafC * (0.6 + 0.5 * u) * (0.9 + 0.1 * fs / 4.0);
        c3 += float3(1.0) * (1.0 - smoothstep(0.0, 0.5, length((lq - float2(-0.02, 0.012)) / float2(0.03, 0.01)))) * 0.35 * step(leaf, stem);
        c3 = mix(c3, leafC * 0.5, step(stem, leaf) * 0.5);
        o = float4(o.rgb * (1.0 - a) + c3 * a, o.a * (1.0 - a) + a);
    }
    return o;
}

// A toy diver in an old suit: round brass helmet with a porthole, a bulky suit, lead boots planted in the gravel, an
// air hose going up, and bubbles coming out of the helmet in a steady string. p = c * (0.6, 1.0); ground at -0.9.
float4 draw_desk_diver(float2 c, float t, float glow, float4 col, float4 extra) {
    float2 p = c * float2(0.6, 1.0);
    float lum = max(col.r, max(col.g, col.b));
    float body = sd_box(p - float2(0.0, -0.42), float2(0.16, 0.24), 0.1);
    float legs = min(sd_box(p - float2(-0.09, -0.76), float2(0.06, 0.12), 0.03), sd_box(p - float2(0.09, -0.76), float2(0.06, 0.12), 0.03));
    float boots = min(sd_box(p - float2(-0.1, -0.86), float2(0.09, 0.045), 0.02), sd_box(p - float2(0.1, -0.86), float2(0.09, 0.045), 0.02));
    float wave = sin(t * 1.2) * 0.04;
    float arms = min(sd_seg(p, float2(-0.16, -0.28), float2(-0.3, -0.5)) - 0.05, sd_seg(p, float2(0.16, -0.28), float2(0.32, -0.12 + wave)) - 0.05);
    float helm = length(p - float2(0.0, -0.02)) - 0.2;
    float collar = sd_box(p - float2(0.0, -0.2), float2(0.19, 0.035), 0.02);
    float hose = abs(p.x - 0.1 - 0.05 * sin(p.y * 5.0 + t * 0.6)) - 0.012;
    hose = max(hose, max(0.12 - p.y, p.y - 0.98));
    float suit = min(min(body, legs), arms);
    float brass = min(helm, min(collar, boots));
    float d = min(min(suit, brass), hose);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float3 c3 = desk_plastic(mix(float3(0.78, 0.7, 0.52), col.rgb, 0.3) * lum, float2(p.x * 4.5, 0.2), 0.15);         // canvas suit
    if (brass < suit) c3 = desk_plastic(float3(0.85, 0.62, 0.22) * lum, (p - float2(0.0, -0.02)) / 0.2 * step(helm, min(collar, boots)), 0.6);
    if (hose < min(suit, brass)) c3 = float3(0.15, 0.15, 0.16) * lum;
    // the porthole: dark glass with a glint, a ring of rivets around it
    float port = length(p - float2(0.03, -0.01));
    c3 = mix(c3, float3(0.08, 0.2, 0.28), (1.0 - smoothstep(0.1, 0.115, port)) * step(helm, 0.0));
    c3 = mix(c3, float3(0.95, 0.75, 0.3) * lum, (1.0 - smoothstep(0.0, 0.01, abs(port - 0.125) - 0.012)) * step(helm, 0.0));
    c3 += float3(1.0) * (1.0 - smoothstep(0.0, 0.03, length(p - float2(-0.01, 0.04)))) * 0.6 * step(port, 0.1);
    float4 o = float4(c3 * a, a);
    // bubbles: a string of them rising from the top of the helmet, wobbling
    for (int i = 0; i < 6; i++) {
        float fi = float(i);
        float ph = fract(t * 0.35 + fi / 6.0);
        float2 bc = float2(-0.08 + sin(ph * 9.0 + fi) * 0.05, 0.2 + ph * 0.78);
        float r = length(p - bc) / (0.02 + 0.02 * ph);
        float ring = (1.0 - smoothstep(0.85, 1.0, r)) * (0.25 + 0.6 * smoothstep(0.5, 0.95, r)) * (1.0 - smoothstep(0.85, 1.0, ph));
        o += float4(float3(0.85, 0.97, 1.0) * ring, ring) * (1.0 - o.a);
    }
    return o;
}

// A little sign on a stick, planted crooked in the gravel: a white board with a red circle and bar over a fish hook
// (no fishing). p = c * (0.8, 1.0); the ground at p.y = -0.9. extra.y: the seed (how crooked).
float4 draw_desk_sign(float2 c, float t, float glow, float4 col, float4 extra) {
    float2 p = c * float2(0.8, 1.0);
    float ang = (extra.y - 0.5) * 0.3;
    float2 q = float2(p.x * cos(ang) - (p.y + 0.9) * sin(ang), p.x * sin(ang) + (p.y + 0.9) * cos(ang) - 0.9);
    float lum = max(col.r, max(col.g, col.b));
    float post = sd_box(q - float2(0.0, -0.45), float2(0.035, 0.46), 0.01);
    float board = sd_box(q - float2(0.0, 0.3), float2(0.5, 0.42), 0.05);
    float d = min(post, board);
    d = max(d, -(p.y + 0.92));
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    if (a <= 0.001) return float4(0.0);
    float3 c3 = float3(0.5, 0.36, 0.22) * (0.85 + 0.2 * vnoise(float2(q.x * 30.0, q.y * 4.0))) * lum;
    if (board < post) {
        c3 = float3(0.95, 0.94, 0.9) * (0.9 + 0.1 * smoothstep(-0.2, 0.7, q.y)) * lum;
        c3 = mix(c3, float3(0.5, 0.36, 0.22) * lum, 1.0 - smoothstep(0.0, 0.03, -board - 0.0));       // a wooden edge
        float2 s = q - float2(0.0, 0.3);
        // the hook: a shank, a bend and a barb
        float hook = min(sd_seg(s, float2(0.04, 0.2), float2(0.04, -0.08)), abs(length(s - float2(-0.03, -0.08)) - 0.07) + step(-0.08, s.y) * 1.0) - 0.022;
        hook = min(hook, sd_seg(s, float2(-0.1, -0.08), float2(-0.1, -0.02)) - 0.02);
        c3 = mix(c3, float3(0.25, 0.27, 0.3) * lum, 1.0 - smoothstep(0.0, 0.015, hook));
        // the red circle and the bar across
        float ring = abs(length(s) - 0.3) - 0.04;
        float bar = max(abs(dot(s, normalize(float2(1.0, 1.0)))) - 0.04, length(s) - 0.3);
        c3 = mix(c3, float3(0.9, 0.15, 0.12) * lum, 1.0 - smoothstep(0.0, 0.015, min(ring, bar)));
    }
    c3 *= 0.75 + 0.25 * smoothstep(-0.9, -0.7, p.y);
    return float4(c3 * a, a);
}

// The toy treasure chest (the theme's chest): molded plastic, gold-painted bands, a lid that swings open on its
// hinge (extra.y: 0 closed … 1 open) showing a pile of painted coins, with a puff of bubbles while it's open.
// p = c; the ground at p.y = -0.9.
float4 draw_desk_chest(float2 c, float t, float glow, float4 col, float4 extra) {
    float2 p = c;
    float open = clamp(extra.y, 0.0, 1.0);
    float lum = max(col.r, max(col.g, col.b));
    float box = sd_box(p - float2(0.0, -0.55), float2(0.62, 0.34), 0.05);
    // the lid turns about the back top edge
    float ang = -open * 1.1;
    float2 hinge = float2(-0.6, -0.2);
    float2 lp = p - hinge;
    lp = float2(lp.x * cos(ang) - lp.y * sin(ang), lp.x * sin(ang) + lp.y * cos(ang)) + hinge;
    float lid = max((length((lp - float2(0.0, -0.2)) / float2(0.64, 0.34)) - 1.0) * 0.34, -(lp.y + 0.2));
    float d = min(box, lid);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float3 plast = mix(float3(0.62, 0.3, 0.14), col.rgb, 0.3) * lum, gold = float3(1.0, 0.8, 0.25) * lum;
    float3 c3 = desk_plastic(plast, float2(p.x * 1.2, lid < box ? 0.5 : 0.1), 0.35);
    // bands and a lock
    float2 bp = lid < box ? lp : p;
    float bands = min(abs(abs(bp.x) - 0.36) - 0.045, lid < box ? 1.0 : abs(p.y + 0.24) - 0.03);
    c3 = mix(c3, gold * (0.8 + 0.3 * smoothstep(-0.9, 0.2, p.y)), 1.0 - smoothstep(0.0, 0.012, bands));
    c3 = mix(c3, gold, (1.0 - smoothstep(0.0, 0.012, sd_box(p - float2(0.0, -0.3), float2(0.06, 0.07), 0.02))) * step(box, lid) * (1.0 - open));
    float4 o = float4(c3 * a, a);
    // the coins inside, seen when it opens, and the glow over them
    if (open > 0.05) {
        float coins = (length((p - float2(0.02, -0.2)) / float2(0.5, 0.14 * open)) - 1.0) * 0.14;
        float ca = (1.0 - smoothstep(0.0, 0.012, coins)) * (1.0 - smoothstep(-0.02, 0.0, -box)) * step(lid, 1e3) * (lid > 0.0 ? 1.0 : 0.0);
        float2 cg = p * float2(9.0, 16.0);
        float3 coinC = gold * (0.75 + 0.4 * step(0.5, hash21(floor(cg)))) + float3(1.0) * step(0.93, hash21(floor(cg) + 2.0)) * 0.4;
        o = float4(o.rgb * (1.0 - ca) + coinC * ca, max(o.a, ca));
        float halo = open * exp(-pow(length((p - float2(0.0, -0.05)) / float2(0.7, 0.45)), 2.0) * 2.5) * (0.25 + 0.5 * glow) * (1.0 - o.a);
        o += float4(float3(1.0, 0.85, 0.4) * halo, halo * 0.5);
        for (int i = 0; i < 4; i++) {
            float fi = float(i);
            float ph = fract(t * 0.5 + fi * 0.27);
            float2 bc = float2((fi - 1.5) * 0.18 + sin(ph * 8.0 + fi) * 0.05, -0.1 + ph * 1.0);
            float r = length(p - bc) / (0.03 + 0.03 * ph);
            float ring = (1.0 - smoothstep(0.85, 1.0, r)) * (0.2 + 0.6 * smoothstep(0.5, 0.95, r)) * (1.0 - smoothstep(0.8, 1.0, ph)) * open;
            o += float4(float3(0.85, 0.97, 1.0) * ring, ring) * (1.0 - o.a);
        }
    }
    return o;
}

// A piece of aquarium gravel: a smooth little stone in a candy color (the seed picks it), glossy.
// p = c * (1.0, 0.7).
float4 draw_desk_gravel(float2 c, float t, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.0, 0.7);
    float seed = extra.y;
    float2 b = p / float2(0.82 + 0.12 * sin(seed * 20.0), 0.5);
    float d = (length(b) - 1.0) * 0.5;
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float lum = max(col.r, max(col.g, col.b));
    float pick = floor(fract(seed * 7.31) * 5.99);
    float3 base = pick < 0.5 ? float3(1.0, 0.4, 0.6) : pick < 1.5 ? float3(1.0, 0.85, 0.25) : pick < 2.5 ? float3(0.35, 0.9, 0.5)
                : pick < 3.5 ? float3(0.95, 0.95, 1.0) : pick < 4.5 ? float3(0.6, 0.4, 1.0) : float3(0.3, 0.75, 1.0);
    float3 c3 = desk_plastic(base * lum, b * 0.9, 0.5);
    return float4(c3 * a, a);
}

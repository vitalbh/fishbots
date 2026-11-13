// Constellations: the sessions' fish drawn as figures of stars (a fish, a long one, a ray, a whale) and the sparks
// that make the schools.
//
// Every figure is a list of stars (x, y, size 0…1) in the fish's square units, and four ways of joining them (the
// patterns): its outline, a spine with ribs, a lattice of triangles, and a dotted outline. The stars move with the
// swim (constellations_bend), twinkle each at its own pace, the brightest one is the eye, and a faint haze in the
// project's color fills the figure's shape so it still reads as a fish when it's only 30 pixels long.

constant float3 CONSTELLATIONS_FISH[14] = {
    float3(1.02, -0.04, 0.45),   // 0 nose
    float3(0.66, 0.1, 1.0),      // 1 eye
    float3(0.45, 0.3, 0.5),      // 2 top of the head
    float3(0.05, 0.44, 0.7),     // 3 dorsal
    float3(-0.14, 0.58, 0.38),   // 4 dorsal tip
    float3(-0.38, 0.22, 0.45),   // 5 back
    float3(-0.62, 0.0, 0.55),    // 6 tail stock
    float3(-1.08, 0.42, 0.75),   // 7 tail, top
    float3(-1.06, -0.4, 0.62),   // 8 tail, bottom
    float3(0.1, -0.38, 0.6),     // 9 belly
    float3(-0.2, -0.54, 0.35),   // 10 pelvic fin
    float3(-0.4, -0.2, 0.4),     // 11 belly, back
    float3(0.08, 0.0, 0.3),      // 12 middle
    float3(0.42, -0.16, 0.35)    // 13 gill
};
constant int2 CONSTELLATIONS_FISH_SEGS[4][17] = {
    { int2(0, 2), int2(2, 3), int2(3, 5), int2(5, 6), int2(6, 7), int2(7, 8), int2(8, 6), int2(6, 11), int2(11, 9),
      int2(9, 0), int2(3, 4), int2(9, 10), int2(-1, -1) },
    { int2(0, 13), int2(13, 12), int2(12, 6), int2(6, 7), int2(6, 8), int2(12, 3), int2(12, 9), int2(13, 2),
      int2(3, 4), int2(9, 10), int2(2, 3), int2(-1, -1) },
    { int2(0, 2), int2(2, 13), int2(13, 0), int2(2, 3), int2(3, 13), int2(13, 9), int2(9, 0), int2(3, 5),
      int2(5, 11), int2(11, 9), int2(5, 6), int2(11, 6), int2(6, 7), int2(6, 8), int2(7, 8), int2(-1, -1) },
    { int2(0, 2), int2(2, 3), int2(3, 5), int2(5, 6), int2(6, 7), int2(7, 8), int2(8, 6), int2(6, 11), int2(11, 9),
      int2(9, 0), int2(3, 4), int2(-1, -1) }
};

constant float3 CONSTELLATIONS_LONG[15] = {
    float3(2.1, 0.0, 0.45),      // 0 snout
    float3(1.8, 0.1, 1.0),       // 1 eye
    float3(1.72, -0.15, 0.35),   // 2 throat
    float3(1.36, 0.03, 0.5),     // 3
    float3(0.9, 0.0, 0.7),       // 4
    float3(0.45, -0.02, 0.4),    // 5
    float3(0.0, 0.0, 0.62),      // 6
    float3(-0.45, 0.01, 0.42),   // 7
    float3(-0.9, 0.0, 0.55),     // 8
    float3(-1.35, 0.0, 0.4),     // 9
    float3(-1.75, 0.0, 0.42),    // 10
    float3(-2.08, 0.0, 0.62),    // 11 tail tip
    float3(0.62, 0.3, 0.36),     // 12 dorsal
    float3(-0.25, 0.28, 0.34),   // 13 dorsal, back
    float3(-0.62, -0.27, 0.32)   // 14 anal fin
};
constant int2 CONSTELLATIONS_LONG_SEGS[4][17] = {
    { int2(0, 3), int2(3, 4), int2(4, 5), int2(5, 6), int2(6, 7), int2(7, 8), int2(8, 9), int2(9, 10), int2(10, 11),
      int2(0, 2), int2(2, 3), int2(-1, -1) },
    { int2(0, 3), int2(3, 4), int2(4, 5), int2(5, 6), int2(6, 7), int2(7, 8), int2(8, 9), int2(9, 10), int2(10, 11),
      int2(0, 2), int2(4, 12), int2(12, 13), int2(13, 8), int2(7, 14), int2(-1, -1) },
    { int2(0, 2), int2(2, 3), int2(0, 3), int2(3, 4), int2(4, 12), int2(12, 5), int2(5, 6), int2(6, 13), int2(13, 7),
      int2(7, 8), int2(8, 14), int2(14, 9), int2(9, 10), int2(10, 11), int2(-1, -1) },
    { int2(0, 3), int2(3, 4), int2(4, 5), int2(5, 6), int2(6, 7), int2(7, 8), int2(8, 9), int2(9, 10), int2(10, 11),
      int2(0, 2), int2(2, 3), int2(-1, -1) }
};

// The ray, seen from above as it glides: head to +x, the wings reaching up and down, a long thin tail.
constant float3 CONSTELLATIONS_RAY[13] = {
    float3(0.92, 0.14, 0.42),    // 0 horn, upper
    float3(0.92, -0.14, 0.42),   // 1 horn, lower
    float3(0.6, 0.16, 1.0),      // 2 eye
    float3(0.22, 0.0, 0.55),     // 3 middle
    float3(-0.08, 0.92, 0.78),   // 4 wingtip, upper
    float3(-0.08, -0.92, 0.72),  // 5 wingtip, lower
    float3(-0.36, 0.3, 0.4),     // 6 wing's back edge, upper
    float3(-0.36, -0.3, 0.4),    // 7 wing's back edge, lower
    float3(-0.5, 0.0, 0.5),      // 8 tail base
    float3(-0.86, 0.02, 0.3),    // 9 tail
    float3(-1.22, 0.0, 0.38),    // 10 tail tip
    float3(0.48, 0.44, 0.36),    // 11 wing's front edge, upper
    float3(0.48, -0.44, 0.36)    // 12 wing's front edge, lower
};
constant int2 CONSTELLATIONS_RAY_SEGS[4][17] = {
    { int2(0, 11), int2(11, 4), int2(4, 6), int2(6, 8), int2(8, 7), int2(7, 5), int2(5, 12), int2(12, 1), int2(0, 1),
      int2(8, 9), int2(9, 10), int2(-1, -1) },
    { int2(0, 3), int2(1, 3), int2(3, 11), int2(11, 4), int2(3, 12), int2(12, 5), int2(3, 8), int2(8, 9),
      int2(9, 10), int2(-1, -1) },
    { int2(0, 11), int2(11, 4), int2(4, 6), int2(6, 8), int2(8, 7), int2(7, 5), int2(5, 12), int2(12, 1),
      int2(11, 3), int2(12, 3), int2(6, 3), int2(7, 3), int2(0, 3), int2(1, 3), int2(8, 9), int2(9, 10), int2(-1, -1) },
    { int2(0, 11), int2(11, 4), int2(4, 6), int2(6, 8), int2(8, 7), int2(7, 5), int2(5, 12), int2(12, 1), int2(0, 1),
      int2(8, 9), int2(9, 10), int2(-1, -1) }
};

constant float3 CONSTELLATIONS_WHALE[16] = {
    float3(1.62, -0.04, 0.48),   // 0 snout
    float3(1.0, -0.14, 1.0),     // 1 eye (low, by the mouth's corner)
    float3(1.2, 0.26, 0.55),     // 2 top of the head
    float3(0.7, 0.4, 0.42),      // 3 blowhole
    float3(0.0, 0.46, 0.72),     // 4 back
    float3(-0.62, 0.32, 0.45),   // 5 small dorsal
    float3(-1.12, 0.14, 0.5),    // 6 tail stock
    float3(-1.62, 0.34, 0.7),    // 7 fluke, upper (seen edge-on: a narrow fork)
    float3(-1.6, 0.04, 0.6),     // 8 fluke, lower
    float3(0.1, -0.42, 0.62),    // 9 belly
    float3(1.2, -0.32, 0.42),    // 10 throat
    float3(0.22, -0.7, 0.42),    // 11 flipper tip
    float3(-0.6, -0.14, 0.4),    // 12 belly, back
    float3(0.3, 0.02, 0.3),      // 13 middle
    float3(0.68, -0.4, 0.32),    // 14 flipper base
    float3(-0.45, 0.42, 0.28)    // 15 dorsal tip
};
// (the throat's grooves: lines along the throat, in every pattern, so the whale reads as a whale)
constant int2 CONSTELLATIONS_WHALE_SEGS[4][17] = {
    { int2(0, 2), int2(2, 3), int2(3, 4), int2(4, 5), int2(5, 15), int2(5, 6), int2(6, 7), int2(7, 8), int2(8, 6),
      int2(6, 12), int2(12, 9), int2(9, 14), int2(14, 10), int2(10, 0), int2(14, 11), int2(-1, -1) },
    { int2(0, 13), int2(13, 6), int2(6, 7), int2(6, 8), int2(13, 3), int2(13, 4), int2(13, 9), int2(14, 11),
      int2(0, 2), int2(2, 3), int2(4, 5), int2(5, 15), int2(13, 14), int2(10, 14), int2(-1, -1) },
    { int2(0, 2), int2(0, 10), int2(2, 10), int2(2, 4), int2(4, 10), int2(4, 9), int2(9, 10), int2(4, 5),
      int2(5, 12), int2(9, 12), int2(5, 6), int2(12, 6), int2(6, 7), int2(6, 8), int2(14, 11), int2(-1, -1) },
    { int2(0, 2), int2(2, 3), int2(3, 4), int2(4, 5), int2(5, 6), int2(6, 7), int2(7, 8), int2(8, 6), int2(6, 12),
      int2(12, 9), int2(9, 14), int2(14, 10), int2(10, 0), int2(14, 11), int2(-1, -1) }
};

// Where a star of the figure is as it swims. mode 0: a fish (the tail beats), 1: a long one (the whole body
// undulates), 2: a ray (the wings rise and fall, seen from above: they shorten and sweep back), 3: a whale (slow
// flukes, the body barely bends), 4: the dragon (a slow sway all over).
float2 constellations_bend(float2 s, int mode, float phase) {
    if (mode == 0) {
        s.y += sin(phase - s.x * 2.5) * 0.09 * smoothstep(0.4, -1.2, s.x);
    } else if (mode == 1) {
        s.y += sin(phase - s.x * 1.6) * 0.13 * (0.3 + 0.7 * smoothstep(1.9, -2.1, s.x));
    } else if (mode == 2) {
        float w = smoothstep(0.2, 0.95, abs(s.y));
        s.y *= 1.0 - 0.16 * w * (0.5 + 0.5 * sin(phase));
        s.x -= 0.08 * w * cos(phase);
        s.y += sin(phase * 1.3 - s.x * 3.0) * 0.06 * smoothstep(-0.4, -1.2, s.x);
    } else if (mode == 3) {
        s.y += sin(phase - s.x * 1.4) * 0.1 * smoothstep(-0.2, -1.6, s.x);
    } else {
        s += float2(sin(phase * 0.5 + s.y * 3.0), cos(phase * 0.4 + s.x * 3.0)) * 0.03;
    }
    return s;
}

// A figure of stars. p: the point in the figure's square units; stars/segs: the figure and the pattern's lines;
// eye: which star is the eye; hazeD: the figure's shape (signed distance, for the haze and the glow).
float4 constellations_figure(float2 p, constant float3* stars, int n, constant int2* segs, int eye, int mode,
                             float hazeD, float phase, float glow, float4 col, float4 extra, bool dashed, float scale) {
    float px = max(fwidth(p.x), fwidth(p.y)) + 1e-5;
    bool asleep = extra.w > 1.5;
    float dim = asleep ? 0.5 : 1.0;
    float awake = 1.0 + glow * 0.6;
    float3 starC = mix(col.rgb, float3(1.0, 0.98, 0.94), 0.55);
    float3 lineC = mix(col.rgb, float3(0.85, 0.9, 1.0), 0.25);
    // the haze: the figure's shape, faint, a little cloudy
    float haze = (1.0 - smoothstep(-0.14 * scale, 0.06 * scale, hazeD)) * (0.6 + 0.5 * vnoise(p * 3.2 / scale + phase * 0.03));
    float ha = haze * 0.11 * dim * (1.0 + glow);
    float3 rgb = col.rgb * ha;
    float a = ha;
    // the lines, stopping short of the stars, as on a star chart
    float w = max(0.012 * scale, px * 0.55);
    float la = 0.0;
    for (int i = 0; i < 17; i++) {
        int2 s = segs[i];
        if (s.x < 0) break;
        float2 a0 = constellations_bend(stars[s.x].xy, mode, phase), a1 = constellations_bend(stars[s.y].xy, mode, phase);
        float2 ab = a1 - a0;
        float len = length(ab);
        float h = clamp(dot(p - a0, ab) / (len * len), 0.0, 1.0);
        float d = length(p - a0 - ab * h);
        if (d > w + px * 2.0) continue;
        float m = 1.0 - smoothstep(w - px * 0.5, w + px * 0.5, d);
        float gap = 0.07 * scale + px;
        m *= smoothstep(gap, gap + 0.04 * scale, min(h, 1.0 - h) * len);
        if (dashed) m *= 0.15 + 0.85 * smoothstep(0.18, 0.3, abs(fract(h * len / (0.09 * scale)) - 0.5));
        la = max(la, m);
    }
    la *= 0.5 * dim * awake;
    rgb = rgb * (1.0 - la) + lineC * la;
    a = a + la * (1.0 - a);
    // the stars: a sharp core, a soft halo, spikes on the bright ones; each twinkles at its own pace
    float3 sl = float3(0.0);
    float sa = 0.0;
    for (int i = 0; i < n; i++) {
        float2 s = constellations_bend(stars[i].xy, mode, phase);
        float2 q = p - s;
        float r = length(q);
        if (r > 0.45 * scale) continue;
        float size = stars[i].z;
        float hs = hash21(float2(float(i), 7.3));
        float tw = 0.7 + 0.3 * sin(phase * (0.23 + 0.4 * hs) + hs * 40.0);
        float rc = max(mix(0.022, 0.058, size) * scale, px * (0.7 + 0.7 * size));
        if (i == eye) {
            if (asleep) {
                // the eye closed: a short curved line where the bright star was
                float2 eq = q / scale;
                float lid = abs(eq.y + 0.25 * eq.x * eq.x / 0.06 - 0.008) - max(0.008, px / scale * 0.5);
                lid = max(lid, abs(eq.x) - 0.07);
                float m = 1.0 - smoothstep(-px / scale, px / scale, lid);
                sl += starC * m * 0.8;
                sa = max(sa, m * 0.8);
                continue;
            }
            rc *= 1.25;
            tw = 0.92 + 0.08 * sin(phase * 0.5);
        }
        float core = 1.0 - smoothstep(rc * 0.45, rc, r);
        float halo = exp(-r * r / (rc * rc * (i == eye ? 4.0 : 7.0))) * (0.25 + 0.5 * size);
        float spike = 0.0;
        if (size > 0.6) {
            float k = (size - 0.55) * (i == eye ? 2.2 : 1.6);
            float th = px * 0.6 + 0.004 * scale;
            float L = rc * (i == eye ? 3.2 : 3.5 + 2.5 * size);
            spike = (exp(-abs(q.y) / th) * exp(-abs(q.x) / L) + exp(-abs(q.x) / th) * exp(-abs(q.y) / L)) * k;
        }
        float lum = (core + halo * 0.7 + spike * 0.6) * tw * dim * awake * (i == eye ? 1.25 : 1.0);
        float3 sc = i == eye ? mix(starC, float3(1.0), 0.5) : starC;
        sl += mix(col.rgb * 1.1, sc, core) * lum;
        sa = max(sa, min(1.0, lum));
    }
    rgb += sl;
    a = max(a, sa);
    // when it needs you: brighter, and a wide halo around the whole figure
    rgb += col.rgb * glow * 0.45 * a;
    float halo = glow * exp(-max(hazeD, 0.0) * 5.0 / scale) * 0.6;
    rgb += col.rgb * halo * (1.0 - a);
    a = a + halo * (1.0 - a) * 0.55;
    return float4(rgb, min(a, 1.0)) * col.a;
}

float constellations_fade(float2 c) { return 1.0 - smoothstep(0.7, 1.0, max(abs(c.x), abs(c.y))); }

// A fish of stars: a plain fish shape, a forked tail. extra.y: the pattern (outline, spine, lattice, dotted).
float4 draw_constellations_fish(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.25, 0.8);
    int pat = int(extra.y + 0.5) % 4;
    float2 hp = p;
    hp.y -= sin(phase - p.x * 2.5) * 0.09 * smoothstep(0.4, -1.2, p.x);
    float body = (length((hp - float2(0.18, 0.0)) / float2(0.84, 0.4 * mix(0.45, 1.0, smoothstep(-0.7, 0.2, hp.x)))) - 1.0) * 0.32;
    float tail = sd_tri(hp, float2(-0.55, 0.0), float2(-1.06, 0.42), float2(-1.04, -0.4));
    float dors = sd_tri(hp, float2(0.2, 0.36), float2(-0.32, 0.22), float2(-0.12, 0.56));
    float d = min(min(body, tail), dors);
    float4 o = constellations_figure(p, CONSTELLATIONS_FISH, 14, CONSTELLATIONS_FISH_SEGS[pat], 1, 0, d, phase, glow, col,
                                     float4(0.0, extra.y, 0.0, extra.w), pat == 3, 1.0);
    return o * constellations_fade(c);
}

// A long fish of stars, an eel or a needlefish: a chain of stars that undulates from head to tail.
float4 draw_constellations_long(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(2.3, 0.55);
    int pat = int(extra.y + 0.5) % 4;
    float2 hp = p;
    hp.y -= sin(phase - p.x * 1.6) * 0.13 * (0.3 + 0.7 * smoothstep(1.9, -2.1, p.x));
    float th = mix(0.05, 0.17, smoothstep(-2.1, 1.0, hp.x)) * (1.0 - 0.4 * smoothstep(1.4, 2.1, hp.x));
    float d = max(abs(hp.y) - th, abs(hp.x) - 2.1);
    float4 o = constellations_figure(p, CONSTELLATIONS_LONG, 15, CONSTELLATIONS_LONG_SEGS[pat], 1, 1, d, phase, glow, col,
                                     float4(0.0, extra.y, 0.0, extra.w), pat == 3, 1.15);
    return o * constellations_fade(c);
}

// A ray of stars, seen from above as it glides: wide wings that rise and fall, two horns, a long thin tail.
float4 draw_constellations_ray(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.3, 1.05);
    int pat = int(extra.y + 0.5) % 4;
    float2 hp = p;
    float flap = 1.0 - 0.16 * (0.5 + 0.5 * sin(phase));
    hp.y /= mix(1.0, flap, smoothstep(0.2, 0.95, abs(hp.y)));
    float wings = min(sd_tri(hp, float2(0.95, 0.0), float2(-0.08, 0.92), float2(-0.5, 0.0)),
                      sd_tri(hp, float2(0.95, 0.0), float2(-0.5, 0.0), float2(-0.08, -0.92)));
    float tail = sd_seg(hp, float2(-0.5, 0.0), float2(-1.2, 0.0)) - 0.02;
    float d = min(wings + 0.03, tail);
    float4 o = constellations_figure(p, CONSTELLATIONS_RAY, 13, CONSTELLATIONS_RAY_SEGS[pat], 2, 2, d, phase, glow, col,
                                     float4(0.0, extra.y, 0.0, extra.w), pat == 3, 1.05);
    return o * constellations_fade(c);
}

// A whale of stars: a long heavy body, a big head, a small dorsal, a long flipper and wide flukes that beat slowly.
float4 draw_constellations_whale(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.7, 0.78);
    int pat = int(extra.y + 0.5) % 4;
    float2 hp = p;
    hp.y -= sin(phase - p.x * 1.4) * 0.1 * smoothstep(-0.2, -1.6, p.x);
    float ry = 0.44 * mix(0.3, 1.0, smoothstep(-1.2, 0.2, hp.x));
    float body = (length((hp - float2(0.22, 0.03 + 0.1 * smoothstep(0.0, -1.2, hp.x))) / float2(1.4, ry)) - 1.0) * 0.4;
    float flukes = sd_tri(hp, float2(-1.05, 0.14), float2(-1.62, 0.36), float2(-1.6, 0.02));
    float flip = sd_seg(hp, float2(0.7, -0.38), float2(0.24, -0.66)) - 0.05;
    float d = min(min(body, flukes), flip);
    float4 o = constellations_figure(p, CONSTELLATIONS_WHALE, 16, CONSTELLATIONS_WHALE_SEGS[pat], 1, 3, d, phase, glow, col,
                                     float4(0.0, extra.y, 0.0, extra.w), pat == 3, 1.15);
    return o * constellations_fade(c);
}

// A spark: one small star with a short streak behind it, a meteor in a shower (the schools). The streak flickers.
float4 draw_constellations_spark(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(2.0, 0.5);
    float px = max(fwidth(p.x), fwidth(p.y)) + 1e-5;
    float2 head = float2(1.3, 0.0);
    float2 q = p - head;
    float r = length(q);
    float rc = max(0.09, px * 1.1);
    float core = 1.0 - smoothstep(rc * 0.4, rc, r);
    float halo = exp(-r * r / (rc * rc * 6.0)) * 0.6;
    // the streak: thin, fading toward the back, a little uneven
    float along = clamp(-q.x / 2.9, 0.0, 1.0);
    float wid = max(mix(0.06, 0.01, along), px * 0.5);
    float streak = exp(-abs(q.y) / wid) * (1.0 - along) * step(q.x, 0.0) * (0.75 + 0.25 * sin(p.x * 9.0 - phase * 3.0));
    float tw = 0.8 + 0.2 * sin(phase * 0.7 + hash21(float2(extra.y, 3.0)) * 30.0);
    float3 hot = mix(col.rgb, float3(1.0), 0.6);
    float lum = (core + halo) * tw;
    float sa = streak * 0.55;
    float3 rgb = hot * lum + col.rgb * sa;
    float a = clamp(max(lum, sa), 0.0, 1.0);
    return float4(rgb, a) * col.a * constellations_fade(c);
}

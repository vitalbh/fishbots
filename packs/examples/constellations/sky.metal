// Constellations: the night sky itself, the stellar nursery where sessions are born, the chest of stars adrift, and
// the stardust and sparkles that take the place of the marine snow, the bubbles and the food.

// One layer of stars: a grid of cells, some with a star somewhere in them, most faint and a few bright, each
// twinkling slowly at its own pace and in its own color (bluer or warmer). q in the sky's square units.
float3 constellations_stars(float2 q, float cells, float density, float t, float bright, float seed) {
    float2 g = q * cells;
    float2 id = floor(g);
    float h = hash21(id + seed);
    if (h > density) return float3(0.0);
    float2 off = float2(hash21(id + seed + 1.3), hash21(id + seed + 7.1)) * 0.7 + 0.15;
    float2 dq = (fract(g) - off) / cells;
    float px = fwidth(q.y) + 1e-6;
    float mag = pow(hash21(id + seed + 3.7), 3.0);
    float rad = px * (0.55 + 1.1 * mag * bright);
    float r2 = dot(dq, dq) / (rad * rad);
    float tw = 0.6 + 0.4 * sin(t * (0.25 + 0.9 * hash21(id + seed + 9.2)) + h * 60.0);
    float lum = exp(-r2) * (0.25 + 0.9 * mag) * tw * bright;
    // the brightest get thin spikes
    if (mag * bright > 0.45) {
        float L = px * 9.0 * mag;
        lum += (exp(-abs(dq.y) / (px * 0.5)) * exp(-abs(dq.x) / L) + exp(-abs(dq.x) / (px * 0.5)) * exp(-abs(dq.y) / L)) * 0.35 * mag * tw;
    }
    float3 tint = mix(float3(0.72, 0.82, 1.0), float3(1.0, 0.86, 0.68), hash21(id + seed + 5.5));
    return tint * lum;
}

float constellations_fbm(float2 p) {
    return vnoise(p) * 0.5 + vnoise(p * 2.03 + 3.1) * 0.27 + vnoise(p * 4.1 + 7.7) * 0.15 + vnoise(p * 8.3 + 1.7) * 0.08;
}

// The sky: deep blue at the bottom going to black overhead, the band of the milky way across it with its dark lane
// of dust, two nebulae in quiet colors, a crescent moon, three depths of stars twinkling slowly, the green airglow
// low down, and a shooting star now and then. By day it's the blue hour that never ends: lighter, bluer, the stars
// fainter but there. At dawn and dusk a warm glow rises from below.
float4 draw_constellations_sky(float2 uv, float t, float light, float2 gaze, float3 water, float4 extra) {
    float aspect = extra.x;
    float night = clamp(extra.y, 0.0, 1.0);
    float day = smoothstep(0.62, 0.95, light) * (1.0 - night);              // (the theme's light runs 0.6 at night … 1 at noon)
    float twilight = clamp(1.0 - abs(light - 0.5) * 3.2, 0.0, 1.0) * (1.0 - night * 0.6);
    float2 q = float2(uv.x * aspect, uv.y);
    // the sky's color: black overhead, deep blue low down
    float3 zenith = mix(float3(0.002, 0.004, 0.012), float3(0.05, 0.1, 0.24), day);
    float3 low = mix(float3(0.014, 0.024, 0.06), float3(0.2, 0.3, 0.52), day);
    float3 rgb = mix(low, zenith, smoothstep(0.0, 0.95, uv.y));
    rgb += float3(0.3, 0.13, 0.12) * twilight * exp(-uv.y * 4.0) * 0.6;              // dawn, dusk: warm from below
    rgb += float3(0.012, 0.03, 0.022) * exp(-uv.y * 7.0) * (1.0 - day);              // the airglow, faint green
    float starK = mix(1.0, 0.4, day);
    // the milky way: a band across, lumpy, with a dark lane of dust down its middle
    float2 mq = q + gaze * 0.004;
    float2 dir = normalize(float2(1.0, 0.42));
    float across = dot(mq - float2(aspect * 0.5, 0.48), float2(-dir.y, dir.x));
    float alongB = dot(mq, dir);
    float wob = (vnoise(float2(alongB * 1.6, 2.0)) - 0.5) * 0.12;
    float band = exp(-pow((across - wob) / 0.17, 2.0));
    float cloud = constellations_fbm(float2(alongB * 3.0, across * 6.0) + 11.0);
    float lane = smoothstep(0.035, 0.0, abs(across - wob * 0.6 + (vnoise(float2(alongB * 4.0, 5.0)) - 0.5) * 0.06))
               * smoothstep(0.35, 0.65, constellations_fbm(float2(alongB * 5.0, across * 9.0) + 3.0));
    float milk = band * smoothstep(0.25, 0.85, cloud) * (1.0 - lane * 0.85);
    rgb += mix(float3(0.5, 0.56, 0.75), float3(0.75, 0.66, 0.55), smoothstep(0.4, 0.8, cloud)) * milk * 0.11 * starK;
    // the nebulae: soft and restrained, one teal, one rose
    {
        float2 n1 = (q - float2(aspect * 0.2, 0.7)) / float2(0.32, 0.2);
        float k1 = exp(-dot(n1, n1)) * smoothstep(0.35, 0.85, constellations_fbm(q * 3.3 + float2(t * 0.002, 4.0)));
        float2 n2 = (q - float2(aspect * 0.8, 0.32)) / float2(0.26, 0.22);
        float k2 = exp(-dot(n2, n2)) * smoothstep(0.3, 0.85, constellations_fbm(q * 2.7 + float2(9.0, -t * 0.0015)));
        rgb += (float3(0.12, 0.42, 0.5) * k1 + float3(0.5, 0.2, 0.42) * k2) * 0.11 * mix(1.0, 0.55, day);
    }
    // the stars, in three depths that move a little with the gaze; more of them in the milky way
    // (as many stars per pixel in a small window as in a big one: the grids follow the window's height)
    float sk = clamp(1.0 / (max(fwidth(uv.y), 1e-5) * 900.0), 0.3, 2.0);
    rgb += constellations_stars(q + gaze * 0.002, 190.0 * sk, 0.12 + 0.4 * band, t, 0.6 * starK, 0.0);
    rgb += constellations_stars(q + gaze * 0.004, 70.0 * sk, 0.3, t, 1.0 * starK, 17.0);
    rgb += constellations_stars(q + gaze * 0.007, max(18.0 * sk, 9.0), 0.45, t * 0.7, 1.35 * starK, 41.0);
    // the moon: a thin crescent high on the right, the rest of its face lit faintly by the earth
    {
        float2 mc = float2(aspect * 0.86, 0.8) + gaze * 0.006;
        float r = 0.034;
        float px = fwidth(q.y) + 1e-6;
        float dm = length(q - mc);
        float disc = 1.0 - smoothstep(r - px, r + px, dm);
        float lit = disc * smoothstep(r * 0.92 - px, r * 0.92 + px, length(q - mc - float2(-0.016, 0.008)));
        float3 moonC = float3(1.0, 0.95, 0.85) * (0.8 + 0.2 * vnoise((q - mc) * 160.0));
        rgb = mix(rgb, moonC * mix(0.95, 0.7, day), lit);
        rgb = mix(rgb, float3(0.1, 0.12, 0.16) * (1.0 - day * 0.5), disc * (1.0 - lit) * 0.45);
        rgb += float3(0.6, 0.65, 0.8) * exp(-max(dm - r, 0.0) * 40.0) * 0.06 * (1.0 - disc);
    }
    // a shooting star now and then: one every ten seconds or so, gone in under a second
    {
        float slot = floor(t / 11.0);
        float hs = hash21(float2(slot, 1.7));
        float tt = t - slot * 11.0 - hs * 8.0;
        if (hs < 0.6 && tt > 0.0 && tt < 0.7) {
            float2 a0 = float2((0.15 + 0.7 * hash21(float2(slot, 4.1))) * aspect, 0.6 + 0.35 * hash21(float2(slot, 8.3)));
            float2 dv = normalize(float2(hash21(float2(slot, 2.2)) < 0.5 ? -1.0 : 1.0, -0.55));
            float2 head = a0 + dv * tt * 0.55;
            float2 tail = head - dv * min(tt, 0.25) * 0.55;
            float2 ab = head - tail;
            float hh = clamp(dot(q - tail, ab) / max(dot(ab, ab), 1e-6), 0.0, 1.0);
            float d = length(q - tail - ab * hh);
            float px = fwidth(q.y) + 1e-6;
            float fade = sin(tt / 0.7 * 3.14159);
            rgb += float3(0.85, 0.9, 1.0) * exp(-d / (px * 0.8)) * hh * hh * fade * 0.9 * starK;
        }
    }
    return float4(rgb, 1.0);
}

// A star as seen up close in a drawing of the sky: a core, a halo, four spikes. Returns its light.
float constellations_twinkle(float2 q, float r0, float spikes) {
    float r = length(q);
    float px = max(fwidth(q.x), fwidth(q.y)) + 1e-5;
    float rc = max(r0, px);
    float core = 1.0 - smoothstep(rc * 0.4, rc, r);
    float halo = exp(-r * r / (rc * rc * 8.0)) * 0.5;
    float L = rc * 7.0;
    float th = px * 0.6 + rc * 0.1;
    float sp = (exp(-abs(q.y) / th) * exp(-abs(q.x) / L) + exp(-abs(q.x) / th) * exp(-abs(q.y) / L)) * spikes;
    return core + halo + sp;
}

// The stellar nursery, where sessions are born: a small bright nebula, rose gas in the clutch's color glowing from
// within, bluer at its edges, wisps curling off it, and young stars shining in its heart. It brightens and its stars
// swell when a session is about to hatch (glow). p = c * (1.3, 1.0).
float4 draw_constellations_nursery(float2 c, float t, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.3, 1.0);
    float fade = 1.0 - smoothstep(0.5, 0.95, max(abs(c.x), abs(c.y)));
    if (fade <= 0.0) return float4(0.0);
    float2 w = p + (float2(vnoise(p * 2.0 + t * 0.02), vnoise(p * 2.0 + 7.0 - t * 0.015)) - 0.5) * 0.35;
    float r = length(w / float2(1.0, 0.7));
    float n = constellations_fbm(w * 2.4 + float2(t * 0.01, 0.0) + 2.0);
    float n2 = constellations_fbm(w * 5.0 - float2(0.0, t * 0.012) + 9.0);
    float body = exp(-r * r * 3.2);
    float gas = body * (0.45 + 0.75 * smoothstep(0.3, 0.8, n)) * (0.75 + 0.35 * n2);
    float core = exp(-dot(w - float2(0.05, -0.02), w - float2(0.05, -0.02)) * 14.0);
    // a few darker knots of dust in it, soft
    float dust = smoothstep(0.55, 0.75, n2) * body * 0.5;
    float3 rose = mix(col.rgb, float3(1.0, 0.7, 0.75), 0.2), blue = float3(0.32, 0.5, 0.95);
    float3 gc = mix(blue, rose, smoothstep(0.2, 0.75, body + (n - 0.5) * 0.6));
    float bright = 0.65 + 0.7 * glow;
    float3 rgb = gc * gas * bright * (1.0 - dust) + float3(1.0, 0.88, 0.85) * core * 0.5 * bright;
    float a = clamp(gas * 0.75 + core * 0.4, 0.0, 1.0);
    // the young stars: a few in its heart, twinkling, bigger and brighter as a birth nears
    for (int i = 0; i < 7; i++) {
        float fi = float(i);
        float2 sp = (float2(hash21(float2(fi * 7.13 + 0.5, 1.7)), hash21(float2(fi * 3.71 + 2.2, 8.3))) - 0.5) * float2(0.95, 0.6);
        float tw = 0.65 + 0.35 * sin(t * (0.5 + hash21(float2(fi, 3.0))) + fi * 2.0);
        float sz = mix(0.014, 0.034, hash21(float2(fi, 4.0))) * (1.0 + glow * 0.6);
        float l = constellations_twinkle(p - sp, sz, i < 2 ? 0.35 : 0.1) * tw * (0.75 + 0.5 * glow);
        rgb += mix(float3(1.0), rose, 0.2) * l;
        a = max(a, min(1.0, l));
    }
    return float4(rgb, a) * fade;
}

// The rough outline of one half of the asteroid, around its own middle: a lumpy round rock. Returns its distance.
float constellations_rock(float2 q, float seed) {
    float ang = atan2(q.y, q.x);
    float r = 0.42 + 0.05 * sin(ang * 3.0 + seed) + 0.035 * sin(ang * 5.0 + seed * 2.3) + 0.02 * sin(ang * 9.0 + seed * 4.1);
    return (length(q) - r) * 0.9;
}

// The chest, up here: an asteroid adrift, turning slowly, pocked with craters. It is a geode: when it opens (extra.y:
// 0 shut … 1 open) it splits along a crack into two halves that drift apart, and the crystals inside shine gold, with
// stardust rising out of them. Shut, a thin line of light shows along the crack. p = c.
float4 draw_constellations_chest(float2 c, float t, float glow, float4 col, float4 extra) {
    float open = clamp(extra.y, 0.0, 1.0);
    float px = max(fwidth(c.x), fwidth(c.y)) + 1e-5;
    float2 p = c - float2(0.0, sin(t * 0.37) * 0.03);
    float spin = t * 0.05;
    // the crack runs across it, a little crooked; the halves part along its normal
    float2 nrm = normalize(float2(0.35, 1.0));
    float crackAt = dot(p, nrm) + sin(dot(p, float2(nrm.y, -nrm.x)) * 5.0) * 0.03;
    float side = crackAt > 0.0 ? 1.0 : -1.0;
    float2 q = p - nrm * side * open * 0.2;
    q = float2(q.x * cos(side * open * 0.25) - q.y * sin(side * open * 0.25), q.x * sin(side * open * 0.25) + q.y * cos(side * open * 0.25));
    float2 rq = float2(q.x * cos(spin) - q.y * sin(spin), q.x * sin(spin) + q.y * cos(spin));
    float rock = constellations_rock(rq, 1.7);
    // this half's distance to its own broken edge (it moved with the half): the gap between the halves is outside
    float2 qp = q + nrm * side * open * 0.2;
    float edge = side * (dot(qp, nrm) + sin(dot(qp, float2(nrm.y, -nrm.x)) * 5.0) * 0.03) - open * 0.04;
    float d = max(rock, -edge);
    float a = 1.0 - smoothstep(-px, px, d);
    // the stone: lit from above left, darker at the edge, craters
    float2 nq = rq / 0.45;
    float3 n = normalize(float3(nq, sqrt(max(0.05, 1.0 - dot(nq, nq)))));
    float lit = 0.35 + 0.75 * max(0.0, dot(n, normalize(float3(-0.5, 0.6, 0.6))));
    float3 stone = mix(float3(0.42, 0.38, 0.36), col.rgb * 0.5, 0.2) * (0.8 + 0.35 * vnoise(rq * 9.0));
    float2 cg = rq * 5.0;
    float2 cid = floor(cg);
    float cr = length(fract(cg) - 0.5 - (float2(hash21(cid), hash21(cid + 3.0)) - 0.5) * 0.3);
    float crater = step(0.55, hash21(cid + 7.0)) * (1.0 - smoothstep(0.18, 0.26, cr));
    float rimC = step(0.55, hash21(cid + 7.0)) * (1.0 - smoothstep(0.0, 0.06, abs(cr - 0.24)));
    stone *= (1.0 - crater * 0.35) * (1.0 + rimC * 0.25);
    float3 rgb = stone * lit;
    // the inside of each half along the crack: the geode's crystals, gold, glinting
    float3 gold = mix(float3(1.0, 0.8, 0.4), col.rgb, 0.3);
    float inner = (1.0 - smoothstep(0.0, 0.05 + open * 0.07, edge)) * a;
    float facets = 0.6 + 0.4 * step(0.5, hash21(floor(q * 26.0)));
    rgb = mix(rgb, gold * facets * (0.6 + 0.8 * open), inner * smoothstep(0.0, 0.15, open + 0.06));
    rgb *= a;
    float al = a;
    // shut: a thin seam of light; open: the light pours out of the gap, and stardust rises
    float seam = exp(-abs(crackAt) / max(px * 0.7, 0.006)) * step(rock, 0.0) * (0.25 + 0.5 * glow) * (1.0 - open);
    rgb += gold * seam;
    if (open > 0.02) {
        float pour = exp(-abs(crackAt) * 7.0) * exp(-dot(p, p) * 3.0) * open * (0.6 + 0.4 * glow) * (1.0 - al);
        float specks = 0.0;
        for (int i = 0; i < 7; i++) {
            float fi = float(i);
            float life = fract(t * 0.16 + hash21(float2(fi, 9.0)));
            float2 sp = nrm * (0.1 + life * 0.75) + float2(nrm.y, -nrm.x) * ((hash21(float2(fi, 5.0)) - 0.5) * 0.6 + sin(life * 6.0 + fi) * 0.05);
            specks += constellations_twinkle(p - sp, 0.016, 0.2) * sin(life * 3.14159);
        }
        float lw = (pour + specks * open) * (1.0 - smoothstep(0.75, 0.98, max(abs(c.x), abs(c.y))));
        rgb += float3(1.0, 0.85, 0.45) * lw;
        al = max(al, min(1.0, lw * 0.8));
    }
    return float4(rgb, al) * (1.0 - smoothstep(0.85, 1.0, max(abs(c.x), abs(c.y))));
}

// Stardust (the marine snow), a sparkle (the bubbles) and a little golden star (the food): small, twinkling.
float4 draw_constellations_dust(float2 c, float t, float glow, float4 col, float4 extra) {
    float tw = 0.55 + 0.45 * sin(t * 1.3 + extra.y * 20.0);
    float l = constellations_twinkle(c, 0.16, 0.0) * tw;
    l *= 1.0 - smoothstep(0.6, 1.0, length(c));
    return float4(col.rgb * l, min(1.0, l * 0.9));
}

float4 draw_constellations_sparkle(float2 c, float t, float glow, float4 col, float4 extra) {
    float l = constellations_twinkle(c, 0.12, 0.35) * (0.45 + 0.25 * sin(t * 3.0 + extra.y * 9.0));
    l *= 1.0 - smoothstep(0.7, 1.0, max(abs(c.x), abs(c.y)));
    return float4(mix(col.rgb, float3(1.0), 0.4) * l, min(1.0, l));
}

// Open sea: the blue with nothing under it, and the sargassum drifting at the surface.

// The water itself: shafts of light fanning down from where the sun stands over the surface, the bright window right
// above, slow patches of lighter and darker blue, and the blue going to black toward the bottom, so the floor is
// never seen. uv 0…1 over the window (y up); extra.x the aspect, extra.z the sand line.
float4 draw_ocean_background(float2 uv, float t, float light, float2 gaze, float3 water, float4 extra) {
    float aspect = extra.x;
    float night = extra.y;
    // down into nothing: darker and darker below the middle, all the way dark by the sand line
    float deepen = smoothstep(0.55, extra.z + 0.02, uv.y);
    float a = deepen * 0.92;
    float3 rgb = float3(0.004, 0.02, 0.045) * (0.5 + 0.5 * light) * a;
    // slow patches of blue: the water is never one flat color
    float patch = vnoise(float2(uv.x * aspect * 1.6 + t * 0.012, uv.y * 2.2 - t * 0.008)) - 0.5;
    rgb += water * patch * 0.22 * (1.0 - deepen);
    // the shafts: they fan out from a point above the surface and lean with it
    float2 sp = float2((uv.x - 0.6 + gaze.x * 0.004) * aspect, uv.y - 1.35);
    float ang = atan2(sp.x, -sp.y);
    float shafts = pow(max(0.0, sin(ang * 24.0 + t * 0.1 + sin(ang * 7.0 - t * 0.06) * 2.2)), 3.0)
                 * (0.35 + 0.9 * smoothstep(0.3, 0.75, vnoise(float2(ang * 8.0 + t * 0.03, 3.0))));
    shafts *= smoothstep(1.35, 0.4, length(sp)) * (1.0 - deepen);
    float3 shaftC = mix(float3(0.3, 0.68, 0.95), float3(0.45, 0.6, 1.0), night);
    rgb += shaftC * shafts * 0.2 * max(light, night * 0.7);
    // the window of sky right over the sun's place
    float win = exp(-pow((uv.x - 0.6) * aspect * 1.4, 2.0)) * smoothstep(0.7, 1.0, uv.y);
    rgb += float3(0.4, 0.75, 1.0) * win * 0.16 * light * (1.0 - night);
    return float4(rgb, a);
}

// one frond of sargassum: a thin wavy stem from `a0` to `a1` with small leaves and round air bladders along it
float ocean_frond(float2 p, float2 a0, float2 a1, float t, float seed, thread float &berry) {
    float2 ab = a1 - a0;
    float len = length(ab);
    float2 dir = ab / len, nrm = float2(-dir.y, dir.x);
    float2 q = p - a0;
    float u = clamp(dot(q, dir) / len, 0.0, 1.0);
    float v = dot(q, nrm) - sin(u * 9.0 + t * 0.9 + seed * 6.0) * 0.02 * u;
    float along = dot(q, dir);
    float stem = length(float2(along - clamp(along, 0.0, len), v)) - 0.008;
    // leaves: small blades off both sides, every so often
    float cell = floor(u * 9.0), fu = fract(u * 9.0) - 0.5;
    float side = fmod(cell, 2.0) < 0.5 ? 1.0 : -1.0;
    float2 lq = float2(fu * len / 9.0, v - side * 0.028);
    float leaf = (length(lq / float2(0.03, 0.012)) - 1.0) * 0.012;
    // bladders: little round floats on short stalks, on the other side
    float2 bq = float2((fract(u * 5.0 + seed) - 0.5) * len / 5.0, v + side * 0.03);
    berry = length(bq) - 0.016;
    float d = min(stem, leaf);
    if (u <= 0.02 || u >= 0.98) { berry = 1e3; d = stem; }
    return d;
}

// A raft of sargassum at the surface: golden-brown weed in a loose tangle, most of it just under the water line,
// fronds hanging and waving below, round bladders keeping it afloat. p = c * (1.6, 0.6); the water line at p.y = 0.12.
float4 ocean_sargassum(float2 c, float t, float4 col, float seed, thread float &d, thread float2 &pOut) {
    float2 p = c * float2(1.6, 0.6);
    pOut = p;
    float wl = 0.12;
    d = 1e3;
    float berryD = 1e3;
    // the mat along the line: lumps of weed bobbing a little
    for (int i = 0; i < 7; i++) {
        float fi = float(i);
        float h = hash21(float2(fi, seed * 13.0));
        float2 ctr = float2(-1.15 + fi * 0.38 + (h - 0.5) * 0.14, wl - 0.02 + sin(t * 0.8 + fi * 1.3 + seed * 5.0) * 0.012);
        d = smin_k(d, (length((p - ctr) / float2(0.24 + 0.1 * h, 0.06 + 0.05 * h)) - 1.0) * 0.06, 0.04);
    }
    // fronds hanging under it and a few sticking up into the air
    for (int i = 0; i < 9; i++) {
        float fi = float(i);
        float h = hash21(float2(fi + 20.0, seed * 7.0));
        float x0 = -1.2 + fi * 0.3 + (h - 0.5) * 0.1;
        bool up = fmod(fi, 3.0) > 1.5;
        float2 a0 = float2(x0, wl - 0.01);
        float2 a1 = up ? float2(x0 + (h - 0.5) * 0.2, wl + 0.1 + 0.06 * h)
                       : float2(x0 + (h - 0.5) * 0.3 + sin(t * 0.5 + fi) * 0.04, wl - 0.25 - 0.22 * h);
        float b;
        float f = ocean_frond(p, a0, a1, t, h + seed, b);
        d = min(d, f);
        berryD = min(berryD, b);
    }
    float aa = fwidth(min(d, berryD)) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, min(d, berryD));
    if (a <= 0.001) return float4(0.0);
    float3 gold = mix(float3(0.62, 0.46, 0.14), col.rgb, 0.35);
    float3 c3 = gold * (0.7 + 0.5 * vnoise(p * 14.0 + seed * 9.0));
    c3 *= 0.75 + 0.35 * smoothstep(-0.03, 0.0, -d) ;
    // bladders: paler, round, with a little shine
    float bl = 1.0 - smoothstep(-0.004, 0.004, berryD);
    c3 = mix(c3, gold * 1.35 + 0.08, bl);
    c3 += float3(1.0, 0.95, 0.8) * bl * smoothstep(0.012, 0.0, berryD + 0.012) * 0.0;
    // above the line the sun dries and lights it; below, the water takes it
    c3 *= mix(0.7, 1.15, smoothstep(wl - 0.03, wl + 0.03, p.y));
    c3 = mix(c3, col.rgb * 0.2 + float3(0.02, 0.1, 0.16), smoothstep(wl - 0.12, wl - 0.5, p.y) * 0.5);
    return float4(c3 * a, a);
}

float4 draw_ocean_sargassum(float2 c, float t, float glow, float4 col, float4 extra) {
    float d;
    float2 p;
    return ocean_sargassum(c, t, col, extra.y, d, p);
}

// The clutch, here where there's no floor: flying-fish eggs strung in the sargassum, a bunch of clear amber beads
// hanging under the raft, each with a dark eye spot. Glows a little when sessions are about to hatch (glow).
float4 draw_ocean_eggs(float2 c, float t, float glow, float4 col, float4 extra) {
    float d;
    float2 p;
    float4 weed = ocean_sargassum(c, t, float4(0.62, 0.46, 0.14, 1.0), 0.37, d, p);
    float3 amber = mix(float3(1.0, 0.62, 0.25), col.rgb, 0.3);
    float4 o = weed;
    float sway = sin(t * 0.7) * 0.02;
    for (int i = 0; i < 9; i++) {
        float fi = float(i);
        float row = floor(fi / 3.0), cidx = fmod(fi, 3.0);
        float2 ctr = float2(-0.1 + (cidx - 1.0) * 0.1 + fmod(row, 2.0) * 0.05 + sway * (row + 1.0) * 0.5, 0.02 - row * 0.085);
        float r = length(p - ctr) / 0.052;
        if (r > 1.25) continue;
        float ea = 1.0 - smoothstep(0.9, 1.0, r);
        float3 e = amber * (0.7 + 0.5 * (1.0 - r)) + float3(1.0) * smoothstep(0.35, 0.0, length(p - ctr - float2(-0.016, 0.018)) / 0.052) * 0.6;
        e = mix(e, float3(0.12, 0.06, 0.03), 1.0 - smoothstep(0.2, 0.32, length(p - ctr - float2(0.01, -0.008)) / 0.052));
        e += amber * glow * 0.6;
        float al = ea * 0.9;
        o = float4(o.rgb * (1.0 - al) + e * al, o.a * (1.0 - al) + al);
        float halo = glow * exp(-max(r - 1.0, 0.0) * 4.0) * (1.0 - ea) * 0.4;
        o += float4(amber * halo, halo * 0.5);
    }
    return o;
}

// The chest, here where there's no floor: an old sea chest adrift, riding low and a little crooked, half of it under
// the water line, weed and barnacles on the wet half, a frayed rope trailing. Its lid swings open on its hinge
// (extra.y: 0 closed … 1 open) with a glow from inside. p = c; the water line at p.y = 0.12.
float4 draw_ocean_chest(float2 c, float t, float glow, float4 col, float4 extra) {
    float open = clamp(extra.y, 0.0, 1.0);
    float wl = 0.12;
    float lum = max(col.r, max(col.g, col.b));
    // it rocks with the swell
    float tilt = 0.1 + sin(t * 0.7) * 0.06;
    float2 p = c - float2(0.0, 0.2 + sin(t * 0.9) * 0.015);                  // riding with half of it out of the water
    p = float2(p.x * cos(tilt) - p.y * sin(tilt), p.x * sin(tilt) + p.y * cos(tilt));
    float box = sd_box(p - float2(0.0, -0.08), float2(0.5, 0.24), 0.04);
    float ang = -open * 1.1;
    float2 hinge = float2(-0.48, 0.16);
    float2 lp = p - hinge;
    lp = float2(lp.x * cos(ang) - lp.y * sin(ang), lp.x * sin(ang) + lp.y * cos(ang)) + hinge;
    float lid = max((length((lp - float2(0.0, 0.16)) / float2(0.52, 0.24)) - 1.0) * 0.24, -(lp.y - 0.16));
    // the rope: tied to a ring on the side, hanging down and swaying
    float rx = 0.5 + sin(c.y * 6.0 + t * 0.8) * 0.04 * smoothstep(0.0, -0.8, c.y);
    float rope = max(abs(c.x - rx) - 0.014, max(c.y - 0.0, -0.85 - c.y));
    float d = min(min(box, lid), rope);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float3 wood = mix(float3(0.5, 0.32, 0.17), col.rgb, 0.25) * lum, iron = float3(0.75, 0.62, 0.3) * lum;
    float2 bp = lid < box ? lp : p;
    // planks, a rounded lid, the bands and the lock
    float3 c3 = wood * (0.8 + 0.25 * vnoise(float2(bp.x * 4.0, bp.y * 40.0)));
    c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.012, abs(fract(bp.y * 6.0) - 0.5) - 0.46)) * 0.25;
    c3 *= lid < box ? 0.85 + 0.35 * smoothstep(0.16, 0.4, lp.y) : 0.8 + 0.3 * smoothstep(-0.3, 0.16, p.y);
    float bands = min(abs(abs(bp.x) - 0.3) - 0.04, lid < box ? 1.0 : abs(p.y - 0.12) - 0.025);
    c3 = mix(c3, iron * (0.75 + 0.35 * vnoise(bp * 30.0)), 1.0 - smoothstep(0.0, 0.012, bands));
    c3 = mix(c3, iron * 1.1, (1.0 - smoothstep(0.0, 0.012, sd_box(p - float2(0.0, 0.08), float2(0.05, 0.06), 0.02))) * step(box, lid) * (1.0 - open));
    if (rope < min(box, lid)) c3 = float3(0.62, 0.52, 0.34) * lum * (0.8 + 0.2 * sin(c.y * 90.0));
    // what's under the line is wet and takes the water: darker, bluer, with weed and barnacles
    float under = smoothstep(wl + 0.02, wl - 0.04, c.y);
    float grow = under * smoothstep(0.4, 0.7, vnoise(c * 12.0 + 3.0));
    c3 = mix(c3, float3(0.16, 0.36, 0.2) * lum, grow * 0.6);
    float2 bg = c * 16.0;
    c3 = mix(c3, float3(0.8, 0.8, 0.74) * lum, under * (1.0 - smoothstep(0.16, 0.28, length(fract(bg) - 0.5))) * step(0.78, hash21(floor(bg))) * step(box, 0.0));
    c3 = mix(c3, c3 * float3(0.5, 0.72, 0.9), under * 0.45);
    // the wet line where the water laps at it
    c3 += float3(0.8, 0.95, 1.0) * (1.0 - smoothstep(0.0, 0.015, abs(c.y - wl - sin(c.x * 14.0 + t * 2.0) * 0.008))) * 0.35 * step(min(box, lid), 0.0);
    float4 o = float4(c3 * a, a);
    if (open > 0.05) {
        // gold inside, and its light spilling up and out
        float coins = (length((p - float2(0.02, 0.17)) / float2(0.42, 0.1 * open)) - 1.0) * 0.1;
        float ca = (1.0 - smoothstep(0.0, 0.012, coins)) * step(0.0, lid);
        float2 cg = p * float2(10.0, 18.0);
        float3 coinC = float3(1.0, 0.8, 0.25) * lum * (0.75 + 0.4 * step(0.5, hash21(floor(cg)))) + float3(1.0) * step(0.93, hash21(floor(cg) + 2.0)) * 0.4;
        o = float4(o.rgb * (1.0 - ca) + coinC * ca, max(o.a, ca));
        float halo = open * exp(-pow(length((c - float2(0.0, 0.35)) / float2(0.7, 0.5)), 2.0) * 2.5) * (0.3 + 0.5 * glow) * (1.0 - o.a);
        o += float4(float3(1.0, 0.85, 0.4) * halo, halo * 0.5);
    }
    return o;
}

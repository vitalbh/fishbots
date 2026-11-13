// Kelp forest sardines: the Pacific sardine (a fish kind, the theme's high school) and the bait ball that drifts
// through the forest now and then (a creature).

// Pacific sardine: slim, a blue-green back, a silver flank with a row of small dark spots, a bright gill plate, a
// deeply forked tail. col tints the back and the silver; extra.w > 1.5: asleep.
float4 draw_kelp_sardine(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.25, 0.8);
    p.y -= sin(phase - p.x * 2.8) * 0.05 * smoothstep(0.3, -1.0, p.x);
    // a spindle: fullest ahead of the middle, a narrow tail stock, a blunt little head
    float thin = mix(0.3, 1.0, smoothstep(-0.92, -0.05, p.x)) * mix(1.0, 0.8, smoothstep(0.55, 0.95, p.x));
    float ry = 0.215 * thin;
    float2 bc = float2(0.1, 0.0);
    float body = (length((p - bc) / float2(0.86, ry)) - 1.0) * ry;
    // the tail: two swept lobes with a deep notch
    float2 tq = p - float2(-0.68, sin(phase - 1.2) * 0.05);
    float tail = max(sd_tri(tq, float2(0.1, 0.0), float2(-0.35, 0.31), float2(-0.35, -0.31)),
                     -sd_tri(tq, float2(-0.13, 0.0), float2(-0.46, 0.2), float2(-0.46, -0.2))) - 0.014;
    // one small dorsal at the middle of the back, the pelvic under it, a low anal fin near the tail
    float dors = sd_tri(p, float2(0.12, 0.17), float2(-0.2, 0.15), float2(-0.1, 0.36)) - 0.012;
    float pelv = sd_tri(p, float2(0.0, -0.17), float2(-0.16, -0.16), float2(-0.15, -0.29)) - 0.008;
    float anal = sd_tri(p, float2(-0.3, -0.12), float2(-0.56, -0.07), float2(-0.5, -0.2)) - 0.008;
    float fins = min(min(tail, pelv), min(dors, anal));
    float d = min(body, fins);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float3 back = mix(float3(0.04, 0.4, 0.46), col.rgb * 0.7, 0.3) * 0.85;
    float3 silver = mix(float3(0.93, 0.96, 0.98), col.rgb, 0.16);
    float yn = p.y / max(ry, 0.04);
    float3 c3 = mix(silver, back, smoothstep(0.08, 0.42, yn));
    // an iridescent line where the back meets the flank, then the row of spots under it
    c3 = mix(c3, mix(float3(0.55, 0.95, 0.8), col.rgb, 0.3), (1.0 - smoothstep(0.03, 0.16, abs(yn - 0.22))) * 0.45);
    float sx = p.x * 8.0 + 0.2;
    float spot = 1.0 - smoothstep(0.024, 0.037, length(float2((fract(sx) - 0.5) / 8.0, p.y - ry * 0.02)));
    spot *= step(-0.5, p.x) * step(p.x, 0.42) * (0.75 + 0.25 * hash21(float2(floor(sx), 3.0)));
    c3 = mix(c3, float3(0.07, 0.12, 0.2), spot * 0.8);
    // scales glinting on the flank
    float2 sc = p * float2(20.0, 24.0);
    c3 *= 0.95 + 0.07 * smoothstep(0.25, 0.5, length(fract(sc + float2(floor(sc.y) * 0.5, 0.0)) - 0.5));
    c3 = fish_round(c3 * 1.1, float2((p.x - bc.x) / 0.86, yn), body);
    // the gill plate: a bright cheek with a dark curve behind it
    float gr = length((p - float2(0.6, -0.01)) * float2(1.0, 0.75));
    c3 = mix(c3, silver * 1.08, (1.0 - smoothstep(0.08, 0.14, gr)) * step(body, 0.0) * 0.45);
    c3 *= 1.0 - (1.0 - smoothstep(0.004, 0.018, abs(gr - 0.14))) * step(p.x, 0.62) * step(body, 0.0) * 0.3;
    c3 = mix(c3, c3 * 0.4, (1.0 - smoothstep(0.0, 0.012, abs(p.y + 0.035 + (p.x - 0.84) * 0.35) - 0.005)) * step(0.8, p.x) * step(body, 0.0));
    float al = a;
    if (body > 0.0) {                                               // fins: clear, rayed, darker toward the tips
        c3 = mix(back * 1.5, silver, 0.4) * (0.88 + 0.12 * cos(atan2(p.y, p.x + 0.55) * 50.0));
        al *= 0.68;
    }
    c3 = fish_eye(c3, p, float2(0.7, 0.04), 0.06, silver, step(1.5, extra.w));
    c3 += col.rgb * glow * 0.45;
    float fade = 1.0 - smoothstep(0.6, 1.0, max(abs(c.x), abs(c.y)));
    float halo = exp(-max(d, 0.0) * 12.0) * glow * (1.0 - a) * fade;
    return float4((c3 * al + col.rgb * halo * 0.9) * col.a, min(al + halo * 0.55, 1.0) * col.a);
}

// One sardine of the ball, in its own space: q.x along its course (head at +x), q.y across, the fish one unit long.
// A tapered sliver and a notched tail that beats.
float kelp_ball_fish(float2 q, float wag) {
    q.y -= wag * smoothstep(0.15, -0.5, q.x);
    float thin = mix(0.4, 1.0, smoothstep(-0.36, 0.02, q.x));
    float ry = 0.135 * thin;
    float body = (length((q - float2(0.1, 0.0)) / float2(0.4, ry)) - 1.0) * ry;
    float2 t = q - float2(-0.26, 0.0);
    float tail = max(sd_tri(t, float2(0.06, 0.0), float2(-0.24, 0.2), float2(-0.24, -0.2)),
                     -sd_tri(t, float2(-0.1, 0.0), float2(-0.3, 0.12), float2(-0.3, -0.12)));
    return min(body, tail);
}

// Sardine bait ball: a few dozen sardines circling a common axis, as bait balls do. The ball is a globe seen a
// little from above: each orbit is a line of latitude (an ellipse), on an outer shell and an inner one, with its fish
// spaced along it. The arc of an orbit nearer to us swims forward, bright and a bit bigger; the far arc swims back
// the other way, dimmer and bluer. The ball breathes and wobbles, and flanks flash as fish turn.
// Each pixel only looks at the few fish of each orbit next to it.
float4 draw_kelp_sardine_ball(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.2, 1.0);
    float seed = extra.y;
    float px = fwidth(p.x) * 0.75 + 1e-4;
    p -= float2(sin(phase * 0.31 + seed * 5.0), cos(phase * 0.23 + seed * 3.0)) * 0.03;        // the wobble
    float breathe = 1.0 + 0.05 * sin(phase * 0.45 + seed * 6.0);
    float2 ball = float2(0.94, 0.8 / breathe) * breathe * float2(1.0 + 0.03 * sin(phase * 0.2 + seed), 1.0);
    float rr = length(p / ball);
    if (rr > 1.2) return float4(0.0);
    float t = phase * 0.42 + seed * 9.0;
    float lean = 0.1 * sin(phase * 0.17 + seed * 4.0);                                         // the axis sways
    float cr = cos(lean), sr = sin(lean);
    float2 e = float2(p.x * cr + p.y * sr, -p.x * sr + p.y * cr);
    float open = 0.34 + 0.05 * sin(phase * 0.13 + seed * 2.0);                                 // how much from above we see it
    float rise = sqrt(1.0 - open * open);
    const float ringLat[8] = { -0.8, -0.46, -0.1, 0.28, 0.66, -0.5, 0.05, 0.6 };              // sine of the latitude
    const float ringShell[8] = { 0.9, 0.9, 0.9, 0.9, 0.9, 0.5, 0.5, 0.5 };
    const float ringN[8] = { 9.0, 13.0, 15.0, 14.0, 10.0, 6.0, 8.0, 6.0 };
    const float ringW[8] = { 1.0, 0.9, 0.82, 0.88, 1.05, 1.4, 1.3, 1.45 };
    float3 silver = col.rgb * 1.12, back = col.rgb * float3(0.24, 0.42, 0.5), haze = col.rgb * float3(0.36, 0.52, 0.74);
    float lum = max(col.r, max(col.g, col.b));
    float4 acc = float4(0.0);
    float zacc = -2.0;
    for (int i = 0; i < 8; i++) {
        float fi = float(i);
        float sl = ringLat[i] + 0.04 * sin(phase * 0.3 + fi * 1.7);
        float cl = sqrt(1.0 - sl * sl);
        float2 mid = float2(0.0, ringShell[i] * sl * rise * ball.y);
        float2 rad = ringShell[i] * cl * float2(ball.x, ball.y * open);
        float2 q = (e - mid) / rad;
        float rq = length(q);
        if (abs(rq - 1.0) * rad.y > 0.3) continue;
        float n = ringN[i];
        float off = t * ringW[i] * n / 6.2832 + fi * 0.37;
        float s = atan2(q.y, q.x) * n / 6.2832 - off;
        float j0 = floor(s);
        for (int dj = -2; dj <= 2; dj++) {
            float j = j0 + float(dj);
            float jm = j - n * floor(j / n);
            float h = hash21(float2(jm + 1.0, fi * 7.3 + 2.0));
            float h2 = fract(h * 57.31), h3 = fract(h * 131.7);
            float th = (j + 0.5 + (h - 0.5) * 0.6 + off) * 6.2832 / n;
            float cs = cos(th), sn = sin(th);
            float rj = 1.0 + (h2 - 0.5) * 0.22 + 0.04 * sin(phase * 0.8 + h * 30.0);
            float2 at = mid + rad * rj * float2(cs, sn) + float2(0.0, (h3 - 0.5) * 0.17);
            float2 tg = float2(-rad.x * sn, rad.y * cs);                                       // the way it swims
            float tl = length(tg);
            tg /= max(tl, 1e-4);
            float yaw = (h3 - 0.5) * 0.5 + 0.12 * sin(phase * 0.7 + h * 50.0);
            tg = float2(tg.x * cos(yaw) - tg.y * sin(yaw), tg.x * sin(yaw) + tg.y * cos(yaw));
            float z = -sn;                                                                     // toward us: 1, away: -1
            float near = z * 0.5 + 0.5;
            float len = 0.22 * mix(0.72, 1.12, near) * mix(0.6, 1.0, smoothstep(0.2, 0.8, tl / rad.x));
            float2 w = e - at;
            float2 l = float2(dot(w, tg), -w.x * tg.y + w.y * tg.x) / len;
            if (abs(l.x) > 0.62 || abs(l.y) > 0.3) continue;
            if (tg.x < 0.0) l.y = -l.y;                                                        // its back is the side toward the surface
            float d = kelp_ball_fish(l, sin(phase * 3.0 + h * 20.0) * 0.07) * len;
            float a = 1.0 - smoothstep(-px, px, d);
            if (a < 0.003) continue;
            float3 c3 = mix(silver, back, smoothstep(-0.01, 0.07, l.y));
            c3 = mix(c3, silver * 1.1, (1.0 - smoothstep(0.0, 0.05, abs(l.y + 0.02))) * 0.5);  // the line of light along the flank
            c3 = mix(c3, float3(0.03, 0.05, 0.08) * lum, 1.0 - smoothstep(0.02, 0.045, length(l - float2(0.36, 0.02))));
            float flash = smoothstep(0.86, 1.0, sin(phase * 0.9 + h * 40.0 + th * 2.0));       // a flank turned to the light
            c3 = mix(c3, float3(1.0, 1.0, 0.97) * lum * 1.35, flash * (0.35 + 0.5 * near));
            float depth = mix(0.3, 1.0, near) * mix(0.8, 1.0, ringShell[i] * 2.0 - 0.8);
            c3 = mix(haze * (0.7 + 0.2 * h2), c3, depth);
            a *= mix(0.62, 1.0, near);
            float4 smp = float4(c3 * a, a);
            if (z > zacc) { acc = smp + acc * (1.0 - a); zacc = z; }
            else acc = acc + smp * (1.0 - acc.a);
        }
    }
    // the fish too deep in the ball to tell apart: a faint blue haze in the middle
    float core = (1.0 - smoothstep(0.1, 0.95, rr)) * 0.34;
    acc = acc + float4(haze * 0.6 * core, core) * (1.0 - acc.a);
    return acc;
}

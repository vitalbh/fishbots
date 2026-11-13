// Constellations: the plugins' presences, up among the stars. What the aquarium shows as a shark, a bottle, a flag…
// becomes something of the sky that means the same: a black hole that prowls, a balloon carrying a message, a flag
// planted on a little moon. Drawn like the rest of the pack: fine lines, small bright stars, soft glows, little color.
//
// Every one shows its state (extra.w: 0 idle, 1 busy, 2 waiting, 3 ok, 4 alert, 5 error, 6 done, 7 born) by its
// light and its motion; the app has already tinted `col` for the state (dimmer when idle, amber in alert, faded and
// reddish in error) and raises `glow` while it needs you. A meter's value is extra.y (0…1).

// The light of a small star: a sharp core, a soft halo, four thin spikes.
float constellations_pr_star(float2 q, float r0, float spikes) {
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

// The same, with the pixel size given (for stars placed per cell, where fwidth of the offset jumps at the seams).
float constellations_pr_star_px(float2 q, float r0, float px) {
    float r = length(q);
    float rc = max(r0, px);
    return 1.0 - smoothstep(rc * 0.4, rc, r) + exp(-r * r / (rc * rc * 6.0)) * 0.45;
}

// The state's lamp, as the app's pilot lights show it.
float3 constellations_pr_lamp(int st) {
    if (st == 0) return float3(0.5, 0.52, 0.55);
    if (st == 1) return float3(0.45, 0.75, 1.0);
    if (st == 2) return float3(1.0, 0.85, 0.4);
    if (st == 4) return float3(1.0, 0.72, 0.25);
    if (st == 5) return float3(1.0, 0.38, 0.32);
    if (st == 6) return float3(0.6, 1.0, 0.7);
    return float3(0.35, 0.85, 0.5);
}

// Whether the state calls for its own color (waiting, alert, error, done): 0 or 1.
float constellations_pr_calls(int st) { return (st == 2 || st == 4 || st == 5 || st == 6) ? 1.0 : 0.0; }

// A fine line: coverage of a stroke of half-width w at distance d.
float constellations_pr_line(float d, float w, float px) { return 1.0 - smoothstep(w - px * 0.5, w + px * 0.5, d); }

float2 constellations_pr_rot(float2 p, float a) { float s = sin(a), k = cos(a); return float2(p.x * k - p.y * s, p.x * s + p.y * k); }

float constellations_pr_fade(float2 c) { return 1.0 - smoothstep(0.75, 1.0, max(abs(c.x), abs(c.y))); }

// A soft halo in the color around a shape (d: the shape's distance), added under what's drawn (premultiplied).
float4 constellations_pr_halo(float4 o, float d, float glow, float3 color, float2 c, float k) {
    float halo = glow * exp(-max(d, 0.0) * k) * constellations_pr_fade(c);
    o.rgb += color * halo * (1.0 - o.a);
    o.a += halo * (1.0 - o.a) * 0.55;
    return o;
}

// A figure of stars joined by fine lines that stop short of them, as on a star chart, over a faint haze of its color
// near the lines. pts/sz: the stars (size 0…1); segs: pairs of indices, ending at -1. eye: the brightest one.
float4 constellations_pr_figure(float2 p, thread float2* pts, thread float* sz, int n, constant int2* segs, int eye,
                                float phase, float glow, float3 col, float dim) {
    float px = max(fwidth(p.x), fwidth(p.y)) + 1e-5;
    float3 starC = mix(col, float3(1.0, 0.98, 0.94), 0.55);
    float3 lineC = mix(col, float3(0.85, 0.9, 1.0), 0.25);
    float w = max(0.012, px * 0.55);
    float la = 0.0, near = 10.0;
    for (int i = 0; i < 40; i++) {
        int2 s = segs[i];
        if (s.x < 0) break;
        float2 a0 = pts[s.x], ab = pts[s.y] - a0;
        float len = length(ab);
        float h = clamp(dot(p - a0, ab) / (len * len), 0.0, 1.0);
        float d = length(p - a0 - ab * h);
        near = min(near, d);
        if (d > w + px * 2.0) continue;
        float m = constellations_pr_line(d, w, px);
        float gap = 0.06 + px;
        m *= smoothstep(gap, gap + 0.035, min(h, 1.0 - h) * len);
        la = max(la, m);
    }
    float haze = exp(-near * near / 0.012) * 0.1 * dim * (1.0 + glow);
    la *= 0.5 * dim * (1.0 + glow * 0.6);
    float3 rgb = col * haze;
    float a = haze;
    rgb = rgb * (1.0 - la) + lineC * la;
    a = a + la * (1.0 - a);
    float3 sl = float3(0.0);
    float sa = 0.0;
    for (int i = 0; i < n; i++) {
        float2 q = p - pts[i];
        if (dot(q, q) > 0.2) continue;
        float hs = hash21(float2(float(i), 7.3));
        float tw = 0.7 + 0.3 * sin(phase * (0.6 + 0.8 * hs) + hs * 40.0);
        float rc = max(mix(0.022, 0.056, sz[i]), px * (0.7 + 0.7 * sz[i])) * (i == eye ? 1.25 : 1.0);
        float lum = constellations_pr_star_px(q, rc, px * 0.8) * tw * dim * (1.0 + glow * 0.6);
        if (sz[i] > 0.6) lum += constellations_pr_star(q, rc * 0.6, (sz[i] - 0.5) * 0.8) * 0.5 * tw * dim;
        if (i == eye) lum *= 1.25;
        sl += mix(col * 1.1, starC, 0.6) * lum;
        sa = max(sa, min(1.0, lum));
    }
    rgb += sl;
    a = max(a, sa);
    rgb += col * glow * 0.45 * a;
    float halo = glow * exp(-near * 5.0) * 0.5;
    rgb += col * halo * (1.0 - a);
    a = a + halo * (1.0 - a) * 0.55;
    return float4(rgb, min(a, 1.0));
}

// ---------------------------------------------------------------------------------------------------------------
// The shark: a black hole that prowls across the sky. A round shadow darker than the night around it, a thin bright
// photon ring, and a disk of hot gas seen nearly edge-on: its near side crosses in front of the shadow, its far side
// shows bent up over the top. The gas turns (faster while busy) and takes the state's color when it calls; while busy
// it throws two thin jets from its poles; in error the disk flickers and the shadow swells. p = c * (1.4, 0.8).
float4 draw_constellations_blackhole(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.4, 0.8);
    float px = max(fwidth(p.x), fwidth(p.y)) + 1e-5;
    int st = int(extra.w + 0.5);
    float busy = st == 1 ? 1.0 : 0.0, err = st == 5 ? 1.0 : 0.0;
    float dim = st == 0 ? 0.55 : 1.0;
    float Rs = 0.22 * (1.0 + 0.1 * err);
    float r = length(p);
    float3 gas = mix(col.rgb, constellations_pr_lamp(st), 0.55 * constellations_pr_calls(st));
    float3 hot = mix(gas, float3(1.0, 0.97, 0.9), 0.6);
    float flick = err > 0.5 ? 0.55 + 0.45 * vnoise(float2(phase * 5.0, 1.3)) : 1.0;
    // the disk, tilted a little and seen from just above its plane
    float2 dq = constellations_pr_rot(p, 0.12);
    float2 e = float2(dq.x, dq.y / 0.27);
    float er = length(e);
    float ang = atan2(e.y, e.x);
    float spin = phase * (st == 0 ? 0.35 : 0.9);
    float band = smoothstep(0.36, 0.44, er) * (1.0 - smoothstep(0.7, 1.08, er));
    float streak = 0.72 + 0.28 * sin(ang * 3.0 + er * 10.0 - spin * 2.0) * (0.6 + 0.4 * vnoise(float2(ang * 2.0 - spin, er * 6.0)));
    float beam = 0.75 + 0.35 * (-e.x / max(er, 0.01));                     // the side turning toward us is brighter
    float heat = 1.0 - smoothstep(0.4, 1.0, er);
    float diskL = band * streak * beam * (0.35 + 0.9 * heat) * dim * flick;
    float near = dq.y < 0.0 ? 1.0 : 0.0;                                     // the near half passes in front
    diskL *= 1.0 + 1.6 * near * (1.0 - smoothstep(Rs * 0.9, Rs * 1.5, abs(dq.x))) * (1.0 - smoothstep(0.5, 0.75, er));   // brightest where it crosses the shadow
    // the far half bent up over the shadow (and a fainter thinner image under it)
    float lr = r / Rs;
    float upper = smoothstep(-0.05, 0.25, p.y / Rs);
    float arc = exp(-pow((lr - 1.35) / 0.22, 2.0)) * upper * (0.7 + 0.3 * sin(atan2(p.y, p.x) * 4.0 - spin * 1.5));
    arc += exp(-pow((lr - 1.18) / 0.08, 2.0)) * (1.0 - upper) * 0.35;
    arc *= dim * flick * 0.85;
    float ring = exp(-abs(r - Rs * 1.04) / max(px * 0.7, 0.006)) * dim * flick;   // the photon ring
    float shadow = 1.0 - smoothstep(Rs - px, Rs + px, r);
    // behind the hole: the far half of the disk is hidden, the near half covers it
    float behind = (1.0 - near) * shadow;
    float3 rgb = float3(0.0);
    float a = 0.0;
    // a dark well around it, so it reads as a hole in the stars
    float well = exp(-pow(max(r - Rs, 0.0) / (Rs * 0.9), 2.0)) * 0.55;
    a = max(a, well);
    a = max(a, shadow * 0.97);
    rgb += mix(gas, hot, 0.5) * arc;
    rgb += hot * ring * 0.9;
    rgb += mix(gas * 0.8, hot, heat) * diskL * (1.0 - behind);
    a = max(a, min(1.0, arc * 0.9 + ring * 0.8 + diskL * (1.0 - behind) * 0.85));
    // busy: two thin jets out of the poles
    if (busy > 0.5) {
        float2 jq = constellations_pr_rot(p, 0.12);
        float along = abs(jq.y) - Rs * 1.1;
        float jw = max(0.01 + along * 0.05, px * 0.6);
        float jet = exp(-abs(jq.x) / jw) * smoothstep(0.0, 0.05, along) * (1.0 - smoothstep(0.15, 0.72, along))
                  * (0.7 + 0.3 * sin(along * 30.0 - phase * 6.0));
        rgb += float3(0.6, 0.8, 1.0) * jet * 0.8;
        a = max(a, min(1.0, jet * 0.7));
    }
    rgb += gas * glow * 0.3 * a;
    float4 o = float4(rgb, clamp(a, 0.0, 1.0));
    o = constellations_pr_halo(o, r - Rs * 1.8, glow, gas, c, 5.0);
    return o * constellations_pr_fade(c) * col.a;
}

// ---------------------------------------------------------------------------------------------------------------
// The submarine: a small shuttle on a long run. A pale hull with a stripe in its color, a swept wing, a tail fin, a
// row of lit windows and an engine at the back. The engine says how it goes: off and dark while idle, a short steady
// flame when ok, a long flickering one while busy, a sputter of red sparks in error. Its windows and the beacon on the
// fin blink in the state's color when it calls. Faces +x. p = c * (1.6, 0.7).
float4 draw_constellations_shuttle(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.6, 0.7);
    float px = max(fwidth(p.x), fwidth(p.y)) + 1e-5;
    int st = int(extra.w + 0.5);
    float3 lamp = constellations_pr_lamp(st);
    float calls = constellations_pr_calls(st);
    float lumK = max(col.r, max(col.g, col.b));
    // in error it lists, nose down
    if (st == 5) p = constellations_pr_rot(p, 0.12 + sin(phase * 0.9) * 0.03);
    float body = (length((p - float2(0.06, 0.0)) / float2(0.82, 0.17)) - 1.0) * 0.17;
    body = max(body, -(p.x + 0.66));
    float wing = sd_tri(p, float2(0.28, -0.06), float2(-0.62, -0.06), float2(-0.56, -0.34)) - 0.01;
    float fin = sd_tri(p, float2(-0.3, 0.1), float2(-0.66, 0.1), float2(-0.62, 0.42)) - 0.01;
    float bell = sd_box(p - float2(-0.7, 0.0), float2(0.05, 0.09), 0.01);
    float d = min(min(body, wing), min(fin, bell));
    float a = 1.0 - smoothstep(-px, px, d);
    float3 hull = mix(float3(0.86, 0.88, 0.93), col.rgb, 0.12) * (0.75 + 0.25 * lumK);
    float top = smoothstep(-0.17, 0.17, p.y);
    float3 c3 = hull * (0.5 + 0.55 * top);
    if (wing < body && wing < fin) c3 = hull * 0.55;
    if (fin < body && fin < wing) c3 = hull * 0.7;
    if (bell < min(body, min(wing, fin))) c3 = float3(0.35, 0.36, 0.4);
    // the stripe along its side, in its color
    float stripe = (1.0 - smoothstep(0.012, 0.012 + px, abs(p.y + 0.035))) * step(body, 0.0) * step(p.x, 0.62);
    c3 = mix(c3, col.rgb * 1.1, stripe * 0.85);
    // a thin bright rim on top, a darker line under
    float rim = exp(-abs(d) / max(px * 0.8, 0.004)) * smoothstep(0.0, 0.15, p.y);
    c3 += float3(0.9, 0.93, 1.0) * rim * 0.35;
    // the windows
    float win = 0.0;
    for (int i = 0; i < 4; i++) {
        float2 wq = p - float2(0.58 - float(i) * 0.15, 0.06);
        win += 1.0 - smoothstep(0.022, 0.022 + px, length(wq));
    }
    float blink = calls > 0.5 ? 0.55 + 0.45 * sin(phase * 4.0) : 1.0;
    float3 winC = mix(float3(1.0, 0.85, 0.55), lamp, calls) * (st == 0 ? 0.15 : 0.9) * blink;
    c3 = mix(c3, winC, win);
    float3 rgb = c3 * a;
    float al = a;
    // the engine
    float L = st == 0 ? 0.0 : st == 1 ? 0.75 : st == 5 ? 0.22 : 0.24;
    float sput = st == 5 ? step(0.45, vnoise(float2(phase * 7.0, 2.0))) : 1.0;
    float fl = st == 1 ? 0.8 + 0.2 * sin(phase * 23.0) * sin(phase * 7.0) : 1.0;
    float back = -(p.x + 0.75);
    if (L > 0.0 && back > -0.02) {
        float u = clamp(back / (L * fl), 0.0, 1.0);
        float wdt = max((st == 1 ? 0.065 : 0.05) * (1.0 - u * 0.6), px * 0.6);
        float flame = exp(-abs(p.y) / wdt) * (1.0 - u) * smoothstep(-0.02, 0.03, back) * sput;
        float3 flameC = st == 5 ? float3(1.0, 0.45, 0.3) : mix(float3(0.55, 0.75, 1.0), float3(1.0), 1.0 - u);
        rgb += flameC * flame * 0.9;
        al = max(al, min(1.0, flame * 0.8));
    }
    // the beacon on the fin's tip
    float bk = st == 0 ? 0.3 : calls > 0.5 ? 0.5 + 0.5 * sin(phase * 4.0) : step(0.8, fract(phase * 0.5));
    float bl = constellations_pr_star(p - float2(-0.62, 0.45), 0.02, 0.4) * bk;
    rgb += mix(float3(1.0, 0.35, 0.3), lamp, calls) * bl;
    al = max(al, min(1.0, bl));
    float4 o = float4(rgb, al);
    o = constellations_pr_halo(o, d, glow, mix(col.rgb, lamp, calls), c, 8.0);
    return o * constellations_pr_fade(c) * col.a;
}

// ---------------------------------------------------------------------------------------------------------------
// The turtle: a ringed planet crossing the sky, slow and steady. Banded in its color, lit from one side with a soft
// terminator, its rings tilted (their far half behind the planet, the near half in front), with a gap in them. While
// busy a small moon goes round it; when it calls the rings take the state's color; idle it's dim. p = c * (1.5, 0.9).
float4 draw_constellations_planet(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.5, 0.9);
    float px = max(fwidth(p.x), fwidth(p.y)) + 1e-5;
    int st = int(extra.w + 0.5);
    float3 lamp = constellations_pr_lamp(st);
    float calls = constellations_pr_calls(st);
    float R = 0.4;
    float r = length(p);
    float planet = 1.0 - smoothstep(R - px, R + px, r);
    float2 q = p / R;
    float3 n = normalize(float3(q, sqrt(max(0.02, 1.0 - dot(q, q)))));
    float lit = smoothstep(-0.15, 0.45, dot(n, normalize(float3(-0.6, 0.45, 0.65))));
    float lat = q.y + 0.08 * sin(q.x * 3.0);
    float bands = 0.5 + 0.5 * sin(lat * 11.0 + vnoise(q * 3.0 + 2.0) * 2.0);
    float3 surf = mix(col.rgb * 0.7, mix(col.rgb, float3(1.0, 0.95, 0.88), 0.45), bands);
    float3 pc = surf * (0.07 + 0.95 * lit);
    // the rings
    float tilt = -0.28;
    float2 rq = constellations_pr_rot(p, tilt);
    float2 e = float2(rq.x, rq.y / 0.24);
    float er = length(e);
    float ringM = smoothstep(0.56, 0.6, er) * (1.0 - smoothstep(0.95, 0.99, er));
    ringM *= 1.0 - 0.75 * (1.0 - smoothstep(0.0, 0.025, abs(er - 0.8)));        // the gap
    ringM *= 0.65 + 0.35 * sin(er * 70.0);                                       // fine bands
    float front = rq.y < 0.0 ? 1.0 : 0.0;
    float hidden = (1.0 - front) * planet;
    float3 ringC = mix(mix(col.rgb, float3(0.95, 0.9, 0.8), 0.55), lamp, calls * (0.55 + 0.25 * sin(phase * 3.0)));
    float ringA = ringM * 0.7 * (1.0 - hidden);
    // the planet's shadow across the near rings, a darker band behind it
    float shade = 1.0 - 0.5 * (1.0 - smoothstep(R * 0.9, R * 1.25, length(rq + float2(0.18, 0.0)))) * (1.0 - front);
    float dim = st == 0 ? 0.6 : 1.0;
    float3 rgb = pc * planet * dim;
    float a = planet;
    rgb = rgb * (1.0 - ringA) + ringC * ringM * shade * dim * 0.8 * (1.0 - hidden);
    a = a + ringA * (1.0 - a);
    // a thin rim of atmosphere on the lit side
    float atm = exp(-abs(r - R) / max(px, 0.008)) * (0.3 + 0.7 * lit);
    rgb += mix(col.rgb, float3(0.8, 0.9, 1.0), 0.5) * atm * 0.4 * dim;
    a = max(a, min(1.0, atm * 0.5));
    // busy: a little moon going round, hidden when it passes behind
    if (st == 1) {
        float m = phase * 0.9;
        float2 mp = constellations_pr_rot(float2(cos(m) * 0.86, sin(m) * 0.86 * 0.24), -tilt);
        float behindP = (sin(m) > 0.0 && length(mp) < R) ? 0.0 : 1.0;
        float moon = constellations_pr_star(p - mp, 0.03, 0.15) * behindP;
        rgb += float3(1.0, 0.98, 0.94) * moon;
        a = max(a, min(1.0, moon));
    }
    float4 o = float4(rgb, a);
    o = constellations_pr_halo(o, r - R, glow, mix(col.rgb, lamp, calls), c, 7.0);
    return o * constellations_pr_fade(c) * col.a;
}

// ---------------------------------------------------------------------------------------------------------------
// The jellyfish: a little nebula that drifts like one. A bell of glowing gas, brighter at its rim, that breathes in
// and out, and long tentacles that are threads of tiny stars, waving. Busy it breathes faster and brighter; in error
// the tentacles hang limp and the gas flickers; idle it's faint. p = c * (0.9, 1.4).
float4 draw_constellations_jelly(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(0.9, 1.4);
    float px = max(fwidth(p.x), fwidth(p.y)) + 1e-5;
    int st = int(extra.w + 0.5);
    float dim = st == 0 ? 0.55 : st == 1 ? 1.15 : 1.0;
    float err = st == 5 ? 1.0 : 0.0;
    float beat = 0.5 + 0.5 * sin(phase * 1.6);
    float2 bc = float2(0.0, 0.48 + beat * 0.03);
    float2 rr = float2(0.5 * (1.0 - 0.08 * beat), 0.36 * (1.0 + 0.05 * beat));
    float2 q = p - bc;
    float scal = 0.025 * sin(atan2(q.y, q.x) * 9.0);
    float bell = (length(q / rr) - 1.0) * rr.y - scal * step(q.y, 0.0);
    bell = max(bell, -(q.y + 0.1 + 0.03 * sin(q.x * 18.0)));
    float inside = 1.0 - smoothstep(-px, px, bell);
    float rim = exp(-abs(bell) / max(px * 1.2, 0.02));
    float n = vnoise(q * 6.0 + float2(phase * 0.15, 0.0)) * 0.6 + vnoise(q * 13.0 - phase * 0.1) * 0.4;
    float flick = err > 0.5 ? 0.6 + 0.4 * vnoise(float2(phase * 4.0, 0.0)) : 1.0;
    float3 gas = mix(col.rgb, float3(0.55, 0.65, 1.0), 0.25 * (1.0 - smoothstep(-0.3, 0.3, q.y)));
    float core = exp(-dot(q - float2(0.0, 0.05), q - float2(0.0, 0.05)) / 0.03);
    float body = inside * (0.22 + 0.35 * n) + rim * 0.55;
    float3 rgb = (gas * body + mix(gas, float3(1.0), 0.6) * core * 0.6 * inside) * dim * flick;
    float a = clamp(inside * (0.3 + 0.25 * n) + rim * 0.45 + core * 0.3 * inside, 0.0, 1.0) * min(1.0, dim);
    // the tentacles: threads of tiny stars
    float base = bc.y - 0.1;
    for (int i = 0; i < 5; i++) {
        float fi = float(i);
        float x0 = (fi - 2.0) * 0.16;
        float down = base - p.y;
        if (down < 0.0 || down > 1.5) continue;
        float amp = mix(0.07, 0.015, err) * (0.4 + down);
        float x = x0 * (1.0 - 0.25 * down) + sin(phase * 1.3 - down * 3.5 + fi * 1.7) * amp + err * 0.0;
        float dx = abs(p.x - x);
        float len = (1.25 - abs(fi - 2.0) * 0.18) * (1.0 - 0.15 * err);
        float fadeT = 1.0 - smoothstep(len * 0.6, len, down);
        float thread_ = constellations_pr_line(dx, max(0.006, px * 0.45), px) * 0.35 * fadeT;
        float k = down * 9.0 + fi * 0.37;
        float ky = (floor(k) + 0.5 - fi * 0.37) / 9.0;
        float2 sq = float2(p.x - x, (base - p.y) - ky);
        float tw = 0.6 + 0.4 * sin(phase * 2.0 + floor(k) * 1.9 + fi);
        float star = constellations_pr_star_px(sq, 0.016, px) * fadeT * tw;
        rgb += mix(gas, float3(1.0), 0.4) * (thread_ * 0.6 + star * 0.8) * dim * flick;
        a = max(a, min(1.0, (thread_ + star) * min(1.0, dim)));
    }
    float4 o = float4(rgb, a);
    o = constellations_pr_halo(o, bell, glow, col.rgb, c, 6.0);
    return o * constellations_pr_fade(c) * col.a;
}

// ---------------------------------------------------------------------------------------------------------------
// The seahorse: a small constellation in its shape, upright, the snout to +x and the tail curled under. The tail
// curls and uncurls as it bobs, the little dorsal fin flutters; it twinkles faster while busy and its lines take the
// state's color when it calls. p = c * (0.75, 1.2).
constant int2 CONSTELLATIONS_PR_SEAHORSE[18] = {
    int2(0, 1), int2(1, 3), int2(3, 4), int2(4, 5), int2(5, 6), int2(6, 9), int2(9, 10), int2(10, 11),
    int2(11, 12), int2(12, 13), int2(1, 7), int2(7, 8), int2(8, 9), int2(5, 14), int2(14, 6), int2(-1, -1),
    int2(-1, -1), int2(-1, -1)
};
float4 draw_constellations_seahorse(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(0.75, 1.2);
    int st = int(extra.w + 0.5);
    float calls = constellations_pr_calls(st);
    float curl = sin(phase * 1.2) * 0.12;
    float flut = sin(phase * 7.0) * 0.03;
    float2 pts[15] = {
        float2(0.68, 0.6),      // 0 snout tip
        float2(0.3, 0.72),      // 1 snout base
        float2(0.14, 0.8),      // 2 eye
        float2(0.08, 0.98),     // 3 crown
        float2(-0.16, 0.66),    // 4 back of the head
        float2(-0.28, 0.32),    // 5 back
        float2(-0.24, -0.12),   // 6 back, low
        float2(0.26, 0.44),     // 7 throat
        float2(0.36, 0.08),     // 8 belly
        float2(0.02, -0.42),    // 9 tail
        float2(0.18, -0.66),    // 10 tail
        float2(0.08, -0.9),     // 11 curl
        float2(-0.14, -0.82),   // 12 curl
        float2(-0.08, -0.64),   // 13 curl's end
        float2(-0.46 + flut, 0.06) // 14 dorsal fin
    };
    // the curl winds and unwinds around its middle
    float2 cc = float2(0.03, -0.74);
    for (int i = 10; i < 14; i++) pts[i] = cc + constellations_pr_rot(pts[i] - cc, curl * float(i - 9) * 0.5);
    float sz[15] = { 0.45, 0.35, 1.0, 0.4, 0.5, 0.55, 0.4, 0.35, 0.5, 0.45, 0.4, 0.55, 0.35, 0.3, 0.4 };
    float3 lc = mix(col.rgb, constellations_pr_lamp(st), calls * 0.6);
    float dim = st == 0 ? 0.6 : 1.0;
    float4 o = constellations_pr_figure(p, pts, sz, 15, CONSTELLATIONS_PR_SEAHORSE, 2, phase, glow, lc, dim);
    return o * constellations_pr_fade(c) * col.a;
}

// ---------------------------------------------------------------------------------------------------------------
// The crab: a crab of stars (the sky has one, Cancer). A ring of stars for its shell, two eyes on stalks, two claws
// and six legs; the legs step while it walks and the claws snap while it's busy; it stands still, its lines in the
// state's color, when it waits or fails. p = c * (1.3, 0.9).
constant int2 CONSTELLATIONS_PR_CRAB[32] = {
    int2(0, 1), int2(1, 2), int2(2, 3), int2(3, 4), int2(4, 5), int2(5, 0), int2(1, 6), int2(2, 7),
    int2(0, 8), int2(8, 9), int2(8, 10), int2(3, 11), int2(11, 12), int2(11, 13),
    int2(0, 14), int2(14, 15), int2(5, 16), int2(16, 17), int2(5, 18), int2(18, 19),
    int2(3, 20), int2(20, 21), int2(4, 22), int2(22, 23), int2(4, 24), int2(24, 25),
    int2(-1, -1), int2(-1, -1), int2(-1, -1), int2(-1, -1), int2(-1, -1), int2(-1, -1)
};
float4 draw_constellations_crab(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.3, 0.9);
    int st = int(extra.w + 0.5);
    float calls = constellations_pr_calls(st);
    float walking = (st == 0 || st == 2 || st == 5) ? 0.0 : 1.0;
    float snap = st == 1 ? max(0.0, sin(phase * 5.0)) : 0.0;
    float2 pts[26];
    pts[0] = float2(-0.34, 0.0);  pts[1] = float2(-0.16, 0.2);  pts[2] = float2(0.16, 0.2);
    pts[3] = float2(0.34, 0.0);   pts[4] = float2(0.16, -0.2);  pts[5] = float2(-0.16, -0.2);
    pts[6] = float2(-0.1, 0.38);  pts[7] = float2(0.1, 0.38);
    pts[8] = float2(-0.58, 0.28); pts[9] = float2(-0.66 + snap * 0.05, 0.56 - snap * 0.08); pts[10] = float2(-0.84, 0.4);
    pts[11] = float2(0.58, 0.28); pts[12] = float2(0.66 - snap * 0.05, 0.56 - snap * 0.08); pts[13] = float2(0.84, 0.4);
    // the legs: knee and foot, three on each side; they step in turn while it walks
    for (int j = 0; j < 3; j++) {
        float fj = float(j);
        for (int s = 0; s < 2; s++) {
            float sd = s == 0 ? -1.0 : 1.0;
            float stp = sin(phase * 6.0 + fj * 2.1 + float(s) * 3.14159) * walking;
            int k = 14 + s * 6 + j * 2;
            pts[k] = float2(sd * (0.54 + fj * 0.03), -0.06 - fj * 0.14 + max(0.0, stp) * 0.05);
            pts[k + 1] = float2(sd * (0.86 - fj * 0.04) + stp * 0.04, -0.22 - fj * 0.17 + max(0.0, stp) * 0.07);
        }
    }
    float sz[26] = { 0.6, 0.45, 0.45, 0.6, 0.4, 0.4, 0.75, 0.75, 0.45, 0.55, 0.45, 0.45, 0.55, 0.45,
                     0.2, 0.3, 0.2, 0.3, 0.2, 0.3, 0.2, 0.3, 0.2, 0.3, 0.2, 0.3 };
    float3 lc = mix(col.rgb, constellations_pr_lamp(st), calls * 0.6);
    float dim = st == 0 ? 0.6 : 1.0;
    float4 o = constellations_pr_figure(p, pts, sz, 26, CONSTELLATIONS_PR_CRAB, 6, phase, glow, lc, dim);
    return o * constellations_pr_fade(c) * col.a;
}

// ---------------------------------------------------------------------------------------------------------------
// The starfish: a real star, a marker in the sky. A white-hot core in its color, a soft corona and diffraction
// spikes (four long, four short) that breathe as it twinkles. Busy it twinkles quickly; idle it's small and faint;
// in error it's a reddish star that gutters; done, it flares. p = c.
float4 draw_constellations_star(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c;
    float px = max(fwidth(p.x), fwidth(p.y)) + 1e-5;
    int st = int(extra.w + 0.5);
    float calls = constellations_pr_calls(st);
    float3 sc = mix(col.rgb, constellations_pr_lamp(st), calls * 0.6);
    float tw = st == 1 ? 0.78 + 0.22 * sin(phase * 5.0) * sin(phase * 1.7)
             : st == 5 ? 0.45 + 0.55 * vnoise(float2(phase * 3.0, 4.0)) : 0.9 + 0.1 * sin(phase * 0.8);
    float size = st == 0 ? 0.6 : 1.0;
    float r = length(p);
    float rc = max(0.07 * size, px);
    float core = 1.0 - smoothstep(rc * 0.45, rc, r);
    float corona = exp(-r * r / (0.03 * size)) * 0.7 + exp(-r * r / 0.15) * 0.18;
    float th = px * 0.6 + 0.008;
    float L = 0.55 * size * tw;
    float sp = exp(-abs(p.y) / th) * exp(-abs(p.x) / L) + exp(-abs(p.x) / th) * exp(-abs(p.y) / L);
    float2 dq = constellations_pr_rot(p, 0.785);
    float sp2 = (exp(-abs(dq.y) / th) * exp(-abs(dq.x) / (L * 0.35)) + exp(-abs(dq.x) / th) * exp(-abs(dq.y) / (L * 0.35))) * 0.6;
    float lum = (core * 1.2 + corona + (sp + sp2) * 0.8) * tw * (st == 0 ? 0.6 : 1.0) * (1.0 + glow * 0.5);
    float3 rgb = mix(sc, float3(1.0, 0.98, 0.95), core * 0.7 + 0.2) * lum;
    float a = min(1.0, lum);
    float4 o = float4(rgb, a);
    o = constellations_pr_halo(o, r - 0.1, glow, sc, c, 6.0);
    return o * constellations_pr_fade(c) * col.a;
}

// ---------------------------------------------------------------------------------------------------------------
// The bottle: a balloon carrying a message, drifting high in the sky. A soft round balloon in its color, lit from
// inside like a paper lantern, tied at the bottom; a thin string and a little rolled letter swinging under it. Waiting
// (a message for you) it glows warm and pulses; busy the letter flutters; in error it's half deflated, wrinkled and
// sagging; idle its light is out. p = c * (0.8, 1.0).
float4 draw_constellations_balloon(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(0.8, 1.0);
    float px = max(fwidth(p.x), fwidth(p.y)) + 1e-5;
    int st = int(extra.w + 0.5);
    float calls = constellations_pr_calls(st);
    float3 lamp = constellations_pr_lamp(st);
    float err = st == 5 ? 1.0 : 0.0;
    // the balloon: a round top tapering to the knot; deflated in error
    float2 bc = float2(0.0, 0.32 - err * 0.06);
    float2 rad = float2(0.36, 0.42) * float2(1.0 - err * 0.18, 1.0 - err * 0.3);
    float2 q = p - bc;
    float taper = 1.0 - 0.35 * smoothstep(0.0, -0.45, q.y);
    float wrinkle = err * 0.025 * sin(atan2(q.y, q.x) * 7.0 + 1.0);
    float bal = (length(q / float2(rad.x * taper, rad.y)) - 1.0) * rad.x * 0.9 - wrinkle;
    float2 knot = float2(0.0, bc.y - rad.y - 0.02);
    float kn = sd_tri(p, knot + float2(-0.035, -0.035), knot + float2(0.035, -0.035), knot + float2(0.0, 0.04));
    float d = min(bal, kn);
    float a = 1.0 - smoothstep(-px, px, d);
    float2 nq = q / rad;
    float3 n = normalize(float3(nq, sqrt(max(0.05, 1.0 - dot(nq, nq)))));
    float lit = 0.35 + 0.65 * max(0.0, dot(n, normalize(float3(-0.4, 0.6, 0.65))));
    float inner = st == 0 ? 0.15 : 0.55 + (st == 2 ? 0.35 * (0.5 + 0.5 * sin(phase * 4.0)) : 0.0) + (st == 1 ? 0.1 : 0.0);
    float3 skin = mix(col.rgb, lamp, calls * 0.45);
    float glowIn = exp(-dot(q - float2(0.0, -0.05), q - float2(0.0, -0.05)) / 0.09) * inner;
    float3 c3 = skin * (0.35 * lit + 0.25) + mix(skin, float3(1.0, 0.9, 0.7), 0.5) * glowIn;
    // gores (the seams of a paper lantern) and a glint
    float gores = 1.0 - 0.18 * (1.0 - smoothstep(0.0, 0.05 + px, abs(fract(atan2(nq.x, n.z) * 0.95 + 0.5) - 0.5)));
    c3 *= gores;
    c3 += float3(1.0) * (1.0 - smoothstep(0.0, 0.07, length(nq - float2(-0.42, 0.45)))) * 0.35 * (1.0 - err);
    if (kn < bal) c3 = skin * 0.5;
    float rim = exp(-abs(d) / max(px * 0.9, 0.005)) * 0.3;
    float3 rgb = c3 * a + skin * rim;
    float al = max(a, rim * 0.5);
    // the string and the letter, swinging
    float swing = sin(phase * 1.4) * (st == 1 ? 0.06 : 0.03);
    float2 s0 = knot + float2(0.0, -0.035);
    float2 s1 = float2(0.04 + swing, -0.58);
    float2 sm = (s0 + s1) * 0.5 + float2(0.03 - swing * 0.5, 0.0);
    float strD = min(sd_seg(p, s0, sm), sd_seg(p, sm, s1));
    float str = constellations_pr_line(strD, max(0.005, px * 0.4), px) * 0.6;
    rgb += float3(0.85, 0.85, 0.9) * str * (1.0 - al);
    al = max(al, str);
    float flap = st == 1 ? sin(phase * 9.0) * 0.12 : 0.0;
    float2 lq = constellations_pr_rot(p - s1 - float2(0.0, -0.04), 0.25 + flap + swing);
    float letter = sd_box(lq, float2(0.11, 0.035), 0.02);
    float la = 1.0 - smoothstep(-px, px, letter);
    float3 paper = float3(0.95, 0.9, 0.78) * (0.75 + 0.25 * smoothstep(-0.035, 0.035, lq.y)) * (st == 0 ? 0.6 : 1.0);
    paper = mix(paper, skin, (1.0 - smoothstep(0.012, 0.012 + px, abs(lq.x))) * 0.8);   // a ribbon round it
    rgb = rgb * (1.0 - la) + paper * la;
    al = max(al, la);
    float4 o = float4(rgb, al);
    o = constellations_pr_halo(o, bal, glow, mix(skin, lamp, calls), c, 7.0);
    return o * constellations_pr_fade(c) * col.a;
}

// ---------------------------------------------------------------------------------------------------------------
// The hourglass: a moon going through its phases, and a thin orbit round it that closes as time runs. The lit part
// of the moon and the arc of the orbit are the value (1 full, 0 new and only the faint earthshine left); a small
// star rides the arc's end, ticking while busy. The orbit takes the state's color when it calls. p = c.
float4 draw_constellations_moon(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c;
    float px = max(fwidth(p.x), fwidth(p.y)) + 1e-5;
    int st = int(extra.w + 0.5);
    float calls = constellations_pr_calls(st);
    float3 lamp = constellations_pr_lamp(st);
    float v = clamp(extra.y, 0.0, 1.0);
    float R = 0.46;
    float r = length(p);
    float disc = 1.0 - smoothstep(R - px, R + px, r);
    // the terminator: lit where x is past it (waxing from the right)
    float w = sqrt(max(0.0, R * R - p.y * p.y));
    float xt = w * (1.0 - 2.0 * v);
    float litM = smoothstep(xt - px * 1.5, xt + px * 1.5, p.x) * disc;
    if (v < 0.005) litM = 0.0;
    float2 q = p / R;
    float3 n = normalize(float3(q, sqrt(max(0.02, 1.0 - dot(q, q)))));
    float shadeL = 0.65 + 0.35 * n.z;
    float maria = 1.0 - 0.25 * smoothstep(0.35, 0.7, vnoise(q * 3.0 + 4.0));
    float3 face = mix(col.rgb, float3(0.96, 0.94, 0.88), 0.55) * shadeL * maria;
    float dim = st == 0 ? 0.6 : 1.0;
    float3 rgb = face * litM * dim + col.rgb * 0.09 * disc * (1.0 - litM);
    float a = disc;
    float edge = exp(-abs(r - R) / max(px * 0.8, 0.005)) * 0.25 * (1.0 - litM);
    rgb += col.rgb * edge;
    // the orbit: from the top, clockwise, as far as the value; the rest a faint dotted line
    float Ro = 0.74;
    float ang = atan2(p.x, p.y);                                   // 0 at the top, growing clockwise
    float u = fract(ang / 6.28318 + 1.0);
    float ringD = abs(r - Ro);
    float lw = max(0.012, px * 0.55);
    float drawn = step(u, v);
    float dots = step(0.5, fract(u * 36.0));
    float3 oc = mix(mix(col.rgb, float3(0.9, 0.92, 1.0), 0.4), lamp, calls);
    float ol = constellations_pr_line(ringD, lw, px) * (drawn * 0.75 + (1.0 - drawn) * dots * 0.18) * dim;
    rgb += oc * ol * (1.0 - a);
    a = max(a, ol);
    // the star at the arc's end
    float ea = v * 6.28318;
    float2 ep = Ro * float2(sin(ea), cos(ea));
    float tick = st == 1 ? 0.6 + 0.4 * step(0.5, fract(phase * 1.0)) : 0.85;
    float es = constellations_pr_star(p - ep, 0.04, 0.4) * tick * dim;
    rgb += mix(oc, float3(1.0), 0.5) * es;
    a = max(a, min(1.0, es));
    float4 o = float4(rgb, a);
    o = constellations_pr_halo(o, r - R, glow * 0.7, oc, c, 9.0);
    return o * constellations_pr_fade(c) * col.a;
}

// ---------------------------------------------------------------------------------------------------------------
// The anchor: a probe moored on a tether, pinned in place. It came down on its line and hangs there, swaying a
// little: a small body with a dish under it and two short panels, the tether running up out of sight, and a beacon
// on top in the state's color (slow and dim idle, blinking quickly in error). Busy, its dish sweeps. p = c * (0.8, 1.3).
float4 draw_constellations_probe(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.0, 1.3);
    float px = max(fwidth(p.x), fwidth(p.y)) + 1e-5;
    int st = int(extra.w + 0.5);
    float calls = constellations_pr_calls(st);
    float3 lamp = constellations_pr_lamp(st);
    // it swings from far above
    float2 pivot = float2(0.0, 2.6);
    float sw = sin(phase * 0.45) * 0.035 + (st == 5 ? sin(phase * 3.0) * 0.02 : 0.0);
    float2 b = pivot + constellations_pr_rot(p - pivot, -sw);
    float2 bc = float2(0.0, -0.45);
    float k = 1.4;                                                  // the probe's own scale
    float2 l = (b - bc) / k;
    float body = sd_box(l, float2(0.15, 0.13), 0.035) * k;
    float panels = min(sd_box(l - float2(-0.38, 0.02), float2(0.16, 0.07), 0.0), sd_box(l - float2(0.38, 0.02), float2(0.16, 0.07), 0.0)) * k;
    float strut = sd_box(l - float2(0.0, 0.02), float2(0.25, 0.012), 0.0) * k;
    // the dish under it, seen from the side: a shallow bowl, turning while busy
    float sweep = st == 1 ? sin(phase * 1.5) : 0.4;
    float2 dq = l - float2(0.0, -0.2);
    float dw = 0.2 * (0.55 + 0.45 * abs(sweep));
    float dish = max(abs(length((dq - float2(0.0, 0.22)) / float2(dw / 0.2, 1.0)) - 0.27) - 0.012, dq.y - 0.03) * k;
    float feed = (sd_seg(dq, float2(0.0, -0.05), float2(0.0, 0.12)) - 0.008) * k;
    float d = min(min(body, panels), min(strut, min(dish, feed)));
    float a = 1.0 - smoothstep(-px, px, d);
    float3 metal = mix(float3(0.78, 0.8, 0.86), col.rgb, 0.3);
    float3 c3 = metal * (0.55 + 0.45 * smoothstep(-0.13, 0.13, l.y));
    if (panels < min(body, strut)) {
        float2 g = fract(l * float2(14.0, 18.0));
        c3 = float3(0.16, 0.24, 0.46) * (0.8 + 0.4 * step(0.12, min(g.x, g.y)));
    }
    if (dish < body && dish < panels) c3 = metal * 0.85;
    float rim = exp(-abs(d) / max(px * 0.8, 0.004)) * smoothstep(-0.05, 0.1, l.y) * 0.3;
    float3 rgb = c3 * a + float3(0.9, 0.93, 1.0) * rim * a;
    float al = a;
    // the tether, up to where it's moored
    float tx = sin((b.y - bc.y) * 2.0 + phase * 0.3) * 0.012;
    float teth = constellations_pr_line(abs(b.x - tx), max(0.005, px * 0.4), px) * step(bc.y + 0.13 * k, b.y)
               * (1.0 - smoothstep(0.3, 1.25, b.y));
    rgb += mix(float3(0.75, 0.78, 0.85), col.rgb, 0.3) * teth * 0.55 * (1.0 - al);
    al = max(al, teth * 0.55);
    // the beacon
    float rate = st == 0 ? 0.35 : st == 5 ? 3.0 : calls > 0.5 ? 2.0 : 0.8;
    float bk = st == 0 ? 0.35 : 0.35 + 0.65 * smoothstep(0.55, 1.0, sin(phase * rate) * 0.5 + 0.5);
    float bl = constellations_pr_star(b - bc - float2(0.0, 0.17 * k), 0.032, 0.5) * bk;
    float3 bcol = calls > 0.5 || st == 0 ? lamp : float3(1.0, 0.95, 0.85);
    rgb += bcol * bl;
    al = max(al, min(1.0, bl));
    float4 o = float4(rgb, al);
    o = constellations_pr_halo(o, d, glow, mix(col.rgb, lamp, calls), c, 8.0);
    return o * constellations_pr_fade(c) * col.a;
}

// ---------------------------------------------------------------------------------------------------------------
// The flag: planted on a little moon of its own. A small cratered moonlet lit from one side, a thin pole standing
// on it, and the cloth in the state's color (the app gives it: green ok, yellow waiting, red error, gray idle),
// waving: quickly while busy, hanging limp in error. p = c * (0.8, 1.15).
float4 draw_constellations_flag(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(0.8, 1.15);
    float px = max(fwidth(p.x), fwidth(p.y)) + 1e-5;
    int st = int(extra.w + 0.5);
    // the moonlet
    float2 mc = float2(0.0, -0.6);
    float Rm = 0.36;
    float2 mq = p - mc;
    float lump = 0.012 * sin(atan2(mq.y, mq.x) * 5.0 + 1.0);
    float moon = length(mq) - Rm - lump;
    float ma = 1.0 - smoothstep(-px, px, moon);
    float2 nq = mq / Rm;
    float3 n = normalize(float3(nq, sqrt(max(0.05, 1.0 - dot(nq, nq)))));
    float lit = smoothstep(-0.1, 0.6, dot(n, normalize(float3(-0.55, 0.6, 0.6))));
    float2 cg = nq * 3.2;
    float2 cid = floor(cg);
    float cr = length(fract(cg) - 0.5);
    float crater = step(0.5, hash21(cid + 2.0)) * (1.0 - smoothstep(0.2, 0.3, cr));
    float3 stone = float3(0.62, 0.6, 0.58) * (0.8 + 0.3 * vnoise(nq * 5.0)) * (1.0 - crater * 0.3);
    float3 rgb = stone * (0.08 + 0.85 * lit) * ma;
    float al = ma;
    // the pole, standing on top
    float2 pb = mc + float2(-0.04, Rm - 0.02);
    float2 pt = float2(-0.07, 0.7);
    float pole = sd_seg(p, pb, pt) - max(0.012, px * 0.5);
    float pa = (1.0 - smoothstep(-px, px, pole)) * (1.0 - ma);
    rgb = rgb * (1.0 - pa) + float3(0.85, 0.86, 0.9) * pa;
    al = max(al, pa);
    float knob = constellations_pr_star(p - pt - float2(0.0, 0.03), 0.02, 0.3);
    // the cloth: hangs from the pole's top, waving outward
    float err = st == 5 ? 1.0 : 0.0;
    float amp = (st == 1 ? 0.05 : 0.035) * (1.0 - err * 0.75);
    float spd = st == 1 ? 2.6 : st == 0 ? 0.8 : 1.6;
    float x = p.x - pt.x;
    float L = 0.52;
    float k = clamp(x / L, 0.0, 1.0);
    float droop = err * k * 0.25;
    float yc = pt.y - 0.13 - droop + sin(phase * spd - x * 9.0) * amp * k;
    float hh = 0.13 * (1.0 - err * 0.3) * (1.0 - 0.15 * k);
    float cloth = max(abs(p.y - yc) - hh, max(-x, x - L * (1.0 - err * 0.15)));
    float ca = 1.0 - smoothstep(-px, px, cloth);
    float fold = 0.75 + 0.25 * sin(phase * spd - x * 9.0 + 1.2);
    float3 cc = col.rgb * fold;
    cc += mix(col.rgb, float3(1.0), 0.5) * glow * 0.3;
    rgb = rgb * (1.0 - ca) + cc * ca;
    al = max(al, ca);
    rgb += float3(1.0, 0.97, 0.9) * knob * 0.8;
    al = max(al, min(1.0, knob));
    float4 o = float4(rgb, al);
    o = constellations_pr_halo(o, cloth, glow * 0.9 + 0.12, col.rgb, c, 9.0);
    return o * constellations_pr_fade(c) * col.a;
}

// ---------------------------------------------------------------------------------------------------------------
// The helm: an armillary sphere, the old astronomers' instrument of rings. A fixed meridian ring, the tilted ring of
// the ecliptic, and a ring that turns round the polar axis while busy (slowly while waiting, a shudder in error);
// at the heart a small sphere lit in the state's color (the app gives it as `col`: green ok, blue busy…). p = c.
float4 draw_constellations_armillary(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c;
    float px = max(fwidth(p.x), fwidth(p.y)) + 1e-5;
    int st = int(extra.w + 0.5);
    float tilt = 0.38 + (st == 5 ? sin(phase * 7.0) * 0.05 : 0.0);
    float2 q = constellations_pr_rot(p, -tilt);
    float R = 0.66;
    float turn = st == 1 ? phase * 0.7 : st == 2 ? phase * 0.15 : 0.9;
    float lw = max(0.016, px * 0.6);
    float3 brass = float3(0.86, 0.74, 0.5);
    float meridian = abs(length(q) - R);
    float2 eq = constellations_pr_rot(q, 0.4);
    float ecl = abs(length(eq / float2(1.0, 0.28)) - R) * 0.28;
    // the turning ring: a circle round the vertical axis, seen as an ellipse whose width follows the angle
    float cw = max(0.05, abs(cos(turn)));
    float mov = abs(length(q / float2(cw, 1.0)) - R) * cw;
    float equ = abs(length(q / float2(1.0, 0.16)) - R) * 0.16;
    float axis = max(abs(q.x) - lw * 0.5, abs(q.y) - (R + 0.2));
    float m1 = constellations_pr_line(meridian, lw, px);
    float m2 = constellations_pr_line(ecl, lw * 0.9, px);
    float m3 = constellations_pr_line(mov, lw * 0.8, px);
    float m4 = constellations_pr_line(equ, lw * 0.7, px) * 0.6;
    float m5 = 1.0 - smoothstep(-px, px, axis);
    // the far half of the rings is fainter (it's behind the hub)
    float far2 = eq.y > 0.0 ? 0.55 : 1.0;
    float far3 = (sin(turn) * q.x > 0.0) ? 0.55 : 1.0;
    float far4 = q.y > 0.0 ? 0.55 : 1.0;
    float dim = st == 0 ? 0.6 : 1.0;
    float ringA = max(max(m1, m2 * far2), max(m3 * far3, max(m4 * far4, m5 * 0.8)));
    float3 rgb = brass * (0.55 + 0.45 * smoothstep(-0.7, 0.7, p.y)) * ringA * dim;
    float a = ringA;
    // the ecliptic carries the signs: small stars along it
    float ang = atan2(eq.y / 0.28, eq.x);
    float tick = constellations_pr_line(abs(fract(ang / 6.28318 * 12.0 + 0.5) - 0.5) * 0.4, 0.012, px) * m2 * 0.5;
    rgb += brass * tick * 0.5;
    // the knobs at the poles
    float knobs = constellations_pr_star(q - float2(0.0, R + 0.2), 0.025, 0.2) + constellations_pr_star(q + float2(0.0, R + 0.2), 0.025, 0.2);
    rgb += brass * knobs * 0.7 * dim;
    a = max(a, min(1.0, knobs));
    // the heart: a small sphere in the state's color, glowing
    float hr = length(p);
    float hub = 1.0 - smoothstep(0.13 - px, 0.13 + px, hr);
    float2 hq = p / 0.13;
    float3 hn = normalize(float3(hq, sqrt(max(0.02, 1.0 - dot(hq, hq)))));
    float hl = 0.45 + 0.65 * max(0.0, dot(hn, normalize(float3(-0.4, 0.6, 0.6))));
    float pulse = st == 1 ? 0.85 + 0.15 * sin(phase * 3.0) : 1.0;
    float3 hc = mix(col.rgb, float3(1.0), 0.15) * hl * pulse;
    float hg = exp(-hr * hr / 0.04) * 0.5 * (0.6 + glow);
    rgb = rgb * (1.0 - hub) + hc * hub + col.rgb * hg * (1.0 - hub);
    a = max(a, max(hub, min(1.0, hg)));
    float4 o = float4(rgb, a);
    o = constellations_pr_halo(o, length(p) - 0.15, glow * 0.8, col.rgb, c, 6.0);
    return o * constellations_pr_fade(c) * col.a;
}

// ---------------------------------------------------------------------------------------------------------------
// The lights on the side glass: distant beacons. A point of light in the state's color (the app gives it as `col`)
// with four fine spikes, inside a thin ring like a sight's, so it reads as a signal and not as one more star. It
// breathes while busy, is nearly out when idle, pulses when it needs you. p = c.
float4 draw_constellations_beacon(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c;
    float px = max(fwidth(p.x), fwidth(p.y)) + 1e-5;
    int st = int(extra.w + 0.5);
    float calls = (st == 2 || st == 4 || st == 5) ? 1.0 : 0.0;
    float level = calls > 0.5 ? 0.7 + 0.3 * sin(phase * 4.0) : st == 1 ? 0.7 + 0.25 * sin(phase * 1.2) : st == 0 ? 0.3 : 0.85;
    float r = length(p);
    float l = constellations_pr_star(p, 0.1, 0.35 + 0.4 * calls) * level;
    float ring = constellations_pr_line(abs(r - 0.52), max(0.025, px * 0.5), px) * (0.25 + 0.35 * level);
    float3 rgb = mix(col.rgb, float3(1.0), 0.35) * l + col.rgb * ring;
    float a = min(1.0, l + ring);
    float halo = exp(-r * r / 0.12) * level * 0.3;
    rgb += col.rgb * halo * (1.0 - a);
    a += halo * (1.0 - a) * 0.5;
    return float4(rgb, a) * (1.0 - smoothstep(0.75, 1.0, r)) * col.a;
}

// ---------------------------------------------------------------------------------------------------------------
// The battery: a power cell between two small solar panels. Upright, a terminal on top, five cells inside lit from
// the bottom up to the value, in its color (amber when low, red when nearly empty). Busy it's charging: light runs
// from the panels into it and the next cell blinks. In error it flickers. p = c * (1.3, 1.0).
float4 draw_constellations_cell(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.3, 1.0);
    float px = max(fwidth(p.x), fwidth(p.y)) + 1e-5;
    int st = int(extra.w + 0.5);
    float v = clamp(extra.y, 0.0, 1.0);
    float2 cc = float2(0.0, -0.05);
    float shell = sd_box(p - cc, float2(0.2, 0.42), 0.06);
    float term = sd_box(p - cc - float2(0.0, 0.47), float2(0.07, 0.05), 0.015);
    float panels = min(sd_box(p - float2(-0.78, 0.0), float2(0.26, 0.34), 0.01), sd_box(p - float2(0.78, 0.0), float2(0.26, 0.34), 0.01));
    float strut = sd_box(p, float2(0.55, 0.012), 0.0);
    float d = min(min(shell, term), min(panels, strut));
    float a = 1.0 - smoothstep(-px, px, d);
    float3 metal = float3(0.72, 0.74, 0.8);
    float3 c3 = metal * (0.5 + 0.45 * smoothstep(-0.5, 0.5, p.y));
    float sun = 0.0;
    if (panels < min(min(shell, term), strut)) {
        float2 g = fract((p - float2(0.0, 0.34)) * float2(7.0, 9.0));
        c3 = float3(0.14, 0.22, 0.44) * (0.8 + 0.4 * step(0.12, min(g.x, g.y)));
        // charging: light running across the panels toward the cell
        if (st == 1) sun = exp(-pow(fract(-abs(p.x) * 1.2 + phase * 0.8) - 0.5, 2.0) / 0.01) * 0.5;
        c3 += float3(0.5, 0.65, 1.0) * sun;
    }
    // the cells: five, from the bottom; lit up to the value
    float3 lvl = v < 0.2 ? float3(1.0, 0.38, 0.32) : v < 0.45 ? float3(1.0, 0.72, 0.25) : col.rgb;
    float2 iq = p - cc;
    float innerBox = sd_box(iq, float2(0.14, 0.36), 0.03);
    float idx = clamp(floor((iq.y + 0.36) / 0.72 * 5.0), 0.0, 4.0);
    float sep = abs(fract((iq.y + 0.36) / 0.72 * 5.0) - 0.5);
    float cellM = (1.0 - smoothstep(-px, px, innerBox)) * smoothstep(0.08, 0.14, 0.5 - sep);
    float filled = step(idx + 0.5, v * 5.0 + 0.5);
    float next = (st == 1 && abs(idx - floor(v * 5.0 + 0.5)) < 0.5) ? 0.5 + 0.5 * sin(phase * 5.0) : 0.0;
    float flick = st == 5 ? 0.5 + 0.5 * step(0.4, vnoise(float2(phase * 6.0, 1.0))) : 1.0;
    float dim = st == 0 ? 0.5 : 1.0;
    if (innerBox < 0.0) c3 = float3(0.06, 0.07, 0.1);
    c3 = mix(c3, lvl * (0.9 + 0.2 * smoothstep(-0.14, 0.14, iq.x)) * flick * dim, cellM * max(filled, next * 0.6));
    float rim = exp(-abs(d) / max(px * 0.8, 0.004)) * smoothstep(0.0, 0.3, p.y) * 0.25;
    float3 rgb = c3 * a + float3(0.9, 0.93, 1.0) * rim * a;
    float al = a;
    float glowC = exp(-pow(sd_box(iq, float2(0.14, 0.36 * v), 0.03) / 0.08, 2.0)) * 0.25 * dim * flick * step(0.01, v);
    rgb += lvl * glowC * (1.0 - al);
    al = max(al, glowC * 0.6);
    float4 o = float4(rgb, al);
    o = constellations_pr_halo(o, shell, glow, lvl, c, 8.0);
    return o * constellations_pr_fade(c) * col.a;
}

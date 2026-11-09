// Kelp forest: the far forest, the giant kelp and the urchin barrens.

// The forest far behind: rows of kelp stalks rising to the surface, swaying, fading into the green water; the
// nearer row darker. uv 0…1 over the window (y up).
float4 draw_kelp_background(float2 uv, float t, float light, float2 gaze, float3 water, float4 extra) {
    float4 out = float4(0.0);
    for (int layer = 0; layer < 2; layer++) {
        float fl = float(layer);
        float x = uv.x + gaze.x * (0.003 + 0.004 * fl);
        float n = 11.0 - fl * 4.0;                                         // the far row is denser
        float cell = floor(x * n), fx = fract(x * n);
        float seed = hash21(float2(cell, fl * 7.0));
        float x0 = 0.3 + 0.4 * seed;
        // the stalk sways more toward the top
        float sway = sin(uv.y * 5.0 + t * 0.35 + seed * 6.0) * 0.06 * uv.y;
        float dx = abs(fx - x0 - sway) * extra.x / n;                    // in height units
        float stalk = 1.0 - smoothstep(0.002, 0.005 + fl * 0.002, dx);
        // blades along it: soft lobes alternating sides
        float by = fract(uv.y * (9.0 - fl * 2.0) + seed * 3.0);
        float side = step(0.5, fract(floor(uv.y * (9.0 - fl * 2.0) + seed * 3.0) * 0.5)) * 2.0 - 1.0;
        float2 bq = float2(((fx - x0 - sway) * extra.x / n) * side - 0.012 - fl * 0.006, by - 0.5);
        float blade = 1.0 - smoothstep(0.8, 1.0, length(bq / float2(0.016 + fl * 0.008, 0.32)));
        float k = max(stalk, blade * 0.85) * step(seed, 0.82) * smoothstep(extra.z, extra.z + 0.05, uv.y);
        // a canopy spreading under the surface
        k = max(k, smoothstep(0.86, 0.95, uv.y) * smoothstep(0.35, 0.65, vnoise(float2(x * 30.0, uv.y * 8.0 + fl))) * 0.7);
        float3 kc = mix(float3(0.28, 0.24, 0.1), float3(0.16, 0.15, 0.07), fl) * (0.5 + 0.6 * light);
        float3 c3 = mix(water, kc, 0.35 + 0.25 * fl);
        out = mix(out, float4(c3, 1.0), k * (0.55 + 0.25 * fl));
    }
    return out;
}

// Giant kelp: two stalks rising from a holdfast on the sand to the surface, swaying more the higher they go, long
// golden-brown blades along them each with a little gas bladder at its base, spreading out at the top.
// p = c * (0.3, 1.0): the stalk spans y -0.92 (holdfast) … 0.98. extra.y: the seed.
float4 draw_kelp_giant(float2 c, float t, float glow, float4 col, float4 extra) {
    float2 p = c * float2(0.3, 1.0);
    float seed = extra.y;
    float d = 1e3, bladeD = 1e3, bladderD = 1e3, along = 0.0;
    for (int s = 0; s < 2; s++) {
        float fs = float(s);
        float off = (fs - 0.5) * 0.05;
        // the stalk: a wavy line, swaying with the current, more toward the top
        float y = clamp(p.y, -0.9, 0.97);
        float u = (y + 0.9) / 1.87;
        float sx = off + sin(y * 3.0 + t * 0.45 + seed * 6.0 + fs) * 0.05 * u + sin(t * 0.3 + seed * 3.0) * 0.06 * u * u;
        d = min(d, length(float2(p.x - sx, p.y - y)) - 0.009);
        // blades every so often along it, alternating sides, drooping in the current
        for (int i = 0; i < 11; i++) {
            float fi = float(i);
            float by = -0.75 + fi * 0.165 + 0.04 * sin(fi * 7.1 + fs * 3.0 + seed * 9.0);
            float bu = (by + 0.9) / 1.87;
            float bx = off + sin(by * 3.0 + t * 0.45 + seed * 6.0 + fs) * 0.05 * bu + sin(t * 0.3 + seed * 3.0) * 0.06 * bu * bu;
            float sd = (fmod(fi + fs, 2.0) < 0.5 ? 1.0 : -1.0);
            float ang = sd * (0.75 + 0.25 * sin(t * 0.6 + fi + seed * 4.0)) + 0.35 * sin(t * 0.4 + fi * 0.7);
            float2 q = p - float2(bx, by);
            float2 r = float2(q.x * cos(ang) - q.y * sin(ang), q.x * sin(ang) + q.y * cos(ang));
            // the blade: long, narrow, rippled edge
            float L = 0.16 + 0.04 * fract(fi * 0.618 + seed);
            float2 rb = r - float2(0.0, L * 0.5 + 0.02);
            float w = 0.028 * (1.0 + 0.15 * sin(rb.y * 60.0));
            float bd = (length(rb / float2(w, L * 0.5)) - 1.0) * w;
            if (bd < bladeD) { bladeD = bd; along = clamp(rb.y / L + 0.5, 0.0, 1.0); }
            bladderD = min(bladderD, length(r - float2(0.0, 0.015)) - 0.016);
        }
    }
    // the holdfast: a tangle of little roots gripping the sand
    float hold = (length((p - float2(0.0, -0.93)) / float2(0.05, 0.03)) - 1.0) * 0.03;
    hold = max(hold, -(p.y + 0.97));
    float all = min(min(d, bladeD), min(bladderD, hold));
    float aa = fwidth(all) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, all);
    if (a <= 0.001) return float4(0.0);
    // golden-brown, lit from above, translucent blades glowing where the light comes through
    float3 base = col.rgb;
    float top = smoothstep(-0.9, 0.95, p.y);
    float3 c3;
    if (bladeD <= min(d, min(bladderD, hold))) {
        c3 = base * (0.75 + 0.35 * along) * (0.95 + 0.05 * sin(along * 50.0));             // faint ridges
        c3 += float3(0.35, 0.3, 0.1) * top * (0.4 + 0.6 * along) * 0.5;                // light through the blade
        c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.006, -bladeD)) * 0.25;                       // a darker rim
    } else if (bladderD <= min(d, hold)) {
        c3 = mix(base * 1.2, float3(0.9, 0.8, 0.5), 0.25);                                // gas bladders: round, lighter
        c3 *= 0.8 + 0.4 * smoothstep(-0.016, 0.0, -bladderD);
    } else {
        c3 = base * 0.7;
    }
    c3 *= 0.55 + 0.6 * top;
    return float4(c3 * a, a);
}

// The urchin barren: a low hump of rock where the urchins ate the kelp down to nothing; bare stone crusted pink and
// white with coralline algae, and purple urchins all over it, their spines waving. p = c * (2.4, 0.6); the sand line
// is at the bottom (c.y = -1, a little buried). extra.y: the seed.
float4 draw_kelp_barren(float2 c, float t, float glow, float4 col, float4 extra) {
    float2 p = c * float2(2.4, 0.6);
    float h = 0.08 + 0.32 * exp(-p.x * p.x * 0.9) + 0.05 * vnoise(float2(p.x * 3.0, 1.0)) + 0.03 * vnoise(float2(p.x * 9.0, 2.0));
    float taper = smoothstep(2.4, 1.6, abs(p.x));                                        // it thins out into the sand
    float rock = p.y - (-0.42 + (h + 0.2) * taper);
    // the sand line is at p.y = -0.24 ("bury": 0.3); below it the rock fades into the sand, which hides where the
    // tank's sand dips and rises under it
    float sandFade = smoothstep(-0.38, -0.2, p.y);
    float aa = fwidth(rock) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, rock);
    // the stone: grey, crusted pink and white with coralline algae, lit on top
    float n1 = vnoise(p * 3.0 + extra.y * 7.0) * 0.6 + vnoise(p * 7.0) * 0.4;
    float3 stone = mix(float3(0.42, 0.4, 0.42), col.rgb, 0.45 + 0.45 * n1);              // coralline pink over grey
    stone *= 0.92 + 0.1 * vnoise(p * 45.0 + 1.3);                                        // the crust's grain
    float pale = smoothstep(0.55, 0.9, vnoise(p * 4.5 + 3.0) * 0.6 + vnoise(p * 11.0) * 0.4);
    stone = mix(stone, float3(0.86, 0.82, 0.82), pale * 0.35);                            // dead, bleached patches
    stone *= 0.55 + 0.55 * smoothstep(-0.6, -0.1, p.y);                                  // lit from above
    stone *= 1.0 + 0.25 * (1.0 - smoothstep(0.0, 0.03, -rock));                          // the edge catches light
    float3 c3 = stone;
    float alpha = a;
    // urchins: purple balls with long spines, sitting on the rock (and a few on the sand next to it)
    for (int i = 0; i < 13; i++) {
        float fi = float(i);
        float ux = -2.1 + 4.2 * fract(fi * 0.618 + extra.y * 0.3);
        float uh = 0.08 + 0.32 * exp(-ux * ux * 0.9) + 0.05 * vnoise(float2(ux * 3.0, 1.0)) + 0.03 * vnoise(float2(ux * 9.0, 2.0));
        float r = 0.1 + 0.05 * fract(fi * 0.37);
        float2 uc = float2(ux, -0.42 + (uh + 0.2) * smoothstep(2.4, 1.6, abs(ux)) + r * 0.5 - 0.02);
        float2 q = p - uc;
        float l = length(q);
        float ang = atan2(q.y, q.x);
        float spines = 0.0;
        if (l < r * 2.1) {
            float n = 22.0;
            float wv = 0.15 * sin(t * 0.8 + fi * 2.0 + l * 10.0);                // spines waving slowly
            float s = abs(fract((ang + wv) * n / 6.2832) - 0.5) * 2.0;           // 0 on a spine
            spines = (1.0 - smoothstep(0.08, 0.22, s * (l / r))) * (1.0 - smoothstep(r * 1.4, r * 2.05, l)) * step(r * 0.8, l);
            spines *= step(-0.35, q.y / l);                                     // none going into the rock
        }
        float ball = 1.0 - smoothstep(r - 0.006, r, l);
        float3 purple = float3(0.32, 0.12, 0.42) * (0.55 + 0.6 * smoothstep(-r, r, q.y)) * (0.85 + 0.3 * vnoise(q * 80.0));
        float3 spineC = float3(0.42, 0.18, 0.55) * (0.7 + 0.5 * (l / (r * 2.0)));
        c3 = mix(c3, spineC, spines * 0.9);
        alpha = max(alpha, spines * 0.9);
        c3 = mix(c3, purple, ball);
        alpha = max(alpha, ball);
    }
    alpha *= sandFade;
    c3 = mix(float3(0.3, 0.27, 0.22) * dot(col.rgb, float3(0.4)), c3, smoothstep(-0.3, -0.12, p.y));   // sediment at the base
    return float4(c3 * alpha, alpha);
}

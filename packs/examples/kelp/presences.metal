// The kelp forest's own look for the built-in pieces: the abalone (chest), the bull kelp float (bottle), the helm
// tangled in kelp, the diver-down flag.

// A giant abalone in place of the chest: an oval shell, rough and brick-red outside with a row of breathing holes
// and a bit of crust; open (extra.y), it lifts on its iridescent mother-of-pearl, which glows. Sand line at the bottom.
float4 draw_kelp_abalone(float2 c, float t, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.0, 0.75);
    float open = clamp(extra.y, 0.0, 1.0);
    // the foot (base) stays on the sand; the shell tilts up from its back edge as it opens
    float base = (length((p - float2(0.0, -0.5)) / float2(0.85, 0.16)) - 1.0) * 0.15;
    float ang = open * 0.55;
    float2 hq = p - float2(-0.82, -0.48);
    hq = float2(hq.x * cos(ang) + hq.y * sin(ang), -hq.x * sin(ang) + hq.y * cos(ang)) + float2(-0.82, -0.48);
    float shell = (length((hq - float2(0.0, -0.42)) / float2(0.88, 0.36)) - 1.0) * 0.3;
    shell = max(shell, -(hq.y + 0.46));
    // the inside, between the foot and the raised shell: the nacre
    float gapTop = -0.46 + open * 0.6 * smoothstep(-0.85, 0.85, p.x);
    float nacreD = max(max((length(p / float2(0.84, 2.0)) - 1.0) * 0.5, -(p.y + 0.5)), p.y - gapTop);   // the shell's oval
    float aa = fwidth(shell) + 1e-4;
    float inS = 1.0 - smoothstep(-aa, aa, shell);
    float inB = 1.0 - smoothstep(-aa, aa, base);
    float inN = (1.0 - smoothstep(-aa, aa, nacreD)) * step(0.01, open);
    float lum = dot(col.rgb, float3(0.33));
    // outside: rough, brick red and green-brown, growth ridges, a row of holes near the edge
    float ridge = 0.85 + 0.15 * sin(length(hq - float2(0.55, -0.4)) * 50.0);
    float3 rough = mix(float3(0.55, 0.25, 0.18), float3(0.35, 0.38, 0.25), smoothstep(0.3, 0.7, vnoise(hq * 6.0)));
    rough *= ridge * (0.75 + 0.35 * smoothstep(-0.8, -0.1, hq.y)) * (0.85 + 0.25 * vnoise(hq * 30.0));
    for (int i = 0; i < 6; i++) {
        float2 hc = float2(-0.55 + 0.2 * float(i), -0.2 + 0.08 * sin(float(i) * 0.9));
        rough *= 1.0 - 0.7 * (1.0 - smoothstep(0.025, 0.04, length(hq - hc)));
    }
    // the nacre: blue, green, pink shifting with the angle and the time, glowing when open
    float shift = hq.x * 3.0 + p.y * 5.0 + t * 0.3;
    float3 nacre = 0.6 + 0.4 * cos(6.2832 * (float3(0.0, 0.33, 0.67) + shift * 0.25));
    nacre = mix(float3(0.62, 0.66, 0.7), nacre * 0.75, 0.55) * (0.75 + 0.2 * glow) * (0.92 + 0.08 * sin(hq.x * 18.0 + p.y * 12.0 + vnoise(p * 6.0) * 3.0));
    float3 foot = float3(0.25, 0.22, 0.18) * (0.8 + 0.3 * vnoise(p * 20.0));
    float3 c3 = foot * inB;
    float a = inB;
    c3 = mix(c3, nacre, inN); a = max(a, inN);
    c3 = mix(c3, rough * lum, inS); a = max(a, inS);
    // the shell's inner rim shows its nacre when it lifts
    float rim = (1.0 - smoothstep(0.0, 0.04, -shell)) * step(hq.y, -0.38) * open * inS;
    c3 = mix(c3, nacre, rim);
    float2 hc = p - float2(0.35, -0.3);
    float halo = exp(-dot(hc, hc) * 5.0) * open * glow * 0.35 * (1.0 - a) * step(-0.5, p.y)
               * (1.0 - smoothstep(0.7, 1.0, abs(c.x))) * (1.0 - smoothstep(0.7, 1.0, abs(c.y)));
    c3 += float3(0.75, 0.9, 1.0) * halo;
    return float4(c3, max(a, halo * 0.6));
}

// A bull kelp float in place of the bottle: the round gas bulb bobbing at the surface, a band in the state's color
// (col) around it, its long blades trailing in the water.
float4 draw_kelp_bullkelp(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(0.9, 0.5);
    float bulb = length((p - float2(0.25, 0.04)) / float2(1.0, 0.85)) - 0.17;
    float stem = sd_seg(p, float2(0.08, 0.02), float2(-0.3, -0.06)) - 0.03;
    float blades = 1e3;
    for (int i = 0; i < 4; i++) {
        float fi = float(i);
        float2 a = float2(0.36, 0.06);
        float2 prev = a;
        for (int j = 1; j <= 5; j++) {
            float u = float(j) / 5.0;
            float2 q = a + float2(0.5 * u, (fi - 1.5) * 0.06 * u + sin(phase * 1.2 + fi + u * 4.0) * 0.04 * u);
            blades = min(blades, sd_seg(p, prev, q) - mix(0.02, 0.01, u));
            prev = q;
        }
    }
    float d = min(min(bulb, stem), blades);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float3 brown = float3(0.55, 0.42, 0.18);
    float3 c3 = brown * (0.7 + 0.45 * smoothstep(-0.15, 0.15, p.y));
    float band = (1.0 - smoothstep(0.02, 0.035, abs(p.x - 0.2))) * step(bulb, 0.0);
    c3 = mix(c3, col.rgb * (1.0 + glow * 0.6), band);
    c3 += float3(1.0, 0.95, 0.8) * pow(max(0.0, 1.0 - length((p - float2(0.2, 0.1)) / float2(0.06, 0.04))), 3.0) * 0.35;
    if (blades < min(bulb, stem)) c3 = brown * 0.85 * (0.85 + 0.15 * sin(p.x * 60.0));
    float halo = exp(-max(d, 0.0) * 20.0) * glow * 0.45 * (1.0 - a);
    return float4((c3 * a + col.rgb * halo) * col.a, (a + halo * 0.5) * col.a);
}

// A ship's wheel tangled in kelp, in place of the helm: wooden spokes and rim, golden-brown blades and gas bladders
// wound around it, the hub in the state's color (col). phase: how far it has turned.
float4 draw_kelp_helm(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * 1.05;
    float ca = cos(phase), sa = sin(phase);
    float2 q = float2(p.x * ca - p.y * sa, p.x * sa + p.y * ca);
    float r = length(q);
    float rim = abs(r - 0.6) - 0.06;
    float hubD = r - 0.15;
    float ang = atan2(q.y, q.x);
    float sector = 3.14159265 / 4.0;
    float a0 = floor(ang / sector + 0.5) * sector;
    float2 s = float2(q.x * cos(-a0) - q.y * sin(-a0), q.x * sin(-a0) + q.y * cos(-a0));
    float spoke = max(abs(s.y) - 0.035, max(0.15 - s.x, s.x - 0.68));
    float handle = sd_seg(s, float2(0.7, 0.0), float2(0.92, 0.0)) - 0.055;
    float wood = min(min(rim, spoke), handle);
    // kelp wound around the rim (in screen space, so it hangs down as the wheel turns), with bladders
    float kelp = 1e3, bl = 1e3;
    for (int i = 0; i < 5; i++) {
        float fi = float(i);
        float2 st = float2(cos(fi * 1.3 + 0.4), sin(fi * 1.3 + 0.4)) * 0.6;
        float2 prev = st;
        for (int j = 1; j <= 4; j++) {
            float u = float(j) / 4.0;
            float2 nq = st + float2(sin(fi * 2.0 + u * 3.0 + phase * 0.3) * 0.12 * u, -0.38 * u);
            kelp = min(kelp, sd_seg(p, prev, nq) - mix(0.04, 0.015, u));
            prev = nq;
        }
        bl = min(bl, length(p - st - float2(0.02, -0.08)) - 0.045);
    }
    float d = min(min(wood, hubD), min(kelp, bl));
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float3 woodC = float3(0.42, 0.28, 0.16) * (0.85 + 0.15 * sin(s.x * 40.0 + vnoise(s * 6.0) * 4.0));
    woodC *= 0.7 + 0.4 * smoothstep(-0.8, 0.8, c.y);
    float3 c3 = woodC;
    if (kelp < wood && kelp < hubD) c3 = float3(0.6, 0.45, 0.18) * (0.8 + 0.3 * smoothstep(-0.6, 0.6, p.y));
    if (bl < min(wood, kelp)) c3 = float3(0.7, 0.55, 0.25) * (0.8 + 0.4 * smoothstep(0.04, 0.0, -bl));
    if (hubD < 0.0) c3 = col.rgb * (0.8 + 0.4 * (1.0 - r / 0.15)) + col.rgb * glow * 0.5;
    c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.03, -d)) * 0.25;
    float halo = exp(-max(hubD, 0.0) * 12.0) * 0.3 * (1.0 - a);
    return float4((c3 * a + col.rgb * halo) * col.a, (a + halo * 0.4) * col.a);
}

// The diver-down flag on a little float, in place of the flag: the cloth in the state's color (col) with the white
// diagonal stripe, waving; the float and its line down to a weight on the sand.
float4 draw_kelp_diveflag(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(0.8, 1.0);
    float weight = sd_box(p - float2(-0.2, -0.86), float2(0.12, 0.06), 0.03);
    float line = sd_seg(p, float2(-0.2, -0.8), float2(-0.22, -0.1)) - 0.008;
    float buoy = length((p - float2(-0.22, -0.02)) / float2(1.0, 0.8)) - 0.11;
    float pole = sd_box(p - float2(-0.22, 0.4), float2(0.015, 0.4), 0.005);
    float k = clamp((p.x + 0.2) / 0.6, 0.0, 1.0);
    float w = sin(p.x * 7.0 - phase * 4.0) * 0.05 * k;
    float2 fq = float2(p.x, p.y - w) - float2(0.1, 0.58);
    float cloth = sd_box(fq, float2(0.3, 0.2), 0.01);
    float d = min(min(min(weight, line), min(buoy, pole)), cloth);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float3 c3;
    if (cloth <= min(min(weight, line), min(buoy, pole))) {
        c3 = col.rgb * (0.85 + 0.3 * cos(p.x * 7.0 - phase * 4.0) * k * 0.5);
        float diag = abs(fq.y + fq.x * 0.66) - 0.05;                         // the white stripe, top at the pole to the bottom of the fly
        c3 = mix(c3, float3(0.96), 1.0 - smoothstep(0.0, 0.01, diag));
        c3 += col.rgb * glow * 0.3;
    } else if (buoy < min(pole, min(line, weight))) {
        c3 = float3(0.95, 0.5, 0.15) * (0.7 + 0.5 * smoothstep(-0.1, 0.1, p.y + 0.02));
    } else if (weight < line) {
        c3 = float3(0.3, 0.3, 0.32);
    } else {
        c3 = float3(0.85, 0.85, 0.8) * 0.8;
    }
    c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.02, -d)) * 0.2;
    return float4(c3 * a * col.a, a * col.a);
}

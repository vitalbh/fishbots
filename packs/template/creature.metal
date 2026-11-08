// A creature: float4 draw_<name>(float2 c, float phase, float glow, float4 col, float4 extra)
//   c      -1…1 over the quad (its "extent" × its size), y up, facing +x (the app mirrors it)
//   phase  runs while it moves: legs, fins, wings
//   col    its color, lit by the hour
//   extra  y: a seed (0…1), w: 1 while it moves, 0 while it rests
// How it moves comes from "behavior" in pack.json (cross, pass, crawl, rest, glass, drift, school, skim, perch).
// A hermit crab: a spiral shell on its back, eyestalks, a big claw, legs that step while it walks.
float4 draw_template_creature(float2 c, float phase, float glow, float4 col, float4 extra) {
    const float2 E = float2(1.4, 1.0);
    float2 p = c * E;
    float moving = extra.w;
    float bob = 0.02 * sin(phase * 8.0) * moving;
    // shell: a cone spiral, point to the back and up
    float2 sc = float2(-0.35, -0.12 + bob);
    float2 sq = p - sc;
    float shell = (length(sq / float2(0.52, 0.47)) - 1.0) * 0.47;
    float tip = sd_tri(p, float2(-0.55, 0.18 + bob), float2(-1.2, 0.5 + bob), float2(-0.85, -0.12 + bob)) - 0.05;
    shell = smin_k(shell, tip, 0.12);
    shell = max(shell, -(p.y + 0.62));                                // flat opening on the bottom
    // body poking out at the front
    float body = (length((p - float2(0.3, -0.38 + bob)) / float2(0.42, 0.28)) - 1.0) * 0.28;
    // eyestalks
    float stalks = min(sd_seg(p, float2(0.5, -0.25 + bob), float2(0.62, 0.22 + bob)),
                       sd_seg(p, float2(0.58, -0.25 + bob), float2(0.82, 0.16 + bob))) - 0.03;
    float eyes = min(length(p - float2(0.62, 0.24 + bob)), length(p - float2(0.83, 0.18 + bob))) - 0.07;
    // the big claw: arm + pincer, opens a little while walking
    float snap = 0.08 * (0.5 + 0.5 * sin(phase * 3.0)) * moving;
    float arm = sd_seg(p, float2(0.55, -0.45 + bob), float2(0.85, -0.35 + bob)) - 0.07;
    float claw = (length((p - float2(1.0, -0.33 + bob)) / float2(0.2, 0.15)) - 1.0) * 0.15;
    float jaw = sd_seg(p, float2(1.05, -0.38 + bob), float2(1.3, -0.48 - snap + bob)) - 0.045;
    float fing = sd_seg(p, float2(1.08, -0.25 + bob), float2(1.32, -0.3 + bob)) - 0.05;
    float claws = min(min(arm, claw), min(jaw, fing));
    // legs: three pairs, stepping while it moves
    float legs = 1e3;
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        float st = sin(phase * 6.0 + fi * 2.1) * moving;
        float2 hip = float2(0.2 + fi * 0.2, -0.45 + bob);
        float2 knee = hip + float2(0.12 + 0.05 * st, -0.18 + 0.06 * max(st, 0.0));
        float2 foot = float2(hip.x + 0.18 + 0.1 * st, -0.97 + 0.05 * max(st, 0.0));
        legs = min(legs, min(sd_seg(p, hip, knee), sd_seg(p, knee, foot)) - (0.035 - 0.005 * fi));
    }
    float crab = min(min(body, stalks), min(claws, legs));
    float d = min(shell, min(crab, eyes));
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    if (a <= 0.0) return float4(0.0);

    float3 L = normalize(float3(-0.3, 0.8, 0.5));
    float3 c3;
    float2 bq = (p - float2(0.3, -0.38 + bob)) / float2(0.42, 0.28);
    if (shell <= min(crab, eyes)) {
        // shell: a pale version of the crab's color, spiral bands, lit as a ball
        float lum = dot(col.rgb, float3(0.3, 0.59, 0.11));
        float3 sh = mix(col.rgb, float3(0.95, 0.85, 0.68) * (0.6 + lum), 0.65);
        float2 q = sq / float2(0.52, 0.47);
        float3 n = normalize(float3(q, sqrt(max(0.02, 1.0 - dot(q, q)))));
        float lit = 0.5 + 0.65 * max(0.0, dot(n, L));
        float ang = atan2(sq.y, sq.x);
        float r = length(sq);
        float spiral = fract(log(max(r, 0.02)) * 2.2 - ang / 6.2832 + 0.3);
        float band = smoothstep(0.0, 0.08, spiral) * smoothstep(0.35, 0.25, spiral);
        c3 = sh * lit * (1.0 - 0.35 * band);
        c3 = mix(c3, sh * 0.5, smoothstep(0.1, 0.0, abs(spiral - 0.6) - 0.04) * 0.5);
        c3 += float3(1.0) * pow(max(0.0, dot(reflect(-L, n), float3(0, 0, 1))), 18.0) * 0.35;
        c3 *= 0.75 + 0.25 * vnoise(p * 10.0);
        c3 *= 0.7 + 0.3 * smoothstep(-0.65, -0.3, p.y);               // darker toward the sand
    } else if (eyes < crab) {
        c3 = float3(0.03);
        c3 += float3(0.9) * smoothstep(0.03, 0.0, length(p - float2(0.64, 0.27 + bob)) - 0.005);
        c3 += float3(0.9) * smoothstep(0.03, 0.0, length(p - float2(0.85, 0.21 + bob)) - 0.005);
    } else {
        // the crab: its color, countershaded, darker joints, pale claw tips
        c3 = col.rgb * (0.65 + 0.5 * smoothstep(-0.7, -0.2, p.y));
        if (body <= min(claws, legs)) {
            float3 n = normalize(float3(bq, sqrt(max(0.02, 1.0 - dot(bq, bq)))));
            c3 = col.rgb * (0.55 + 0.6 * max(0.0, dot(n, L)));
            c3 *= 1.0 - 0.25 * smoothstep(0.03, 0.0, abs(fract(p.x * 7.0) - 0.5) - 0.4);   // segments
        }
        if (claws <= min(body, legs)) {
            float2 q = (p - float2(1.0, -0.33 + bob)) / float2(0.25, 0.2);
            float3 n = normalize(float3(q, sqrt(max(0.02, 1.0 - dot(q, q)))));
            c3 = col.rgb * (0.55 + 0.6 * max(0.0, dot(n, L)));
            c3 = mix(c3, float3(0.95, 0.9, 0.8), smoothstep(1.15, 1.32, p.x) * 0.6);
            c3 += 0.25 * pow(max(0.0, dot(reflect(-L, n), float3(0, 0, 1))), 16.0);
        }
        c3 *= 0.9 + 0.2 * vnoise(p * 14.0);
        c3 = mix(c3, col.rgb * 0.4, smoothstep(-0.02, 0.0, d) * 0.6);   // darker outline
    }
    c3 += col.rgb * glow * 0.45;
    return float4(c3 * a, a);
}

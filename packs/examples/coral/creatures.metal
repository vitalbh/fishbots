// Blue-green chromis: tiny, deep-bodied, forked tail, in a school. col is their color.
float4 draw_coral_chromis(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.6, 1.0);
    p.y -= sin(phase * 2.0 - p.x * 3.0) * 0.05 * smoothstep(0.3, -0.9, p.x);
    float body = (length((p - float2(0.15, 0.0)) / float2(0.75, 0.42)) - 1.0) * 0.42;
    float tail = sd_tri(p, float2(-0.5, 0.0), float2(-1.05, 0.38), float2(-1.05, -0.38));
    tail = max(tail, -sd_tri(p, float2(-0.8, 0.0), float2(-1.1, 0.22), float2(-1.1, -0.22)));
    float d = min(body, tail - 0.01);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float3 c3 = col.rgb * (0.65 + 0.5 * smoothstep(-0.4, 0.4, p.y));
    c3 += float3(0.6, 0.9, 1.0) * pow(max(0.0, 1.0 - length((p - float2(0.2, 0.18)) / float2(0.5, 0.12))), 2.0) * 0.35;
    c3 = mix(c3, float3(0.02), 1.0 - smoothstep(0.06, 0.09, length(p - float2(0.65, 0.08))));
    return float4(c3 * a * col.a, a * col.a);
}

// A blue tang crossing the reef now and then: an oval blue body with the black "palette" mark and a yellow tail.
float4 draw_coral_tang(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.4, 1.0);
    p.y -= sin(phase - p.x * 2.4) * 0.05 * smoothstep(0.3, -1.0, p.x);
    float body = (length((p - float2(0.1, 0.0)) / float2(0.78, 0.5)) - 1.0) * 0.5;
    float dors = max((length((p - float2(0.0, 0.32)) / float2(0.7, 0.2)) - 1.0) * 0.2, -(p.y - 0.3));
    float anal = max((length((p - float2(-0.1, -0.3)) / float2(0.55, 0.16)) - 1.0) * 0.16, p.y + 0.28);
    float2 tq = p - float2(-0.68, sin(phase - 1.0) * 0.04);
    float tail = max(sd_tri(tq, float2(0.05, 0.0), float2(-0.38, 0.34), float2(-0.38, -0.34)),
                     -(length((tq - float2(-0.5, 0.0)) / float2(0.2, 0.2)) - 1.0) * 0.2) - 0.01;
    float d = min(min(body, tail), min(dors, anal));
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float3 blue = float3(0.15, 0.35, 0.95), black = float3(0.03, 0.04, 0.08), yellow = float3(1.0, 0.82, 0.15);
    float3 c3 = blue;
    // the "palette": a thick black band from behind the eye along the back, curving down to the tail, with a
    // blue window in its middle
    float yb = 0.2 - 0.45 * (p.x - 0.35) * (p.x - 0.35);
    float band = abs(p.y - yb) - mix(0.04, 0.11, smoothstep(0.45, -0.1, p.x));
    float window = length((p - float2(-0.12, 0.13)) / float2(0.22, 0.05)) - 1.0;
    float mark = max(band, -window * 0.05) ;
    c3 = mix(c3, black, (1.0 - smoothstep(0.0, 0.012, mark)) * step(body, 0.0) * step(-0.62, p.x) * step(p.x, 0.5));
    if (tail < min(body, min(dors, anal))) c3 = yellow * (0.85 + 0.15 * cos(atan2(tq.y, -tq.x) * 20.0));
    if (min(dors, anal) < min(body, tail)) c3 = mix(blue * 0.8, black, smoothstep(-0.03, -0.005, min(dors, anal)));
    c3 *= 0.7 + 0.45 * smoothstep(-0.5, 0.5, p.y);
    c3 = mix(c3, float3(0.02), 1.0 - smoothstep(0.045, 0.06, length(p - float2(0.62, 0.12))));
    c3 = mix(c3, float3(1.0), 1.0 - smoothstep(0.008, 0.016, length(p - float2(0.63, 0.135))));
    c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.025, -d)) * 0.25;
    return float4(c3 * a * col.a, a * col.a);
}


// A masked butterflyfish: a tall, round, flat body with a small pointed snout, golden yellow with thin orange-red
// stripes running up and down, a blue-gray patch around the eye, the fins running along the back and belly edged
// in dark, a yellow tail. They go in pairs around the corals.
float4 draw_coral_butterfly(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.1, 1.0);
    p.y -= sin(phase - p.x * 2.0) * 0.03 * smoothstep(0.2, -0.7, p.x);
    float body = (length((p - float2(0.05, 0.0)) / float2(0.55, 0.62)) - 1.0) * 0.55;
    float snout = sd_tri(p, float2(0.45, 0.12), float2(0.45, -0.12), float2(0.78, -0.02)) - 0.03;
    body = smin_k(body, snout, 0.08);
    // the soft dorsal and anal fins: a rounded plate behind, squaring the silhouette off toward the tail
    float plate = sd_box(p - float2(-0.22, 0.0), float2(0.3, 0.6 - 0.1 * smoothstep(-0.1, -0.5, p.x)), 0.22);
    plate = max(plate, p.x - 0.1);
    float fins = plate;
    float2 tq = p - float2(-0.48, sin(phase - 1.0) * 0.04);
    float tail = max(sd_tri(tq, float2(0.08, 0.0), float2(-0.28, 0.3), float2(-0.28, -0.3)), -tq.x - 0.26) - 0.01;
    float pect = (length((p - float2(0.15, -0.18 + 0.03 * sin(phase * 2.0))) / float2(0.13, 0.06)) - 1.0) * 0.06;
    float d = min(min(body, fins), min(tail, pect));
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float3 yellow = float3(1.0, 0.78, 0.1), orange = float3(0.95, 0.4, 0.12), mask = float3(0.35, 0.45, 0.6);
    float3 c3;
    if (body <= min(fins, tail)) {
        float2 b = (p - float2(0.05, 0.0)) / float2(0.55, 0.62);
        float3 n = normalize(float3(b, sqrt(max(0.02, 1.0 - dot(b, b)))));
        c3 = yellow * (0.65 + 0.45 * max(0.0, dot(n, normalize(float3(-0.3, 0.8, 0.5)))));
        // thin stripes, a little wavy, fading out toward the head
        float st = abs(fract(p.x * 7.0 + 0.12 * sin(p.y * 5.0)) - 0.5);
        c3 = mix(c3, orange, (1.0 - smoothstep(0.07, 0.14, st)) * smoothstep(0.3, 0.1, p.x) * 0.85);
        // the mask around the eye
        float2 eye = float2(0.4, 0.06);
        float m = length((p - eye - float2(-0.02, 0.0)) / float2(0.12, 0.22));
        c3 = mix(c3, mask, 1.0 - smoothstep(0.85, 1.05, m));
        float re = length(p - eye);
        c3 = mix(c3, float3(0.03), 1.0 - smoothstep(0.035, 0.045, re));
        c3 = mix(c3, float3(1.0), 1.0 - smoothstep(0.006, 0.012, length(p - eye - float2(0.01, 0.012))));
        c3 += float3(1.0) * pow(max(0.0, dot(reflect(-normalize(float3(-0.3, 0.8, 0.5)), n), float3(0, 0, 1))), 16.0) * 0.25;
    } else {
        c3 = yellow * 0.9;
        float st = abs(fract(p.x * 7.0 + 0.12 * sin(p.y * 5.0)) - 0.5);
        c3 = mix(c3, orange, (1.0 - smoothstep(0.07, 0.14, st)) * 0.7 * step(tail, 0.0) * 0.0 + (1.0 - smoothstep(0.07, 0.14, st)) * 0.6 * (1.0 - step(tail, min(fins, pect))));
        c3 = mix(c3, float3(0.25, 0.2, 0.1), smoothstep(-0.03, -0.008, d) * 0.8 * step(-0.45, p.x));   // dark rim
        if (pect < min(body, min(fins, tail))) { c3 = yellow * 1.1; a *= 0.6; }
        a *= 0.95;
    }
    c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.02, -d)) * 0.2;
    return float4(c3 * a * col.a, a * col.a);
}

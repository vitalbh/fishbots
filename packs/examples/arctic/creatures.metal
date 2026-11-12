// Polar cod: small, silver, a long body and a pale belly, in schools under the ice.
float4 draw_arctic_cod(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.8, 1.0);
    p.y -= sin(phase * 2.0 - p.x * 3.0) * 0.05 * smoothstep(0.4, -1.2, p.x);
    float body = (length((p - float2(0.1, 0.0)) / float2(0.95, 0.3)) - 1.0) * 0.3;
    float tail = sd_tri(p, float2(-0.75, 0.0), float2(-1.25, 0.28), float2(-1.25, -0.28)) - 0.01;
    // two small dorsal fins and one below, as a cod has
    float fins = min(sd_tri(p, float2(0.35, 0.24), float2(-0.05, 0.22), float2(0.0, 0.42)),
                     min(sd_tri(p, float2(-0.2, 0.2), float2(-0.6, 0.12), float2(-0.5, 0.36)),
                         sd_tri(p, float2(-0.1, -0.24), float2(-0.55, -0.14), float2(-0.45, -0.38)))) - 0.012;
    float d = min(body, min(tail, fins));
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float3 c3 = mix(col.rgb * 1.2 + 0.1, col.rgb * 0.75, smoothstep(-0.2, 0.25, p.y));     // pale belly, darker back
    c3 = fish_round(c3, (p - float2(0.1, 0.0)) / float2(0.95, 0.3), body);
    c3 += float3(1.0) * pow(max(0.0, 1.0 - length((p - float2(0.2, 0.05)) / float2(0.7, 0.06))), 3.0) * 0.4 * step(body, 0.0);   // silver line
    if (body > 0.0) { c3 = col.rgb * 0.7; a *= 0.8; }
    c3 = fish_eye(c3, p, float2(0.8, 0.06), 0.085, col.rgb, 0.0);
    return float4(c3 * a * col.a, a * col.a);
}

// A seal swimming across: a sleek gray body, darker spots, front flippers held in, the hind flippers sculling.
float4 draw_arctic_seal(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.6, 0.8);
    float sw = sin(phase * 1.4);
    p.y -= sw * 0.05 * smoothstep(0.3, -1.3, p.x);
    float body = (length((p - float2(0.0, 0.0)) / float2(1.15, 0.3 * mix(0.55, 1.0, smoothstep(-1.1, 0.3, p.x)))) - 1.0) * 0.3;
    float head = (length((p - float2(1.05, 0.06)) / float2(0.3, 0.22)) - 1.0) * 0.22;
    body = smin_k(body, head, 0.1);
    float2 hq = p - float2(-1.2, sw * 0.08);
    float hind = min(sd_tri(hq, float2(0.1, 0.0), float2(-0.3, 0.2 + sw * 0.05), float2(-0.25, 0.0)),
                     sd_tri(hq, float2(0.1, 0.0), float2(-0.3, -0.2 + sw * 0.05), float2(-0.25, 0.0))) - 0.02;
    float front = (length((p - float2(0.45, -0.25)) / float2(0.18, 0.06)) - 1.0) * 0.06;
    float d = min(min(body, hind), front);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float yn = p.y / 0.3;
    float3 c3 = mix(col.rgb * 1.25 + 0.05, col.rgb * 0.7, smoothstep(-0.5, 0.4, yn));
    // dark rings and spots, scattered (a harbor seal's coat)
    float2 sg = p * float2(5.0, 8.0);
    float2 sid = floor(sg);
    float2 so = fract(sg) - 0.5 - (float2(hash21(sid), hash21(sid + 5.0)) - 0.5) * 0.4;
    float spot = (1.0 - smoothstep(0.12, 0.2, length(so / float2(1.0, 1.3)))) * step(0.5, hash21(sid + 2.0));
    c3 = mix(c3, col.rgb * 0.45, spot * 0.6 * step(-0.3, yn));
    c3 += float3(0.8, 0.9, 1.0) * (1.0 - smoothstep(0.0, 0.03, -body)) * smoothstep(0.0, 0.9, yn) * 0.25;
    // a dark round eye, nostrils, whiskers
    c3 = mix(c3, float3(0.02), 1.0 - smoothstep(0.035, 0.05, length(p - float2(1.12, 0.12))));
    c3 = mix(c3, float3(1.0), 1.0 - smoothstep(0.006, 0.014, length(p - float2(1.13, 0.135))));
    float wh = abs(p.y - 0.0 + (p.x - 1.3) * 0.2) - 0.004;
    c3 = mix(c3, float3(0.85), (1.0 - smoothstep(0.0, 0.006, wh)) * step(1.25, p.x) * step(p.x, 1.48) * 0.7);
    c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.025, -d)) * 0.25;
    return float4(c3 * a * col.a, a * col.a);
}

// A narwhal, far away and rare: a mottled gray body and its long spiral tusk.
float4 draw_arctic_narwhal(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(2.0, 0.7);
    float flex = sin(phase * 0.5);
    p.y -= flex * 0.06 * smoothstep(0.2, -1.6, p.x);
    float body = (length((p - float2(-0.1, 0.0)) / float2(1.3, 0.3 * mix(0.35, 1.0, smoothstep(-1.4, 0.2, p.x)))) - 1.0) * 0.3;
    float2 fq = p - float2(-1.45, 0.0);
    float flukes = min(sd_tri(fq, float2(0.1, 0.0), float2(-0.3, 0.22 + flex * 0.05), float2(-0.25, 0.0)),
                       sd_tri(fq, float2(0.1, 0.0), float2(-0.3, -0.2 + flex * 0.05), float2(-0.25, 0.0))) - 0.02;
    float2 t0 = float2(1.15, 0.04), t1 = float2(1.95, 0.1), pa = p - t0, ba = t1 - t0;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    float tusk = length(pa - ba * h) - mix(0.028, 0.006, h);
    float d = min(min(body, flukes), tusk);
    float a = 1.0 - smoothstep(-0.02, 0.04, d);                                          // soft: it's far away
    float3 c3 = col.rgb * (0.75 + 0.4 * smoothstep(0.2, -0.3, p.y));
    c3 = mix(c3, col.rgb * 0.5, smoothstep(0.55, 0.7, vnoise(p * float2(5.0, 9.0))) * 0.5);
    if (tusk < body) c3 = float3(0.9, 0.88, 0.8) * (0.8 + 0.2 * step(0.5, fract(h * 14.0)));   // the spiral
    float aw = a * 0.65;
    return float4(c3 * aw, aw);
}

// The polar cod as a fish kind (a fish's quad is 1.25 × 0.8): the schools under the ice, and a session can be one.
float4 draw_arctic_cod_fish(float2 c, float phase, float glow, float4 col, float4 extra) {
    float4 o = draw_arctic_cod(c * float2(1.25 / 1.8, 0.8), phase, glow, col, extra);
    return float4(o.rgb + col.rgb * glow * 0.45 * o.a, o.a);
}

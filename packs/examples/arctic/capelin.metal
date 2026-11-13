// Capelin: a slim silver smelt of the cold seas, in big schools. An olive-green back, a bright silver flank with a
// darker line between the two, a white belly, a big eye, a small dorsal fin at the middle of the back and a tiny
// adipose fin behind it, a long low anal fin and a forked tail. col tints the back and the silver. The quad is
// 1.5 × 0.55.
float4 draw_arctic_capelin(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.5, 0.55);
    p.y -= sin(phase - p.x * 2.2) * (0.008 + 0.06 * smoothstep(0.3, -1.2, p.x));
    float cx = 0.14, rx = 1.2, ry = 0.2;
    float ryx = ry * (1.0 - 0.5 * smoothstep(cx + 0.1, cx - rx, p.x)) * (1.0 - 0.3 * smoothstep(cx + 0.55, cx + rx, p.x));
    float2 b = (p - float2(cx, 0.0)) / float2(rx, ryx);
    float body = (length(b) - 1.0) * ryx;
    body = min(body, sd_seg(p, float2(-0.6, 0.0), float2(-1.0, 0.0)) - 0.04);          // the tail stock
    float2 tq = p - float2(cx - rx * 0.93, sin(phase - 1.0) * 0.04);
    float tail = sd_tri(tq, float2(0.08, 0.0), float2(-0.32, 0.3), float2(-0.32, -0.3));
    tail = max(tail, -sd_tri(tq, float2(-0.12, 0.0), float2(-0.4, 0.2), float2(-0.4, -0.2))) - 0.01;
    float dors = sd_tri(p, float2(0.2, ryx * 0.85), float2(-0.12, ryx * 0.8), float2(-0.04, ryx + 0.17)) - 0.01;
    float adip = (length((p - float2(-0.58, ryx * 0.98)) / float2(0.07, 0.04)) - 1.0) * 0.04;
    float anal = sd_tri(p, float2(-0.28, -ryx * 0.8), float2(-0.8, -ryx * 0.7), float2(-0.66, -ryx - 0.13)) - 0.01;
    float pelv = sd_tri(p, float2(0.12, -ryx * 0.85), float2(-0.06, -ryx * 0.8), float2(-0.08, -ryx - 0.1)) - 0.008;
    float pa = -0.45 + sin(phase * 1.7) * 0.25;
    float2 pq = p - float2(0.78, -0.07);
    pq = float2(pq.x * cos(pa) - pq.y * sin(pa), pq.x * sin(pa) + pq.y * cos(pa));
    float pect = (length((pq - float2(-0.13, 0.0)) / float2(0.15, 0.045)) - 1.0) * 0.045;
    float fins = min(min(min(tail, dors), min(adip, anal)), pelv);
    float d = min(min(body, fins), pect);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    if (a <= 0.0 && glow <= 0.0) return float4(0.0);
    float3 silver = mix(col.rgb, float3(0.93, 0.97, 1.0), 0.6) * 1.12;
    float3 olive = mix(col.rgb * 0.45, float3(0.2, 0.3, 0.14), 0.6);
    float3 c3;
    float al = a;
    if (body < 0.0) {
        float yn = b.y;
        c3 = mix(silver, olive, smoothstep(0.22, 0.38, yn));
        c3 = mix(c3, float3(1.0), smoothstep(-0.45, -0.9, yn) * 0.5);                                   // white belly
        c3 = mix(c3, olive * 0.45, (1.0 - smoothstep(0.05, 0.13, abs(yn - 0.27))) * 0.75 * smoothstep(0.75, 0.55, p.x));   // the line between
        c3 += float3(0.9, 1.0, 1.0) * (1.0 - smoothstep(0.0, 0.22, abs(yn + 0.02))) * 0.22 * (0.7 + 0.3 * sin(p.x * 40.0));  // the flank's shine
        c3 = fish_round(c3 * 1.06, b, body);
        c3 *= 1.0 - 0.28 * (1.0 - smoothstep(0.0, 0.02, abs(length((p - float2(0.84, 0.0)) / float2(0.13, 0.2)) - 1.0) * 0.13)) * step(0.84, p.x);   // gill cover
        c3 = mix(c3, olive * 0.3, 1.0 - smoothstep(0.006, 0.016, sd_seg(p, float2(1.3, -0.03), float2(1.17, -0.045))));     // mouth
        c3 = fish_eye(c3, p, float2(1.02, 0.02), 0.07, mix(col.rgb, float3(0.9, 0.95, 1.0), 0.5), step(1.5, extra.w));
    } else {
        c3 = mix(olive * 1.6, silver, 0.45);
        al *= 0.6;
    }
    if (pect < 0.0 && body < 0.0) c3 = mix(c3, silver * 0.8, 0.5);
    c3 += col.rgb * glow * 0.45;
    al *= col.a;
    float edge = 1.0 - smoothstep(0.6, 1.0, max(abs(c.x), abs(c.y)));
    float halo = glow * exp(-max(d, 0.0) * 12.0) * edge * (1.0 - a) * col.a;
    return float4(c3 * al + col.rgb * halo, min(al + halo * 0.55, 1.0));
}

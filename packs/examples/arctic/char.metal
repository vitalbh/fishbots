// Arctic char: a trout-like fish, dark green-gray back with pale spots, an orange-pink belly (bright in the
// spawning ones), and the lower fins edged in white. col tints the back; three varieties by the pattern (extra.y):
// 0 silver (sea-run), 1 spawning (red belly), 2 dark lake form.
float4 draw_arctic_char(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.25, 0.8);
    int variety = int(extra.y + 0.5) % 3;
    bool asleep = extra.w > 1.5;
    p.y -= sin(phase - p.x * 2.4) * (0.012 + 0.07 * (1.0 - smoothstep(-0.9, 0.3, p.x)));
    float cx = 0.08, rx = 0.82, ry = 0.25;
    float rear = smoothstep(cx + 0.2, cx - rx, p.x);
    float ryx = ry * (1.0 - 0.5 * rear);
    float2 b = (p - float2(cx, 0.0)) / float2(rx, ryx);
    float body = (length(b) - 1.0) * min(rx, ryx);
    float bx = cx - rx * 0.9;
    float2 tq = p - float2(bx, sin(phase - 1.0) * 0.05);
    float tail = sd_tri(tq, float2(0.05, 0.0), float2(-0.32, 0.24), float2(-0.32, -0.24));
    tail = max(tail, -sd_tri(tq, float2(-0.24, 0.0), float2(-0.36, 0.12), float2(-0.36, -0.12))) - 0.012;
    float dors = sd_tri(p, float2(cx + 0.05, ryx * 0.9), float2(cx - 0.28, ryx * 0.8), float2(cx - 0.2, ryx + 0.14)) - 0.01;
    float adip = (length((p - float2(cx - rx * 0.62, ryx * 0.95)) / float2(0.05, 0.035)) - 1.0) * 0.035;     // the little adipose fin
    float pelv = sd_tri(p, float2(cx - 0.05, -ryx * 0.8), float2(cx - 0.2, -ryx * 0.75), float2(cx - 0.22, -ryx - 0.1)) - 0.01;
    float anal = sd_tri(p, float2(cx - rx * 0.5, -ryx * 0.7), float2(cx - rx * 0.68, -ryx * 0.55), float2(cx - rx * 0.7, -ryx - 0.08)) - 0.008;
    float pang = -0.5 + sin(phase * 1.7) * 0.35;
    float2 pq = p - float2(cx + rx * 0.45, -ry * 0.45);
    pq = float2(pq.x * cos(pang) - pq.y * sin(pang), pq.x * sin(pang) + pq.y * cos(pang));
    float pect = (length((pq - float2(-0.11, 0.0)) / float2(0.13, 0.05)) - 1.0) * 0.05;
    float lower = min(min(pelv, anal), pect);
    float fins = min(min(tail, dors), min(adip, lower));
    float d = min(body, fins);
    float aa = fwidth(d) + 1e-4;
    float a = (1.0 - smoothstep(-aa, aa, d)) * col.a;
    if (a <= 0.0 && glow <= 0.0) return float4(0.0);
    float3 back = variety == 2 ? col.rgb * 0.35 : mix(col.rgb, float3(0.3, 0.38, 0.35), 0.5) * 0.8;
    float3 belly = variety == 1 ? float3(0.95, 0.32, 0.2) : variety == 2 ? float3(0.85, 0.5, 0.3) : float3(0.95, 0.72, 0.6);
    if (variety == 0) back = mix(back, float3(0.7, 0.75, 0.78), 0.4);                     // sea-run: silvery
    float yn = p.y / max(ryx, 0.02);
    float3 c3;
    if (body <= fins || (pect < 0.0 && body < 0.0)) {
        c3 = mix(belly, back, smoothstep(-0.35, 0.25, yn));
        // pale spots on the back and flanks
        float2 sg = p * float2(10.0, 12.0);
        float2 sid = floor(sg);
        float sp = (1.0 - smoothstep(0.1, 0.18, length(fract(sg) - 0.5 - (float2(hash21(sid), hash21(sid + 3.0)) - 0.5) * 0.4)))
                 * step(0.55, hash21(sid + 7.0)) * smoothstep(-0.3, 0.1, yn);
        c3 = mix(c3, mix(float3(0.95, 0.9, 0.8), belly, variety == 1 ? 0.5 : 0.15), sp * 0.7);
        float3 n = normalize(float3(b, sqrt(max(0.02, 1.0 - dot(b, b)))));
        c3 *= 0.55 + 0.6 * max(0.0, dot(n, normalize(float3(-0.3, 0.8, 0.5))));
        c3 += float3(0.85, 0.92, 1.0) * (1.0 - smoothstep(0.0, 0.03, -body)) * smoothstep(0.0, 0.8, yn) * 0.25;
        c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.03, -body)) * smoothstep(0.0, -0.8, yn) * 0.3;
        // gill cover and eye
        float garc = abs(length((p - float2(cx + rx * 0.62, -0.01)) * float2(1.0, 0.8)) - 0.12);
        c3 *= 1.0 - (1.0 - smoothstep(0.004, 0.014, garc)) * step(p.x, cx + rx * 0.62) * 0.25;
        float2 eye = float2(cx + rx * 0.8, ry * 0.15);
        float re = length(p - eye);
        if (asleep) c3 = mix(c3, float3(0.05), (1.0 - smoothstep(0.0, 0.01, abs(p.y - eye.y) - 0.005)) * step(re, 0.04));
        else {
            c3 = mix(c3, float3(0.85, 0.8, 0.6), 1.0 - smoothstep(0.035, 0.045, re));
            c3 = mix(c3, float3(0.03), 1.0 - smoothstep(0.02, 0.028, re));
            c3 = mix(c3, float3(1.0), 1.0 - smoothstep(0.005, 0.01, length(p - eye - float2(0.008, 0.01))));
        }
        if (pect < 0.0) c3 = mix(c3, belly, 0.5);
    } else {
        // fins: the lower ones the belly's color with a bright white leading edge; the others the back's
        bool isLower = lower <= min(tail, min(dors, adip));
        c3 = isLower ? belly * 0.9 : back * 0.9;
        if (isLower) c3 = mix(c3, float3(1.0), (1.0 - smoothstep(0.0, 0.02, -d)) * step(0.0, p.x - (cx - rx)) * 0.85);
        float2 rr = p - float2(bx + 0.05, 0.0);
        c3 *= 0.88 + 0.12 * cos(atan2(rr.y, -rr.x) * 24.0);
        a *= 0.9;
    }
    c3 += belly * glow * 0.35;
    float edge = 1.0 - smoothstep(0.6, 1.0, max(abs(c.x), abs(c.y)));
    float halo = glow * exp(-max(d, 0.0) * 12.0) * edge;
    return float4(c3 * a + belly * halo * (1.0 - a), a + halo * (1.0 - a) * 0.55);
}

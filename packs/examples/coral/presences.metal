// A wheel of colorful shells around a starfish, hanging on the glass in place of the helm: it turns while busy (slowly
// otherwise), and the starfish in the middle takes the state's color (col), like the helm's hub.
float4 draw_coral_shellwheel(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c;
    float busy = abs(extra.w - 1.0) < 0.5 ? 1.0 : 0.0;
    float ang = phase * (busy > 0.5 ? 0.8 : 0.1);
    float2 q = float2(p.x * cos(ang) - p.y * sin(ang), p.x * sin(ang) + p.y * cos(ang));
    float r = length(q), th = atan2(q.y, q.x);
    // the ring the shells sit on
    float ring = abs(r - 0.62) - 0.04;
    float d = ring;
    float3 c3 = float3(0.85, 0.75, 0.55);
    float which = -1.0;
    // eight scallop shells around it, each its own bright color, ribs fanning toward the outside
    for (int i = 0; i < 8; i++) {
        float a0 = float(i) / 8.0 * 6.2832;
        float2 ctr = float2(cos(a0), sin(a0)) * 0.66;
        float2 s = q - ctr;
        // rotate into the shell's frame: its hinge points to the center
        float2 u = float2(dot(s, float2(cos(a0), sin(a0))), dot(s, float2(-sin(a0), cos(a0))));
        float2 v = u + float2(0.13, 0.0);
        float fan = max(length(v) - 0.3, abs(atan2(v.y, v.x)) - 0.8);
        if (fan < d) { d = fan; which = float(i); }
    }
    // the starfish in the middle: five soft arms
    float sa = atan2(q.y, q.x);
    float star = length(q) - (0.12 + 0.13 * pow(0.5 + 0.5 * cos(5.0 * sa), 2.0));
    float aa = fwidth(min(d, star)) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, min(d, star));
    if (star < d) {
        c3 = col.rgb * (0.85 + 0.35 * (1.0 - length(q) / 0.25)) + col.rgb * glow * 0.5;
        c3 = mix(c3, c3 * 1.3 + 0.1, (1.0 - smoothstep(0.03, 0.05, length(fract(q * 18.0) - 0.5))) * 0.4);
    } else if (which >= 0.0) {
        float3 colors[8] = { float3(1.0, 0.45, 0.55), float3(1.0, 0.75, 0.25), float3(0.45, 0.85, 0.6), float3(0.4, 0.7, 1.0),
                             float3(0.8, 0.5, 1.0), float3(1.0, 0.55, 0.3), float3(0.35, 0.85, 0.85), float3(1.0, 0.9, 0.5) };
        float3 shell = colors[int(which + 0.5) % 8];
        float a0 = which / 8.0 * 6.2832;
        float2 s = q - float2(cos(a0), sin(a0)) * 0.66;
        float2 v = float2(dot(s, float2(cos(a0), sin(a0))), dot(s, float2(-sin(a0), cos(a0)))) + float2(0.13, 0.0);
        float ribs = 0.5 + 0.5 * cos(atan2(v.y, v.x) * 11.0);
        c3 = shell * (0.7 + 0.3 * ribs) * (0.75 + 0.35 * smoothstep(0.0, 0.3, length(v)));
    } else {
        c3 *= 0.8 + 0.2 * sin(th * 30.0);
    }
    c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.02, -min(d, star))) * 0.25;
    return float4(c3 * a, a);
}

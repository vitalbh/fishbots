// An expedition compass on the glass, in place of the helm: a brass ring with the compass rose, its needle swinging
// around while busy and settling north otherwise; the jewel in the middle takes the state's color (col).
float4 draw_arctic_compass(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c;
    float r = length(p);
    float busy = abs(extra.w - 1.0) < 0.5 ? 1.0 : 0.0;
    float ring = abs(r - 0.82) - 0.1;
    float face = r - 0.72;
    float d = min(ring, face);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float th = atan2(p.y, p.x);
    float3 brass = float3(0.78, 0.6, 0.3) * (0.7 + 0.4 * smoothstep(-0.8, 0.8, p.y - p.x * 0.3));
    float3 paper = float3(0.92, 0.88, 0.78) * (0.85 + 0.15 * vnoise(p * 8.0));
    float3 c3 = ring < 0.0 ? brass * (0.85 + 0.15 * step(0.5, fract(th / 6.2832 * 32.0))) : paper;
    if (face < 0.0) {
        // the rose: eight points, the north one red; ticks around the edge
        float ang = th - 1.5708;
        float star = r - 0.62 * pow(0.5 + 0.5 * cos(4.0 * th), 6.0) - 0.06 * pow(0.5 + 0.5 * cos(4.0 * th + 0.785), 6.0) * 6.0;
        if (star < 0.0) c3 = mix(float3(0.25, 0.3, 0.4), float3(0.55, 0.6, 0.7), step(0.0, sin(th * 8.0)));
        c3 = mix(c3, float3(0.2), (1.0 - smoothstep(0.0, 0.01, abs(r - 0.66) - 0.004)) * step(0.7, fract(th / 6.2832 * 36.0)));
        // the needle
        float na = busy > 0.5 ? phase * 2.4 : 1.5708 + sin(phase * 0.7) * 0.08;
        float2 q = float2(p.x * cos(-na) - p.y * sin(-na), p.x * sin(-na) + p.y * cos(-na));
        float needle = abs(q.y) - 0.07 * (1.0 - abs(q.x) / 0.6);
        needle = max(needle, abs(q.x) - 0.6);
        if (needle < 0.0) c3 = q.x > 0.0 ? float3(0.85, 0.15, 0.12) : float3(0.9, 0.9, 0.92);
        if (r < 0.08) c3 = col.rgb * (0.9 + 0.4 * (1.0 - r / 0.08)) + col.rgb * glow * 0.6;
        c3 += float3(1.0) * pow(max(0.0, 1.0 - length((p - float2(-0.3, 0.35)) / float2(0.3, 0.15))), 3.0) * 0.25;   // the glass
    }
    c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.03, -d)) * 0.3;
    return float4(c3 * a, a);
}

// An orca, in place of the shark: black above, white below, the white patch behind the eye, a tall dorsal fin.
float4 draw_arctic_orca(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.6, 0.7);
    float sw = sin(phase * 2.0);
    p.y -= sw * 0.05 * smoothstep(0.2, -1.3, p.x);
    float body = (length((p - float2(0.0, -0.02)) / float2(1.25, 0.33 * mix(0.4, 1.0, smoothstep(-1.2, 0.2, p.x)))) - 1.0) * 0.3;
    float2 fq = p - float2(-1.28, sw * 0.07);
    float flukes = min(sd_tri(fq, float2(0.1, 0.0), float2(-0.3, 0.2), float2(-0.24, 0.0)),
                       sd_tri(fq, float2(0.1, 0.0), float2(-0.3, -0.2), float2(-0.24, 0.0))) - 0.02;
    float dorsal = sd_tri(p, float2(-0.25, 0.24), float2(0.15, 0.27), float2(-0.12, 0.85)) - 0.015;
    float pect = (length((p - float2(0.55, -0.32)) / float2(0.22, 0.08)) - 1.0) * 0.08;
    float d = min(min(body, flukes), min(dorsal, pect));
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float3 black = float3(0.04, 0.05, 0.07), white = float3(0.92, 0.94, 0.96);
    float yn = p.y + 0.05 * sin(p.x * 3.0);
    float3 c3 = mix(white, black, smoothstep(-0.12, -0.06, yn + 0.1 * smoothstep(0.6, 1.2, p.x)));
    // the eye patch and the gray saddle behind the fin
    float patch = length((p - float2(0.8, 0.1)) / float2(0.2, 0.07)) - 1.0;
    c3 = mix(c3, white, 1.0 - smoothstep(-0.1, 0.1, patch));
    float saddle = length((p - float2(-0.4, 0.18)) / float2(0.3, 0.08)) - 1.0;
    c3 = mix(c3, float3(0.45, 0.48, 0.52), (1.0 - smoothstep(-0.2, 0.2, saddle)) * 0.6);
    if (dorsal < body || flukes < body || pect < body) c3 = black;
    c3 += float3(0.6, 0.75, 0.9) * (1.0 - smoothstep(0.0, 0.03, -d)) * smoothstep(0.0, 0.3, p.y) * 0.3;
    c3 = mix(c3, float3(0.0), 1.0 - smoothstep(0.025, 0.035, length(p - float2(0.98, 0.05))));
    c3 += col.rgb * glow * 0.3;
    float edge = 1.0 - smoothstep(0.6, 1.0, max(abs(c.x), abs(c.y)));
    float halo = glow * exp(-max(d, 0.0) * 10.0) * edge;
    return float4(c3 * a + col.rgb * halo * (1.0 - a), a + halo * (1.0 - a) * 0.5);
}

// A message frozen in a cube of ice, floating, in place of the bottle: a rolled paper inside, glowing with the state.
float4 draw_arctic_ice_message(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(0.9, 0.5);
    float cube = sd_box(p - float2(0.0, 0.0), float2(0.42, 0.22), 0.05);
    float paper = sd_box(p - float2(0.0, -0.01), float2(0.24, 0.05), 0.04);
    float aa = fwidth(cube) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, cube);
    float3 ice = mix(float3(0.6, 0.8, 0.92), float3(0.92, 0.97, 1.0), smoothstep(-0.2, 0.2, p.y));
    ice *= 0.9 + 0.12 * vnoise(p * 10.0);
    float inPaper = 1.0 - smoothstep(-0.01, 0.02, paper);
    float3 c3 = mix(ice, float3(0.95, 0.88, 0.7) * (0.85 + 0.5 * glow) + col.rgb * 0.15, inPaper * 0.8);
    c3 = mix(c3, float3(1.0), (1.0 - smoothstep(0.0, 0.03, -cube)) * 0.5);                // frosty edges
    c3 += float3(1.0) * pow(max(0.0, 1.0 - length((p - float2(-0.2, 0.12)) / float2(0.15, 0.05))), 3.0) * 0.5;
    return float4(c3 * a * 0.92, a * 0.9);
}

// An expedition flag planted in a block of ice: a wooden pole, the cloth in the state's color (col) waving.
float4 draw_arctic_flag(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(0.8, 1.0);
    float block = sd_box(p - float2(-0.05, -0.75), float2(0.45, 0.17), 0.05);
    float pole = sd_box(p - float2(-0.3, 0.0), float2(0.02, 0.75), 0.01);
    float k = clamp((p.x + 0.28) / 0.75, 0.0, 1.0);
    float w = sin(p.x * 6.0 - phase * 4.0) * 0.06 * k;
    float cloth = sd_box(float2(p.x, p.y - w) - float2(0.1, 0.5), float2(0.38, 0.2), 0.01);
    float d = min(min(block, pole), cloth);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float3 c3;
    if (cloth < min(block, pole)) {
        float slope = cos(p.x * 6.0 - phase * 4.0) * k;
        c3 = col.rgb * (0.8 + 0.35 * -slope * 0.5);
        c3 = mix(c3, float3(0.95), (1.0 - smoothstep(0.0, 0.02, abs(p.y - w - 0.5) - 0.025)) * 0.6);   // a white stripe
    } else if (pole < block) {
        c3 = float3(0.5, 0.36, 0.22);
    } else {
        c3 = mix(float3(0.65, 0.82, 0.92), float3(0.95, 0.98, 1.0), smoothstep(-0.9, -0.6, p.y)) * (0.9 + 0.1 * vnoise(p * 9.0));
    }
    c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.02, -d)) * 0.25;
    return float4(c3 * a, a);
}

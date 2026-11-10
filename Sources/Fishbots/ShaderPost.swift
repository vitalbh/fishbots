/// The glow: bloom down, blur and add.
let shaderPost = #"""
struct PostOut { float4 position [[position]]; float2 uv; };

vertex PostOut post_vertex(uint vid [[vertex_id]]) {
    float2 p[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
    PostOut o;
    o.position = float4(p[vid], 0, 1);
    o.uv = float2((p[vid].x + 1.0) * 0.5, 1.0 - (p[vid].y + 1.0) * 0.5);
    return o;
}

// to a quarter of the size: 4 bilinear taps (16 texels)
fragment float4 bloom_down(PostOut in [[stage_in]], texture2d<float> src [[texture(0)]], sampler s [[sampler(0)]]) {
    float2 px = 1.0 / float2(src.get_width(), src.get_height());
    float4 c = src.sample(s, in.uv + px * float2(-1, -1)) + src.sample(s, in.uv + px * float2(1, -1))
             + src.sample(s, in.uv + px * float2(-1, 1)) + src.sample(s, in.uv + px * float2(1, 1));
    return float4(c.rgb * 0.25, 1.0);
}

// 9-tap gaussian in 5 bilinear samples, along `dir` (in texels)
fragment float4 bloom_blur(PostOut in [[stage_in]], texture2d<float> src [[texture(0)]], sampler s [[sampler(0)]],
                           constant float2& dir [[buffer(0)]]) {
    float2 px = dir / float2(src.get_width(), src.get_height());
    float3 c = src.sample(s, in.uv).rgb * 0.2270270270;
    c += (src.sample(s, in.uv + px * 1.3846153846).rgb + src.sample(s, in.uv - px * 1.3846153846).rgb) * 0.3162162162;
    c += (src.sample(s, in.uv + px * 3.2307692308).rgb + src.sample(s, in.uv - px * 3.2307692308).rgb) * 0.0702702703;
    return float4(c, 1.0);
}

// The last pass, added on top of the image (one + one): the bloom, and the front glass you look through:
// a diagonal sheen, specks of dust, and mist with drops in the top corners.
fragment float4 bloom_add(PostOut in [[stage_in]], texture2d<float> bloom [[texture(0)]], sampler s [[sampler(0)]],
                          constant float& strength [[buffer(0)]], constant Uniforms& u [[buffer(1)]]) {
    float3 c = strength > 0.001 ? bloom.sample(s, in.uv).rgb * strength : float3(0.0);
    float2 uv = float2(in.uv.x, 1.0 - in.uv.y);
    float2 world = uv * u.res;
    float aspect = u.res.x / u.res.y;
    float sheen = exp(-pow((uv.x * 0.7 + uv.y - 1.05) / 0.07, 2.0)) * 0.035 + exp(-pow((uv.x * 0.7 + uv.y - 1.2) / 0.025, 2.0)) * 0.022;
    float2 cell = floor(world / 7.0);
    float speck = step(0.9982, hash21(cell)) * (1.0 - smoothstep(0.08, 0.2, length(fract(world / 7.0) - 0.5))) * 0.16;
    float glass = sheen + speck;
    float corner = max(1.0 - smoothstep(0.0, 0.22, length(float2(uv.x * aspect, uv.y) - float2(0.0, 1.0))),
                       1.0 - smoothstep(0.0, 0.22, length(float2((1.0 - uv.x) * aspect, uv.y) - float2(0.0, 1.0))));
    if (corner > 0.0) {
        float mist = corner * (0.45 + 0.55 * vnoise(world * 0.03)) * 0.1;
        float drop = corner * step(0.93, hash21(floor(world / 11.0) + 7.0)) * (1.0 - smoothstep(0.18, 0.3, length(fract(world / 11.0) - 0.5))) * 0.2;
        glass += mist + drop;
    }
    c += float3(0.85, 0.92, 0.96) * glass * (0.55 + 0.45 * u.light);
    return float4(c, 0.0);
}
"""#

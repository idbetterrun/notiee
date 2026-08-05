#include <metal_stdlib>
using namespace metal;

struct AuroraUniforms {
    float time;
    float amplitude;
    float blend;
    float padding;
    float2 resolution;
    float2 resolutionPadding;
    float4 color0;
    float4 color1;
    float4 color2;
};

struct AuroraRasterizerData {
    float4 position [[position]];
};

vertex AuroraRasterizerData newUIPreviewAuroraVertex(uint vertexID [[vertex_id]]) {
    constexpr float2 positions[3] = {
        float2(-1.0, -1.0),
        float2(3.0, -1.0),
        float2(-1.0, 3.0)
    };

    AuroraRasterizerData output;
    output.position = float4(positions[vertexID], 0.0, 1.0);
    return output;
}

float3 auroraPermute(float3 value) {
    return fmod(((value * 34.0) + 1.0) * value, 289.0);
}

// Ported from the React Bits Aurora simplex-noise fragment shader.
float auroraSimplexNoise(float2 value) {
    constexpr float4 constants = float4(
        0.211324865405187,
        0.366025403784439,
        -0.577350269189626,
        0.024390243902439
    );

    float2 cell = floor(value + dot(value, constants.yy));
    float2 local = value - cell + dot(cell, constants.xx);
    float2 offset = local.x > local.y ? float2(1.0, 0.0) : float2(0.0, 1.0);
    float4 offsets = float4(local, local) + constants.xxzz;
    offsets.xy -= offset;
    cell = fmod(cell, 289.0);

    float3 permutation = auroraPermute(
        auroraPermute(cell.y + float3(0.0, offset.y, 1.0)) +
        cell.x + float3(0.0, offset.x, 1.0)
    );

    float3 attenuation = max(
        0.5 - float3(
            dot(local, local),
            dot(offsets.xy, offsets.xy),
            dot(offsets.zw, offsets.zw)
        ),
        float3(0.0)
    );
    attenuation *= attenuation;
    attenuation *= attenuation;

    float3 x = 2.0 * fract(permutation * constants.www) - 1.0;
    float3 h = abs(x) - 0.5;
    float3 ox = floor(x + 0.5);
    float3 a0 = x - ox;
    attenuation *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);

    float3 gradient;
    gradient.x = a0.x * local.x + h.x * local.y;
    gradient.yz = a0.yz * offsets.xz + h.yz * offsets.yw;
    return 130.0 * dot(attenuation, gradient);
}

fragment float4 newUIPreviewAuroraFragment(
    AuroraRasterizerData input [[stage_in]],
    constant AuroraUniforms &uniforms [[buffer(0)]]
) {
    float2 resolution = max(uniforms.resolution, float2(1.0));
    float2 uv = input.position.xy / resolution;

    float3 rampColor = uv.x <= 0.5
        ? mix(uniforms.color0.rgb, uniforms.color1.rgb, uv.x * 2.0)
        : mix(uniforms.color1.rgb, uniforms.color2.rgb, (uv.x - 0.5) * 2.0);

    // Metal's viewport origin is top-left; invert Y to preserve the source shader's shape.
    float verticalPosition = 1.0 - uv.y;
    float height = auroraSimplexNoise(float2(
        uv.x * 2.0 + uniforms.time * 0.1,
        uniforms.time * 0.25
    )) * 0.5 * uniforms.amplitude;
    height = exp(height);
    height = verticalPosition * 2.0 - height + 0.2;
    float intensity = 0.6 * height;
    float alpha = smoothstep(
        0.20 - uniforms.blend * 0.5,
        0.20 + uniforms.blend * 0.5,
        intensity
    );

    // Keep the effect bounded to the Hero area even when the host view is taller.
    float bottomFade = 1.0 - smoothstep(0.60, 0.98, uv.y);
    alpha = clamp(alpha * bottomFade * 0.26, 0.0, 0.26);
    float3 color = rampColor * clamp(intensity, 0.25, 1.0);
    return float4(color * alpha, alpha);
}

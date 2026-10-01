// Hologram Tool - pixel shader
//
// writes opaque pixels and full depth on purpose. real alpha blending would
// reveal internal details like eyeballs and teeth inside a head, since almost
// no Source character model is a single manifold surface.
// blending against a framebuffer copy means depth has already discarded everything
// except for the frontmost surface, so the model reads transparent without
// actually being transparent.

#include "common_ps_fxc.h"

sampler BaseTexture : register(s0);
sampler LineTexture : register(s1);
sampler DistortTexture : register(s2);
sampler FrameTexture : register(s3);

float4 C0 : register(c0); // xyz: tint, w: tint amount
float4 C1 : register(c1); // x: thin scale, y: thick scale, z: thick strength, w: thick scroll
float4 C2 : register(c2); // xyz: entity color, w: glitch amount
float4 C3 : register(c3); // x: rim strength, y: opacity, z: noise scale, w: noise scroll

static const float RIM_BIAS = 0.5f;

struct PS_INPUT {
	float2 uv : TEXCOORD0;
	float3 world_pos : TEXCOORD1;
	float3 normal : TEXCOORD2;
	float3 screenUVW : TEXCOORD3;
};

float4 main(PS_INPUT frag) : COLOR {
	float2 screenUV = frag.screenUVW.xy / frag.screenUVW.z;
	float3 behind = tex2D(FrameTexture, screenUV).rgb;

	float3 color = tex2D(BaseTexture, frag.uv).rgb * C2.rgb;

	float gray = dot(color, float3(0.33333f, 0.33333f, 0.33333f));
	color = lerp(color, gray * C0.rgb, C0.w);

	float3 normal = normalize(frag.normal);
	float3 view = normalize(cEyePos - frag.world_pos);
	float rim = 1.0f - saturate(abs(dot(view, normal)) + RIM_BIAS);
	color += rim * C3.x;

	float planeFade = length(normal.xy);

	float3 thin = tex2D(LineTexture, float2(0.5f, frag.world_pos.z * C1.x)).rgb;
	float thick = tex2D(LineTexture, float2(0.5f, frag.world_pos.z * C1.y + C1.w)).a;
	color += (thin + thick * C1.z) * planeFade;

	float2 noiseUV = float2(frag.world_pos.x + frag.world_pos.y, frag.world_pos.z);
	float glitch = tex2D(DistortTexture, noiseUV * C3.z + float2(0.0f, C3.w)).r * C2.w;

	color = lerp(behind, color, C3.y * (1.0f - glitch));

	return float4(color, 1.0f);
}

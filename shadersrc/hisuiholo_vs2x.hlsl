// Hologram Tool - vertex shader
//
// passes model UV, world position + normal, and unprojected screen position to
// the pixel shader.
//
// $vertexnormal is unsigned UBYTE4 in 0-255 range. the shader reads it raw
// and normalizes it, which makes dot(view,normal) depend on which side of an
// entity you stand on rather than on the actual surface

#define COMPRESSED_VERTS 1

#include "common_vs_fxc.h"

struct VS_INPUT {
	float4 vPos : POSITION;
	float4 vNormal : NORMAL0;
	float2 vTexCoord : TEXCOORD0;
};

struct VS_OUTPUT {
	float4 proj_pos : POSITION;
	float2 uv : TEXCOORD0;
	float3 world_pos : TEXCOORD1;
	float3 normal : TEXCOORD2;
	float3 screenUVW : TEXCOORD3;
};

VS_OUTPUT main(VS_INPUT vert) {
	float3 model_normal;
	DecompressVertex_Normal(vert.vNormal, model_normal);
	float3 world_pos;
	float3 world_normal;
	SkinPositionAndNormal(0, vert.vPos, model_normal, 0, 0, world_pos, world_normal);

	VS_OUTPUT output = (VS_OUTPUT)0;
	output.proj_pos = mul(float4(world_pos, 1), cViewProj);
	output.uv = vert.vTexCoord;
	output.world_pos = world_pos;
	output.normal = world_normal;
	output.screenUVW.z = output.proj_pos.w;
	output.screenUVW.xy = output.proj_pos.xy * float2(0.5f, -0.5f)
		+ float2(0.5f, 0.5f) * output.proj_pos.w;

	return output;
}

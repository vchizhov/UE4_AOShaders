// based on the paper for Scalable Ambient Obscurance
// http://graphics.cs.williams.edu/papers/SAOHPG12/

/**
 \file SAO_AO.pix
 \author Morgan McGuire and Michael Mara, NVIDIA Research

 Reference implementation of the Scalable Ambient Obscurance (SAO) screen-space ambient obscurance algorithm. 
 
 The optimized algorithmic structure of SAO was published in McGuire, Mara, and Luebke, Scalable Ambient Obscurance,
 <i>HPG</i> 2012, and was developed at NVIDIA with support from Louis Bavoil.

 The mathematical ideas of AlchemyAO were first described in McGuire, Osman, Bukowski, and Hennessy, The 
 Alchemy Screen-Space Ambient Obscurance Algorithm, <i>HPG</i> 2011 and were developed at 
 Vicarious Visions.  
 
 DX11 HLSL port by Leonardo Zide of Treyarch

 <hr>

  Open Source under the "BSD" license: http://www.opensource.org/licenses/bsd-license.php

  Copyright (c) 2011-2012, NVIDIA
  All rights reserved.

  Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

  Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
  Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

  */
 
 /**
	Adapted for Unreal 4.15 as a custom expression by Vassillen Chizhov
	
	Note: Many parts are different due to Unreal's GBuffer, a custom gbuffer would require the modification of the engine, read more at:
	https://forums.unrealengine.com/showthread.php?27766-Odessey-Creating-my-own-G-Buffer-in-UE4
	I am aware of the light screen tremor that occurs - I believe it's due to Unreal's jittering for temporal AA, in SceneView.h there's TemporalAAProjectionJitter, but as far as I am aware it is not used and
	the jitter is directly encoded into the projection matrix
	I am also aware that the sampling pattern presented in the paper, isn't necessarily correct, since it uses a screen space spiral sampling pattern which favors some pixels over others
	a solution to some overshadowing can be achieved by scaling the spiral pattern accoring to the angle between the forward view vector and the pixel's normal
	A solution to banding artifacts can be achieved by applying a Bayer matrix or some randomness to each new sample's radius
	Possible improvements also include a progressive or temporal scheme for the AO, buffer down&upsampling, depth mipmapping(the Gbuffer would need to be mopdified), a separable blur scheme
	
	The View structure's definition can be seen in SceneView.h in the Source\Runtime\Engine\Public
	The Pixel Parameters structure can be seen from the hlsl generated for this custom expression in the material editor,
	strangely searching for FMaterialPixelParameters in the source code didn't yield anything
	The SceneDepthTexture used for accessing the depth buffer can be seein from SceneRenderTargetParameters.h from Source\Runtime\Renderer\Public
	
 */

// normal reconstruction using a forward difference scheme
float4 SvPosition = Parameters.SvPosition;
float DeviceZ = LookupDeviceZ(SvPositionToBufferUV(SvPosition + float4(0, 0, 0, 0)));

float3 pixelColor = float3(1.0,1.0,1.0);
if(Diffuse==1.0)
{
	pixelColor = CalcSceneColor(UV);
}

// if we're too far - return no occlusion, as to avoid occlusion of the dome
if(DeviceZ<0.0001) return pixelColor;
float DeviceZRight = LookupDeviceZ(SvPositionToBufferUV(SvPosition + float4(1, 0, 0, 0)));
float DeviceZDown = LookupDeviceZ(SvPositionToBufferUV(SvPosition + float4(0, 1, 0, 0)));
// calculate the right and down pixels viewspace positions to use them for normal reconstruction
float3 Mid =	SvPositionToTranslatedWorld(float4(SvPosition.xy + float2(0, 0), DeviceZ, 1));
float3 Right =	SvPositionToTranslatedWorld(float4(SvPosition.xy + float2(1, 0), DeviceZRight, 1)) - Mid;
float3 Down =	SvPositionToTranslatedWorld(float4(SvPosition.xy + float2(0, 1), DeviceZDown, 1)) - Mid;
float3 normal = mul(normalize(cross(Right, Down)), (float3x3)View.TranslatedWorldToCameraView);//normalize(cross(Right, Down));//

float dp = ConvertFromDeviceZ(DeviceZ);

// DEBUG:
// test normals
//return dot(normal,float3(0.0,0.0,-1.0))>0.0? float3(0.0, 1.0,0.0) : float3(1.0,0.0, 0.0);

// calculate the sampling radius in screen space coordinates
float2 ssDiskRadius = View.ViewToClip._m11*View.BufferSizeAndInvSize.xy*ProjScale*radius/ConvertFromDeviceZ(DeviceZ);//View.BufferSizeAndInvSize.zw

// DEBUG:
// test range
//if(ssDiskRadius.x>View.ViewSizeAndInvSize.x*0.5 || ssDiskRadius.y>View.ViewSizeAndInvSize.y*0.5) return float3(1.0,0.0,0.0);
//if(ssDiskRadius==0.0) return float3(1.0,0.0,0.0);

// we'll accumulate the ao per pixel sum here
float sum = 0.0;
// the squared world space radius
float radius2 = radius*radius;

// normalize the intensity
float r6 = 1.0/(radius2*radius2*radius2);
float intenistyDivR6 = intensity*r6;


#define PI 3.14159265359
// random function from  three js's shader chunks
const float a = 12.9898, b = 78.233, c = 43758.5453;
float dt = dot( 0.5*UV+0.5, float2( a,b ) ), sn = fmod( dt, PI );
float spinAngle = frac(sin(sn) * c);

// used to fix the banding artifacts cause by the sampling pattern
dt = dot( 0.5*UV.yx+0.5, float2( a,b ) ), sn = fmod( dt, PI );
float ssRRandBandingFix = frac(sin(sn) * c);
//float ssRRandBandingFix = (2.0*frac(sin(dot(Mid, float3(12.9898, 78.233, 21.317))) * float3(43758.5453, 21383.21227, 20431.20563))-1.0).r;

// accumulate samples
for(float i=0;i<numSamples;++i)
{
	// generate a new sample in a spiral pattern
	float alpha = (i+0.5)/float(numSamples);
	float angle = alpha * 29.0 * PI + spinAngle;
	//fixes the banding artifacts caused by the sampling pattern
	float2 ssR = clamp(ssRRandBandingFix, BandingLow, 1.0)*alpha*ssDiskRadius;
	float2 unitOffset = float2(cos(angle), sin(angle));
	// project that sample into world space
	float3 samplePos = SvPositionToTranslatedWorld(float4(SvPosition.xy+ssR*unitOffset, LookupDeviceZ(SvPositionToBufferUV(SvPosition+float4(ssR*unitOffset,0.0,0.0))), 1));
	//calculate occlusion - 2nd function from the paper
	float3 v = mul(samplePos-Mid, (float3x3)View.TranslatedWorldToCameraView);//samplePos-Mid;//
	float vv = dot(v, v);
	float vn = dot(v, normal);
	float f = max(radius2 - vv, 0.0);
	// DEBUG:
	// test normal dot product and range
	//if(vn>0.0 && f>0.0) return float3(0.0,1.0,1.0);
	f = f * f * f * max((vn - bias) / (0.01 + vv), 0.0);
	sum+=f;
}
sum*=r6;
float A = max(0.0, 1.0 - sum * intensity  * 5.0 / float(numSamples));

// Disable/comment out in case you're using a device that doesn't support a shader feature level including bit operations or automatic derivatives
// Bilateral box-filter over a quad for free, respecting depth edges
// (the difference that this makes is subtle)
if (abs(ddx(dp)) < 0.02) {
	A -= ddx(A) * ((int(SvPosition.x) & 1) - 0.5);
}
if (abs(ddy(dp)) < 0.02) {
	A -= ddy(A) * ((int(SvPosition.y) & 1) - 0.5);
}

return pixelColor*(A*AmbientContribution+(1.0-AmbientContribution));
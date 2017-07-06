// Adapted  by Vassillen Chizhov for Unreal 4.15 from Marc Sunet's master thesis  "Ambient Occlusion on Mobile:An Empirical Comparison"

// Poisson disk points generated with the poisson disk generator tool from here http://www.coderhaus.com/?p=11
// 32 points in the radius 1 circle centered at 0,0
float samplePoints[] =
{
-0.3630694f, -0.5271481f,
-0.6859986f, -0.4584265f,
-0.01027072f, -0.3763485f,
-0.4506904f, -0.03754795f,
-0.0769558f, -0.7530776f,
-0.3442115f, -0.8345784f,
0.12272f, 0.005348092f,
0.3439883f, -0.5269225f,
-0.2183697f, -0.1966636f,
0.1901135f, -0.8037189f,
-0.2069084f, 0.0680032f,
-0.4419276f, 0.2461057f,
0.4953459f, -0.7713191f,
-0.8814662f, -0.2394287f,
-0.7061955f, 0.1065362f,
-0.1361099f, 0.3243283f,
-0.8359504f, 0.5124443f,
-0.218542f, 0.6575691f,
-0.5478165f, 0.6188826f,
0.3872536f, 0.03683177f,
0.2517199f, 0.4944566f,
0.286204f, -0.2659682f,
-0.2377582f, 0.9289695f,
0.154254f, 0.9542935f,
-0.618693f, -0.762839f,
0.8146991f, -0.383564f,
0.860028f, -0.02248338f,
0.8059393f, 0.2953026f,
0.5547388f, 0.3716165f,
0.5901503f, -0.246587f,
0.5621385f, 0.6621177f,
-0.9806842f, 0.05667607f
};

// normal reconstruction using a forward difference scheme
float4 SvPosition = Parameters.SvPosition;
float DeviceZ = LookupDeviceZ(SvPositionToBufferUV(SvPosition + float4(0, 0, 0, 0)));

float3 pixelColor = float3(1.0,1.0,1.0);
if(Diffuse==1.0)
{
	pixelColor = CalcSceneColor(SvPositionToBufferUV(SvPosition));
}

// if we're too far - return no occlusion, as to avoid occlusion of the dome
if(DeviceZ<0.0001) return pixelColor;
float DeviceZRight = LookupDeviceZ(SvPositionToBufferUV(SvPosition + float4(1, 0, 0, 0)));
float DeviceZDown = LookupDeviceZ(SvPositionToBufferUV(SvPosition + float4(0, 1, 0, 0)));
// calculate the right and down pixels viewspace positions to use them for normal reconstruction
float3 Mid =	SvPositionToTranslatedWorld(float4(SvPosition.xy + float2(0, 0), DeviceZ, 1));
float dp = ConvertFromDeviceZ(DeviceZ);
//float3 Right =	SvPositionToTranslatedWorld(float4(SvPosition.xy + float2(1, 0), DeviceZRight, 1)) - Mid;
//float3 Down =	SvPositionToTranslatedWorld(float4(SvPosition.xy + float2(0, 1), DeviceZDown, 1)) - Mid;
float3 normal = -normalize(cross(ddy(Mid), ddx(Mid)));//mul(normalize(cross(Right, Down)), (float3x3)View.TranslatedWorldToCameraView);//normalize(cross(Right, Down));//
// DEBUG:
// test normals
//return mul(normal*float3(1.0,1.0,1.0), (float3x3)View.TranslatedWorldToCameraView);

#define PI 3.14159265359
// random function from  three js's shader chunks
const float a = 12.9898, b = 78.233, c = 43758.5453;
float dt = dot( 0.5*UV+0.5, float2( a,b ) ), sn = fmod( dt, PI );
float r1 = frac(sin(sn) * c);
dt = dot( 0.5*UV.yx+0.5, float2( a+PI,b/2.0 ) ), sn = fmod( dt, PI );

float2 rvec = float2(r1, frac(sin(sn) * c/8.0));
//float2 rvec =  (2.0*frac(sin(dot(Mid, float3(12.9898, 78.233, 21.317))) * float3(43758.5453, 21383.21227, 20431.20563))-1.0).rg;

float AO = 0.0;
for (int i = 0; i < 32; ++i)
{
	// calculate sample position and normal
	float2 qfrag = SvPosition.xy + reflect(radius*View.BufferSizeAndInvSize.xy*float2(samplePoints[2*i],samplePoints[2*i+1]), rvec) / dp;
	float qdepth = LookupDeviceZ(SvPositionToBufferUV(float4(qfrag,0.0,0.0)));
	float3 qMid = SvPositionToTranslatedWorld(float4(qfrag, DeviceZ, 1));
	float3 qnormal = -normalize(cross(ddy(qMid), ddx(qMid)));
	float diff = max(0.0, (ConvertFromDeviceZ(qdepth)-dp)/radiusWorld);
	// Avoid self-shadowing
	float w = 1.0 -  dot(normal, qnormal);
	// Penalise large depth discontinuities
	float odiff = 1.0 + diff;
	w *= smoothstep(0.0, 1.0, odiff*odiff);
	AO += intensity*w * (1.0 - diff);
}
AO = 1.0-AO/32.0;

// Disable/comment out in case you're using a device that doesn't support a shader feature level including bit operations or automatic derivatives
// Bilateral box-filter over a quad for free, respecting depth edges
// (the difference that this makes is subtle)
if (abs(ddx(dp)) < 0.02) {
	AO -= ddx(AO) * ((int(SvPosition.x) & 1) - 0.5);
}
if (abs(ddy(dp)) < 0.02) {
	AO -= ddy(AO) * ((int(SvPosition.y) & 1) - 0.5);
}

return (AO*AmbientContribution+1.0-AmbientContribution)*pixelColor;
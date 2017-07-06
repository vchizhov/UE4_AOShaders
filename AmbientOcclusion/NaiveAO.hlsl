/**
	@author: Vassillen Chizhov
	a naive AO algorithm made by me - the AO's pretty fake, but it's pretty cheap too
*/

float maxDist = 1.0;
// don't shade the pixel if it's too far away
float deviceZ = LookupDeviceZ(UV);
float4 colorAndDepth = CalcSceneColorAndDepth( UV );
float Depth = colorAndDepth.w; 
if(deviceZ<0.001) return float3(1.0,1.0,1.0)*(Diffuse?colorAndDepth.rgb : 1.0);
float Depth1;
float ao = 0.0;
for(int i=0;i<numSamples;++i)
{
	// just look at the difference in depth - this is pretty fake, but there's a sopecific nice effect
	Depth1 = CalcSceneDepth(UV + numSamples*float2(View.BufferSizeAndInvSize.z, 0.0)); 
	ao += saturate(1.0-(Depth1-Depth)/maxDist);
	Depth1 = CalcSceneDepth(UV - numSamples*float2(View.BufferSizeAndInvSize.z, 0.0)); 
	ao += saturate((Depth1-Depth)/maxDist);
	Depth1 = CalcSceneDepth(UV + numSamples*float2(0.0, View.BufferSizeAndInvSize.w)); 
	ao += saturate((Depth1-Depth)/maxDist);
	Depth1 = CalcSceneDepth(UV - numSamples*float2(0.0, View.BufferSizeAndInvSize.w));
	ao += saturate((Depth1-Depth)/maxDist);
}
ao/=(4.0*numSamples);
return (ambientContribution*float3(ao,ao,ao) + 1.0-ambientContribution)*(Diffuse?colorAndDepth.rgb : 1.0);
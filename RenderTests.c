#include "Render.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
int main(void) {
 float input[2048], output[2049];
 for(int i=0;i<2048;i++) input[i]= i%2 ? -0.8f : 0.8f;
 AudioBufferList in={1,{{2,sizeof(input),input}}}, out={1,{{2,sizeof(input),output}}};
 AudioTimeStamp time={0}; IVRender *s=iv_create(); assert(s);
 output[2048]=123.0f;
 iv_gain(s,0.25f);
 for(int b=0;b<8;b++) assert(iv_render(0,&time,&in,&time,&out,&time,s)==0);
 assert(fabsf(output[2046]-0.2f)<0.0001f); assert(fabsf(output[2047]+0.2f)<0.0001f);
 assert(iv_callbacks(s)==8); assert(fabsf(iv_input(s)-0.8f)<0.0001f); assert(output[2048]==123.0f);
 iv_gain(s,0); for(int b=0;b<8;b++) iv_render(0,&time,&in,&time,&out,&time,s);
 assert(fabsf(output[2046])<0.0001f);
 input[0]=NAN; iv_render(0,&time,&in,&time,&out,&time,s); assert(isfinite(output[0]));
 iv_gain(s,12); for(int b=0;b<8;b++) iv_render(0,&time,&in,&time,&out,&time,s);
 assert(fabsf(output[2046]-0.8f)<0.0001f);
 iv_destroy(s);
 puts("PASS: stereo gain, mute, ramp, no amplification, NaN handling, bounds and counters");
 return 0;
}

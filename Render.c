#include "Render.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>
struct IVRender { _Atomic float target, inputPeak, outputPeak; _Atomic uint64_t callbacks; float current; };
IVRender *iv_create(void) { IVRender *s = calloc(1,sizeof(*s)); if(s) { atomic_init(&s->target,0); atomic_init(&s->inputPeak,0); atomic_init(&s->outputPeak,0); atomic_init(&s->callbacks,0); } return s; }
void iv_destroy(IVRender *s) { free(s); }
void iv_gain(IVRender *s, float g) { atomic_store_explicit(&s->target,fmaxf(0,fminf(g,1)),memory_order_relaxed); }
uint64_t iv_callbacks(IVRender *s) { return atomic_load_explicit(&s->callbacks,memory_order_relaxed); }
float iv_input(IVRender *s) { return atomic_load_explicit(&s->inputPeak,memory_order_relaxed); }
float iv_output(IVRender *s) { return atomic_load_explicit(&s->outputPeak,memory_order_relaxed); }
// Float32 PCM, interleaved or planar. No allocation, logging or locks on the audio thread.
OSStatus iv_render(AudioObjectID d, const AudioTimeStamp *n,const AudioBufferList *in,const AudioTimeStamp *it,AudioBufferList *out,const AudioTimeStamp *ot,void *ctx) {
 IVRender *s=ctx; float target=atomic_load_explicit(&s->target,memory_order_relaxed), p=0,q=0;
 uint32_t frames=UINT32_MAX;
 for(uint32_t b=0;b<out->mNumberBuffers;b++) { AudioBuffer *o=&out->mBuffers[b]; if(o->mData) memset(o->mData,0,o->mDataByteSize); if(o->mNumberChannels) { uint32_t f=o->mDataByteSize/(4*o->mNumberChannels); if(f<frames) frames=f; } }
 for(uint32_t b=0;b<in->mNumberBuffers;b++) { const AudioBuffer *i=&in->mBuffers[b]; if(i->mNumberChannels) { uint32_t f=i->mDataByteSize/(4*i->mNumberChannels); if(f<frames) frames=f; } }
 if(frames==UINT32_MAX || frames>65536) frames=0;
 for(uint32_t f=0;f<frames;f++) {
  s->current += (target-s->current)*0.004f;
  uint32_t channel=0;
  for(uint32_t ob=0;ob<out->mNumberBuffers;ob++) { AudioBuffer *o=&out->mBuffers[ob]; float *dst=o->mData;
   for(uint32_t oc=0;oc<o->mNumberChannels;oc++,channel++) {
    float sample=0; uint32_t base=0;
    for(uint32_t ib=0;ib<in->mNumberBuffers;ib++) { const AudioBuffer *i=&in->mBuffers[ib]; if(channel>=base && channel<base+i->mNumberChannels && i->mData) { sample=((const float*)i->mData)[f*i->mNumberChannels+channel-base]; break; } base+=i->mNumberChannels; }
    if(!isfinite(sample)) sample=0; float value=sample*s->current;
    if(dst) dst[f*o->mNumberChannels+oc]=value;
    p=fmaxf(p,fabsf(sample)); q=fmaxf(q,fabsf(value));
   }
  }
 }
 atomic_store_explicit(&s->inputPeak,p,memory_order_relaxed); atomic_store_explicit(&s->outputPeak,q,memory_order_relaxed); atomic_fetch_add_explicit(&s->callbacks,1,memory_order_relaxed);
 return noErr;
}

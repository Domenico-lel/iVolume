#include <CoreAudio/CoreAudio.h>
#include <stdint.h>
typedef struct IVRender IVRender;
IVRender * _Nullable iv_create(void);
void iv_destroy(IVRender * _Nonnull s);
void iv_gain(IVRender * _Nonnull s, float gain);
uint64_t iv_callbacks(IVRender * _Nonnull s);
float iv_input(IVRender * _Nonnull s);
float iv_output(IVRender * _Nonnull s);
OSStatus iv_render(AudioObjectID device, const AudioTimeStamp * _Nonnull now,
 const AudioBufferList * _Nonnull input, const AudioTimeStamp * _Nonnull inputTime,
 AudioBufferList * _Nonnull output, const AudioTimeStamp * _Nonnull outputTime, void * _Nullable context);

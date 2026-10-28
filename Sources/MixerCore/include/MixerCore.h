#ifndef MIXER_CORE_H
#define MIXER_CORE_H

#include <CoreAudio/CoreAudio.h>
#include <stdbool.h>
#include "SystemCore.h"

typedef struct MixerTap MixerTap;

// The returned tap must be stopped with MixerTapDestroy. On failure, errorCode is an OSStatus.
MixerTap *MixerTapCreate(AudioObjectID processID, AudioObjectID sourceDeviceID,
                         AudioObjectID targetDeviceID, float volume, OSStatus *errorCode);
// Starts a short, unmuted system-audio tap so macOS can present its consent dialog.
OSStatus MixerTapRequestPermission(AudioObjectID outputDeviceID);
void MixerTapSetVolume(MixerTap *tap, float volume);
void MixerTapDestroy(MixerTap *tap);

#endif

#import "MixerCore.h"
#import <Foundation/Foundation.h>
#import <CoreAudio/CATapDescription.h>
#import <CoreAudio/AudioHardwareTapping.h>
#import <stdatomic.h>
#import <string.h>

struct MixerTap {
    AudioObjectID tapID;
    AudioObjectID aggregateID;
    AudioDeviceIOProcID procID;
    _Atomic float volume;
    float currentGain;
    UInt32 tapChannels;
    bool started;
    bool permissionOnly;
};

static AudioObjectPropertyAddress address(AudioObjectPropertySelector selector, AudioObjectPropertyScope scope) {
    return (AudioObjectPropertyAddress){selector, scope, kAudioObjectPropertyElementMain};
}

static OSStatus readProperty(AudioObjectID object, AudioObjectPropertySelector selector,
                             AudioObjectPropertyScope scope, void *value, UInt32 *size) {
    AudioObjectPropertyAddress property = address(selector, scope);
    return AudioObjectGetPropertyData(object, &property, 0, NULL, size, value);
}

static float sampleAt(const AudioBufferList *list, UInt32 channel, UInt32 frame) {
    UInt32 offset = channel;
    for (UInt32 i = 0; i < list->mNumberBuffers; i++) {
        const AudioBuffer *buffer = &list->mBuffers[i];
        if (offset < buffer->mNumberChannels) {
            UInt32 index = frame * buffer->mNumberChannels + offset;
            if (buffer->mData && (index + 1) * sizeof(float) <= buffer->mDataByteSize) {
                return ((const float *)buffer->mData)[index];
            }
            return 0;
        }
        offset -= buffer->mNumberChannels;
    }
    return 0;
}

static OSStatus render(AudioObjectID device, const AudioTimeStamp *now,
                       const AudioBufferList *input, const AudioTimeStamp *inputTime,
                       AudioBufferList *output, const AudioTimeStamp *outputTime, void *context) {
    (void)device; (void)now; (void)inputTime; (void)outputTime;
    MixerTap *tap = context;
    if (!input || !output) return noErr;
    if (tap->permissionOnly) return noErr; // HAL supplies zeroed output buffers.
    UInt32 totalInputChannels = 0;
    for (UInt32 b = 0; b < input->mNumberBuffers; b++) {
        totalInputChannels += input->mBuffers[b].mNumberChannels;
    }
    // A subdevice's input buffers come first; the tap is the last input stream.
    if (totalInputChannels < tap->tapChannels) return noErr;
    UInt32 tapChannelOffset = totalInputChannels - tap->tapChannels;
    UInt32 totalOutputChannels = 0;
    for (UInt32 b = 0; b < output->mNumberBuffers; b++) {
        totalOutputChannels += output->mBuffers[b].mNumberChannels;
    }
    float targetGain = atomic_load_explicit(&tap->volume, memory_order_relaxed);
    // Apply one ramp to all output channels, avoiding clicks and L/R imbalance.
    UInt32 firstChannels = output->mNumberBuffers ? output->mBuffers[0].mNumberChannels : 0;
    UInt32 frameCount = firstChannels
        ? output->mBuffers[0].mDataByteSize / (sizeof(float) * firstChannels) : 0;
    const UInt32 rampFrames = 480;
    float startGain = tap->currentGain;
    float gainStep = rampFrames ? (targetGain - startGain) / rampFrames : 0;
    for (UInt32 b = 0; b < output->mNumberBuffers; b++) {
        AudioBuffer *destination = &output->mBuffers[b];
        if (!destination->mData || !destination->mNumberChannels) continue;
        UInt32 frames = destination->mDataByteSize / (sizeof(float) * destination->mNumberChannels);
        float *samples = destination->mData;
        UInt32 channelBase = 0;
        for (UInt32 earlier = 0; earlier < b; earlier++) channelBase += output->mBuffers[earlier].mNumberChannels;
        for (UInt32 frame = 0; frame < frames; frame++) {
            for (UInt32 channel = 0; channel < destination->mNumberChannels; channel++) {
                UInt32 outputChannel = channelBase + channel;
                float gain = startGain + gainStep * (frame < rampFrames ? frame : rampFrames);
                float sample = 0;
                if (totalOutputChannels == 1 && tap->tapChannels > 1) {
                    for (UInt32 sourceChannel = 0; sourceChannel < tap->tapChannels; sourceChannel++) {
                        sample += sampleAt(input, tapChannelOffset + sourceChannel, frame) / tap->tapChannels;
                    }
                } else {
                    UInt32 sourceChannel = tap->tapChannels == 1 ? 0 : outputChannel;
                    if (sourceChannel < tap->tapChannels) {
                        sample = sampleAt(input, tapChannelOffset + sourceChannel, frame);
                    }
                }
                samples[frame * destination->mNumberChannels + channel] = sample * gain;
            }
        }
    }
    tap->currentGain = startGain + gainStep * (frameCount < rampFrames ? frameCount : rampFrames);
    return noErr;
}

static void cleanup(MixerTap *tap) {
    if (!tap) return;
    if (tap->started) AudioDeviceStop(tap->aggregateID, tap->procID);
    if (tap->procID) AudioDeviceDestroyIOProcID(tap->aggregateID, tap->procID);
    if (tap->aggregateID) AudioHardwareDestroyAggregateDevice(tap->aggregateID);
    if (tap->tapID) AudioHardwareDestroyProcessTap(tap->tapID);
    free(tap);
}

static MixerTap *createTap(AudioObjectID processID, AudioObjectID sourceDeviceID,
                           AudioObjectID targetDeviceID, float volume,
                           bool permissionOnly, OSStatus *errorCode) {
    @autoreleasepool {
        OSStatus status = noErr;
        MixerTap *tap = calloc(1, sizeof(MixerTap));
        if (!tap) { if (errorCode) *errorCode = memFullErr; return NULL; }
        atomic_init(&tap->volume, volume);
        tap->currentGain = volume;
        tap->permissionOnly = permissionOnly;
        CATapDescription *description = nil;
        NSDictionary *aggregate = nil;
        CFStringRef sourceUID = NULL;
        CFStringRef targetUID = NULL;
        CFStringRef tapUID = NULL;

        UInt32 uidSize = sizeof(sourceUID);
        status = readProperty(sourceDeviceID, kAudioDevicePropertyDeviceUID,
                              kAudioObjectPropertyScopeGlobal, &sourceUID, &uidSize);
        if (status != noErr || !sourceUID) { if (status == noErr) status = kAudioHardwareBadObjectError; goto fail; }
        uidSize = sizeof(targetUID);
        status = readProperty(targetDeviceID, kAudioDevicePropertyDeviceUID,
                              kAudioObjectPropertyScopeGlobal, &targetUID, &uidSize);
        if (status != noErr || !targetUID) { if (status == noErr) status = kAudioHardwareBadObjectError; goto fail; }

        // Scope the tap to this process and the current output stream.
        description = permissionOnly
            ? [[CATapDescription alloc] initStereoGlobalTapButExcludeProcesses:@[]]
            : [[CATapDescription alloc] initWithProcesses:@[@(processID)]
                                               andDeviceUID:(__bridge NSString *)sourceUID withStream:0];
        description.name = @"MacAudioMixer";
        description.privateTap = YES;
        // Mute the original path as soon as the tap exists, before the aggregate starts.
        description.muteBehavior = permissionOnly ? CATapUnmuted : CATapMuted;
        status = AudioHardwareCreateProcessTap(description, &tap->tapID);
        if (status != noErr) goto fail;

        UInt32 tapUIDSize = sizeof(tapUID);
        status = readProperty(tap->tapID, kAudioTapPropertyUID, kAudioObjectPropertyScopeGlobal,
                              &tapUID, &tapUIDSize);
        if (status != noErr || !tapUID) { if (status == noErr) status = kAudioHardwareBadObjectError; goto fail; }

        aggregate = @{
            @kAudioAggregateDeviceNameKey: @"MacAudioMixer private output",
            @kAudioAggregateDeviceUIDKey: [NSUUID UUID].UUIDString,
            @kAudioAggregateDeviceIsPrivateKey: @YES,
            @kAudioAggregateDeviceMainSubDeviceKey: (__bridge NSString *)targetUID,
            @kAudioAggregateDeviceSubDeviceListKey: @[@{@kAudioSubDeviceUIDKey: (__bridge NSString *)targetUID}],
            @kAudioAggregateDeviceTapListKey: @[@{@kAudioSubTapUIDKey: (__bridge NSString *)tapUID,
                                                 @kAudioSubTapDriftCompensationKey: @YES}],
            @kAudioAggregateDeviceTapAutoStartKey: @YES
        };
        status = AudioHardwareCreateAggregateDevice((__bridge CFDictionaryRef)aggregate, &tap->aggregateID);
        if (status != noErr) goto fail;

        // HAL can return the aggregate before its streams become available.
        UInt32 alive = 0;
        for (int attempt = 0; attempt < 30; attempt++) {
            UInt32 size = sizeof(alive);
            status = readProperty(tap->aggregateID, kAudioDevicePropertyDeviceIsAlive,
                                  kAudioObjectPropertyScopeGlobal, &alive, &size);
            if (status == noErr && alive) break;
            [NSThread sleepForTimeInterval:0.1];
        }
        if (!alive) { status = kAudioHardwareNotRunningError; goto fail; }

        AudioStreamBasicDescription inputFormat = {0}, outputFormat = {0};
        UInt32 size = sizeof(inputFormat);
        status = readProperty(tap->tapID, kAudioTapPropertyFormat,
                              kAudioObjectPropertyScopeGlobal, &inputFormat, &size);
        if (status != noErr) goto fail;
        size = sizeof(outputFormat);
        status = readProperty(tap->aggregateID, kAudioDevicePropertyStreamFormat,
                              kAudioDevicePropertyScopeOutput, &outputFormat, &size);
        if (status != noErr) goto fail;
        if (inputFormat.mFormatID != kAudioFormatLinearPCM || outputFormat.mFormatID != kAudioFormatLinearPCM ||
            !(inputFormat.mFormatFlags & kAudioFormatFlagIsFloat) ||
            !(outputFormat.mFormatFlags & kAudioFormatFlagIsFloat) ||
            inputFormat.mBitsPerChannel != 32 || outputFormat.mBitsPerChannel != 32 ||
            inputFormat.mChannelsPerFrame == 0) {
            status = kAudioHardwareUnsupportedOperationError;
            goto fail;
        }

        tap->tapChannels = inputFormat.mChannelsPerFrame;
        status = AudioDeviceCreateIOProcID(tap->aggregateID, render, tap, &tap->procID);
        if (status != noErr) goto fail;
        status = AudioDeviceStart(tap->aggregateID, tap->procID);
        if (status != noErr) goto fail;
        tap->started = true;
        CFRelease(tapUID);
        CFRelease(targetUID);
        CFRelease(sourceUID);
        if (errorCode) *errorCode = noErr;
        return tap;
fail:
        if (tapUID) CFRelease(tapUID);
        if (targetUID) CFRelease(targetUID);
        if (sourceUID) CFRelease(sourceUID);
        if (errorCode) *errorCode = status;
        cleanup(tap);
        return NULL;
    }
}

MixerTap *MixerTapCreate(AudioObjectID processID, AudioObjectID sourceDeviceID,
                         AudioObjectID targetDeviceID, float volume, OSStatus *errorCode) {
    return createTap(processID, sourceDeviceID, targetDeviceID, volume, false, errorCode);
}

OSStatus MixerTapRequestPermission(AudioObjectID outputDeviceID) {
    OSStatus status = noErr;
    MixerTap *tap = createTap(0, outputDeviceID, outputDeviceID, 0, true, &status);
    if (!tap) return status;
    [NSThread sleepForTimeInterval:1.0];
    MixerTapDestroy(tap);
    return noErr;
}

void MixerTapSetVolume(MixerTap *tap, float volume) {
    if (tap) atomic_store_explicit(&tap->volume, fmaxf(0, fminf(volume, 1)), memory_order_relaxed);
}

void MixerTapDestroy(MixerTap *tap) { cleanup(tap); }

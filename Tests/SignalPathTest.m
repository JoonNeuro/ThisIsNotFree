// A deterministic PCM fixture for duplex devices. It checks the rendered signal,
// including when microphone buffers appear ahead of the process tap.
#import "../Sources/MixerCore/MixerCore.m"
#include <math.h>
#include <stdio.h>

static AudioBufferList *buffers(UInt32 count) {
    AudioBufferList *list = calloc(1, offsetof(AudioBufferList, mBuffers) + count * sizeof(AudioBuffer));
    list->mNumberBuffers = count;
    return list;
}

static double rms(const float *samples, size_t count) {
    double sum = 0;
    for (size_t i = 0; i < count; i++) sum += (double)samples[i] * samples[i];
    return sqrt(sum / count);
}

int main(void) {
    enum { frames = 480 };
    float microphone[frames * 2], tapped[frames * 2], result[frames * 2];
    float left[frames], right[frames];
    for (int i = 0; i < frames; i++) {
        float tone = 0.25f * sinf(2.f * (float)M_PI * 440.f * i / 48000.f);
        microphone[2 * i] = microphone[2 * i + 1] = 0.8f;
        tapped[2 * i] = tapped[2 * i + 1] = tone;
        left[i] = right[i] = tone;
    }

    AudioBufferList *input = buffers(2), *output = buffers(1);
    input->mBuffers[0] = (AudioBuffer){2, sizeof(microphone), microphone};
    input->mBuffers[1] = (AudioBuffer){2, sizeof(tapped), tapped};
    output->mBuffers[0] = (AudioBuffer){2, sizeof(result), result};

    MixerTap tap = {0};
    tap.tapChannels = 2;
    tap.currentGain = 1;
    atomic_init(&tap.volume, 1);
    render(0, NULL, input, NULL, output, NULL, &tap);
    double full = rms(result, frames * 2);
    double source = rms(tapped, frames * 2);

    tap.currentGain = 0.9f;
    atomic_store(&tap.volume, 0.9f);
    render(0, NULL, input, NULL, output, NULL, &tap);
    double initial = rms(result, frames * 2);
    printf("preloaded 90%%: %.6f ratio=%.4f\n", initial, initial / source);
    if (fabs(initial / source - 0.9) > 0.001) return 1;

    tap.currentGain = 1;
    atomic_store(&tap.volume, 1);

    atomic_store(&tap.volume, 0.99f);
    for (int i = 0; i < 10; i++) render(0, NULL, input, NULL, output, NULL, &tap);
    double reduced = rms(result, frames * 2);
    printf("interleaved: source=%.6f 100%%=%.6f 99%%=%.6f ratio=%.4f\n",
           source, full, reduced, reduced / full);
    if (fabs(full / source - 1) > 0.001 || fabs(reduced / full - 0.99) > 0.001) return 1;

    free(input);
    input = buffers(3);
    input->mBuffers[0] = (AudioBuffer){2, sizeof(microphone), microphone};
    input->mBuffers[1] = (AudioBuffer){1, sizeof(left), left};
    input->mBuffers[2] = (AudioBuffer){1, sizeof(right), right};
    memset(result, 0, sizeof(result));
    tap.currentGain = 0.5f;
    atomic_store(&tap.volume, 0.5f);
    render(0, NULL, input, NULL, output, NULL, &tap);
    double half = rms(result, frames * 2);
    printf("deinterleaved: 50%%=%.6f ratio=%.4f\n", half, half / source);
    if (fabs(half / source - 0.5) >= 0.001) return 1;

    float mono[frames] = {0};
    for (int i = 0; i < frames; i++) left[i] = 0;
    output->mBuffers[0] = (AudioBuffer){1, sizeof(mono), mono};
    tap.currentGain = 1;
    atomic_store(&tap.volume, 1);
    render(0, NULL, input, NULL, output, NULL, &tap);
    double downmixed = rms(mono, frames);
    printf("stereo to mono, right only: %.6f ratio=%.4f\n", downmixed, downmixed / source);
    free(input);
    free(output);
    return fabs(downmixed / source - 0.5) < 0.001 ? 0 : 1;
}

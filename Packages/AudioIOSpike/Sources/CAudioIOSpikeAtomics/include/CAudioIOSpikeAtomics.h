#ifndef C_AUDIO_IO_SPIKE_ATOMICS_H
#define C_AUDIO_IO_SPIKE_ATOMICS_H

#include <stdatomic.h>
#include <stdint.h>

typedef struct {
    _Atomic(uint32_t) value;
} AudioIOSpikeAtomicUInt32;

void audio_io_atomic_u32_init(AudioIOSpikeAtomicUInt32 *atomic, uint32_t value);
uint32_t audio_io_atomic_u32_load_acquire(const AudioIOSpikeAtomicUInt32 *atomic);
void audio_io_atomic_u32_store_release(AudioIOSpikeAtomicUInt32 *atomic, uint32_t value);
uint32_t audio_io_atomic_u32_fetch_add_relaxed(AudioIOSpikeAtomicUInt32 *atomic, uint32_t value);

#endif

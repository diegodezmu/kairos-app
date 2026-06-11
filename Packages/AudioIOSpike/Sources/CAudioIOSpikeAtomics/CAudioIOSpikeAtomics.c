#include "CAudioIOSpikeAtomics.h"

void audio_io_atomic_u32_init(AudioIOSpikeAtomicUInt32 *atomic, uint32_t value) {
    atomic_init(&atomic->value, value);
}

uint32_t audio_io_atomic_u32_load_acquire(const AudioIOSpikeAtomicUInt32 *atomic) {
    return atomic_load_explicit(&atomic->value, memory_order_acquire);
}

void audio_io_atomic_u32_store_release(AudioIOSpikeAtomicUInt32 *atomic, uint32_t value) {
    atomic_store_explicit(&atomic->value, value, memory_order_release);
}

uint32_t audio_io_atomic_u32_fetch_add_relaxed(AudioIOSpikeAtomicUInt32 *atomic, uint32_t value) {
    return atomic_fetch_add_explicit(&atomic->value, value, memory_order_relaxed);
}

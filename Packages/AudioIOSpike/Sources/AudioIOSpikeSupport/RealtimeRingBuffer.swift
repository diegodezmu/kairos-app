import CAudioIOSpikeAtomics
import Foundation

public final class AtomicUInt32Box {
    private let storage: UnsafeMutablePointer<AudioIOSpikeAtomicUInt32>

    public init(_ value: UInt32 = 0) {
        storage = .allocate(capacity: 1)
        audio_io_atomic_u32_init(storage, value)
    }

    deinit {
        storage.deallocate()
    }

    @inline(__always)
    public func load() -> UInt32 {
        audio_io_atomic_u32_load_acquire(storage)
    }

    @inline(__always)
    public func store(_ value: UInt32) {
        audio_io_atomic_u32_store_release(storage, value)
    }

    @inline(__always)
    @discardableResult
    public func increment() -> UInt32 {
        audio_io_atomic_u32_fetch_add_relaxed(storage, 1) + 1
    }
}

public final class DynamicsSampleRingBuffer {
    private let capacity: UInt32
    private let mask: UInt32
    private let storage: UnsafeMutableBufferPointer<DynamicsSample>
    private let readIndex: UnsafeMutablePointer<AudioIOSpikeAtomicUInt32>
    private let writeIndex: UnsafeMutablePointer<AudioIOSpikeAtomicUInt32>

    public init(capacity: Int) {
        precondition(capacity > 1 && capacity.isMultiple(of: 2), "Capacity must be a power of two")

        self.capacity = UInt32(capacity)
        self.mask = UInt32(capacity - 1)
        self.storage = UnsafeMutableBufferPointer<DynamicsSample>.allocate(capacity: capacity)
        self.storage.initialize(repeating: .zero)

        readIndex = .allocate(capacity: 1)
        writeIndex = .allocate(capacity: 1)
        audio_io_atomic_u32_init(readIndex, 0)
        audio_io_atomic_u32_init(writeIndex, 0)
    }

    deinit {
        storage.deinitialize()
        storage.deallocate()
        readIndex.deallocate()
        writeIndex.deallocate()
    }

    @inline(__always)
    @discardableResult
    public func push(_ sample: DynamicsSample) -> Bool {
        let head = audio_io_atomic_u32_load_acquire(writeIndex)
        let tail = audio_io_atomic_u32_load_acquire(readIndex)
        let next = (head &+ 1) & mask

        if next == tail {
            return false
        }

        storage[Int(head)] = sample
        audio_io_atomic_u32_store_release(writeIndex, next)
        return true
    }

    @inline(__always)
    public func pop() -> DynamicsSample? {
        let tail = audio_io_atomic_u32_load_acquire(readIndex)
        let head = audio_io_atomic_u32_load_acquire(writeIndex)

        if tail == head {
            return nil
        }

        let sample = storage[Int(tail)]
        let next = (tail &+ 1) & mask
        audio_io_atomic_u32_store_release(readIndex, next)
        return sample
    }

    public func drain() -> [DynamicsSample] {
        var result: [DynamicsSample] = []
        while let sample = pop() {
            result.append(sample)
        }
        return result
    }
}

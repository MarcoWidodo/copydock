import Foundation

public final class SlotStore {
    public static let slotCount = 9

    public private(set) var slots: [ClipboardSnapshot?]
    public private(set) var lastCopiedSlot: Int?
    public var isCapturePaused = false
    public var ignoreNextCapture = false
    public var onChange: (() -> Void)?

    public init() {
        slots = Array(repeating: nil, count: Self.slotCount)
    }

    public subscript(index: Int) -> ClipboardSnapshot? {
        guard slots.indices.contains(index) else { return nil }
        return slots[index]
    }

    @discardableResult
    public func capture(_ snapshot: ClipboardSnapshot, into index: Int, explicit: Bool = false) -> Bool {
        guard slots.indices.contains(index) else { return false }
        if !explicit {
            guard !isCapturePaused else { return false }
            if ignoreNextCapture {
                ignoreNextCapture = false
                return false
            }
        }
        slots[index] = snapshot
        lastCopiedSlot = index
        onChange?()
        return true
    }

    public func clear(_ index: Int) {
        guard slots.indices.contains(index) else { return }
        slots[index] = nil
        if lastCopiedSlot == index { lastCopiedSlot = nil }
        onChange?()
    }

    public func clearAll() {
        slots = Array(repeating: nil, count: Self.slotCount)
        lastCopiedSlot = nil
        onChange?()
    }
}

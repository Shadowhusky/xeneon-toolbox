import Foundation

/// Accumulates raw HID element values from the Xeneon Edge digitizer into the
/// current touch sample. The panel reports as a mouse-style absolute device:
/// X/Y on the Generic Desktop page and contact as Button 1 (not a digitizer
/// tip switch).
public struct HIDTouchDecoder: Sendable {
    public private(set) var rawX: Double?
    public private(set) var rawY: Double?
    public private(set) var contact: Bool = false

    public init() {}

    public mutating func ingest(page: UInt32, usage: UInt32, value: Int) {
        switch (page, usage) {
        case (0x01, 0x30): rawX = Double(value)   // Generic Desktop / X
        case (0x01, 0x31): rawY = Double(value)   // Generic Desktop / Y
        case (0x09, 0x01): contact = value != 0   // Button page / Button 1
        default: break
        }
    }
}

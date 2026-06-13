import SwiftUI

extension Color {
    /// Builds a colour from an Entur presentation hex string such as `"E60000"`.
    /// Entur omits the leading `#`; a leading `#` is tolerated anyway. Returns `nil` for
    /// anything that isn't a 6-digit RGB hex.
    init?(enturHex hex: String?) {
        guard var string = hex?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty
        else { return nil }
        if string.hasPrefix("#") { string.removeFirst() }
        guard string.count == 6, let value = UInt32(string, radix: 16) else { return nil }

        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: 1.0)
    }
}

import SwiftUI

enum PillPalette {
    /// Colors used for pill icons so each medication is easy to tell apart.
    static let colors: [Color] = [
        Color(red: 0.93, green: 0.36, blue: 0.36), Color(red: 0.20, green: 0.62, blue: 0.95),
        Color(red: 0.98, green: 0.70, blue: 0.20), Color(red: 0.30, green: 0.74, blue: 0.50),
        Color(red: 0.62, green: 0.38, blue: 0.90), Color(red: 0.95, green: 0.50, blue: 0.70),
        Color(red: 0.15, green: 0.70, blue: 0.75), Color(red: 0.55, green: 0.45, blue: 0.35)
    ]

    static func color(_ index: Int) -> Color { colors[abs(index) % colors.count] }
}

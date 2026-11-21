import SwiftUI
import UIKit

// Shared pieces of the MEDI redesign (Figma: "Main tabs UPDATED").

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

enum Medi {
    static let ink = Color(hex: 0x111111)
    static let inkSecondary = Color(hex: 0x4D4D4D)
    static let rule = Color(hex: 0xBDBDBD)
    static let screen = Color(hex: 0xF2F2F2)
    static let selected = Color(hex: 0x222222)
    static let goFill = Color(hex: 0xECFFE0)
    static let goStroke = Color(hex: 0xB4ED8E)
    static let welcomeTop = Color(hex: 0xFFF9F9)
}

extension Font {
    /// The design's typeface, Karla (bundled in PillBox/Fonts). Falls back to the system font if it can't load.
    static func karla(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name = weight == .bold ? "Karla-Bold"
            : weight == .semibold ? "Karla-SemiBold"
            : weight == .medium ? "Karla-Medium"
            : "Karla-Regular"
        if UIFont(name: name, size: size) != nil { return .custom(name, fixedSize: size) }
        if UIFont(name: "Karla-Regular", size: size) != nil { return .custom("Karla-Regular", fixedSize: size).weight(weight) }
        return .system(size: size, weight: weight)
    }
}

/// The bottom bar: Home, Add meds, Pill box, Info.
struct MediTabBar: View {
    @Binding var tab: AppTab

    var body: some View {
        HStack(spacing: 10) {
            item("home", label: "Home", selected: tab == .today) { tab = .today }
            item("add", label: "Add medication", selected: tab == .add) { tab = .add }
            item("grid", label: "Pill box", selected: tab == .pillBox) { tab = .pillBox }
            item("info", label: "Info", selected: tab == .meds) { tab = .meds }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .frame(maxWidth: .infinity)
        .background(alignment: .top) {
            Color.white
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) { Medi.rule.frame(height: 1.5) }
        }
    }

    private func item(_ icon: String, label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(selected ? "\(icon)-on" : "\(icon)-off")
                .resizable()
                .frame(width: 42, height: 42)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(selected ? Medi.selected : .clear, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Lays out a screen on the design's 402×874 iPhone canvas, scaled to fit other screen sizes.
struct DesignCanvas<Content: View>: View {
    @ViewBuilder var content: Content
    private let canvas = CGSize(width: 402, height: 874)

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / canvas.width, geo.size.height / canvas.height)
            content
                .frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
                .scaleEffect(scale)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
    }
}

/// "first screen": shown when the app opens with no medications yet.
struct WelcomeView: View {
    var onStart: () -> Void

    var body: some View {
        DesignCanvas {
            ZStack(alignment: .topLeading) {
                Image("welcome-sun-moon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 312, height: 556)
                    .offset(x: 45, y: 64)
                    .accessibilityHidden(true)

                // Paddings reproduce the design's 99.89% line height with Karla's line metrics.
                VStack(spacing: 0) {
                    Text("WELCOME TO ").font(.karla(40)).frame(height: 40).padding(.top, 3.5)
                    Text("MEDI").font(.karla(96)).frame(height: 96).padding(.top, 25.8)
                }
                .foregroundStyle(.black)
                .frame(width: 319)
                .offset(x: 38, y: 115)
                .accessibilityElement(children: .combine)

                Button(action: onStart) {
                    Text("START")
                        .font(.karla(32))
                        .foregroundStyle(.black)
                        .frame(width: 274, height: 60)
                        .background(Capsule().fill(Medi.goFill))
                        .overlay(Capsule().strokeBorder(Medi.goStroke, lineWidth: 4))
                }
                .buttonStyle(.plain)
                .offset(x: 64, y: 653)
            }
        }
        .background(LinearGradient(colors: [Medi.welcomeTop, .white], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
    }
}

/// "Daily Pill Summary" title at the top of Home.
struct HomeHeader: View {
    var topInset: CGFloat

    var body: some View {
        Text("Daily Pill Summary")
            .font(.karla(35, .bold))
            .foregroundStyle(Medi.ink)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, max(topInset - 12, 12))
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Yesterday, the selected day and tomorrow, with arrows to move a day at a time.
struct DateBar: View {
    @Binding var day: Date
    private let cal = Calendar.current

    var body: some View {
        HStack(spacing: 0) {
            arrow("chevron-prev", label: "Previous day", by: -1)
            HStack(spacing: 0) {
                dayColumn(offset: -1)
                dayColumn(offset: 0)
                dayColumn(offset: 1)
            }
            arrow("chevron-next", label: "Next day", by: 1)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(.white)
        .overlay(alignment: .top) { Medi.rule.frame(height: 1.5) }
        .overlay(alignment: .bottom) { Medi.rule.frame(height: 1.5) }
    }

    private func arrow(_ image: String, label: String, by days: Int) -> some View {
        Button { move(by: days) } label: {
            Image(image).resizable().frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func dayColumn(offset: Int) -> some View {
        let date = cal.date(byAdding: .day, value: offset, to: day) ?? day
        let selected = offset == 0
        return Button { move(by: offset) } label: {
            VStack(spacing: 6) {
                Text(date.formatted(.dateTime.weekday(selected ? .wide : .abbreviated)))
                    .font(selected ? .karla(20, .bold) : .karla(17, .medium))
                    .foregroundStyle(selected ? Medi.ink : Medi.inkSecondary)
                Text(date.formatted(.dateTime.day()))
                    .font(selected ? .karla(36, .bold) : .karla(24, .semibold))
                    .foregroundStyle(selected ? .white : Medi.ink)
                    .frame(width: selected ? 72 : 48, height: selected ? 72 : 48)
                    .background(selected ? Medi.selected : .clear, in: Circle())
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func move(by days: Int) {
        guard days != 0, let d = cal.date(byAdding: .day, value: days, to: day) else { return }
        day = d
    }
}

/// "onboarding home": Home before any medication has been added.
struct OnboardingHomeView: View {
    @State private var day = Date()

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                HomeHeader(topInset: geo.safeAreaInsets.top)
                DateBar(day: $day).padding(.top, 15)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea(edges: .top)
        }
        .background(alignment: .topLeading) { greeting }
        .background(Medi.screen.ignoresSafeArea())
    }

    /// Two suns with grey speech bubbles, placed where the design has them on the 402 × 874 screen.
    private var greeting: some View {
        ZStack(alignment: .topLeading) {
            Image("onboarding-sun")
                .resizable()
                .scaledToFit()
                .frame(width: 152, height: 304)
                .offset(x: 18, y: 203)
                .accessibilityHidden(true)

            bubble(width: 199, height: 160)
                .offset(x: 181, y: 302)
            Text("Hi! Your medications and when to take them will appear here.")
                .font(.karla(24, .semibold))
                .foregroundStyle(Medi.ink)
                .frame(width: 172, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .offset(x: 198, y: 310)

            bubble(width: 266, height: 158)
                .offset(x: 24, y: 556)
            Text("Click the \(Text(Image("icon-add-inline")).baselineOffset(-4)) to upload your medications")
                .font(.karla(36, .semibold))
                .foregroundStyle(Medi.ink)
                .frame(width: 263, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .offset(x: 43, y: 570)
                .accessibilityLabel("Tap the plus button below to upload your medications")

            Image("onboarding-sun-wave")
                .resizable()
                .scaledToFill()
                .frame(width: 169, height: 301)
                .offset(x: 259, y: 495)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func bubble(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Medi.compartment)
            .frame(width: width, height: height)
    }
}

// MARK: - Shared pieces for the add flow, pill box and Home

/// The grey card with a medication's name, at the top of "confirm info page" and "pill specific view".
struct MedNameCard: View {
    let name: String
    var faded = false

    var body: some View {
        Text(name)
            .font(.karla(56))
            .foregroundStyle(faded ? Medi.inkSecondary : .black)
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .minimumScaleFactor(0.45)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(width: 330)
            .background(Medi.nameCard, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
    }
}

/// The white card under the name card, with Dosage, Time, Expires and Provider.
struct MedDetailsCard<Rows: View>: View {
    var rowSpacing: CGFloat
    var verticalPadding: CGFloat
    @ViewBuilder var rows: Rows

    var body: some View {
        VStack(alignment: .leading, spacing: rowSpacing) { rows }
            .padding(.vertical, verticalPadding)
            .padding(.leading, 15)
            .padding(.trailing, 16)
            .frame(width: 266, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
    }
}

/// One line of the details card. Long values wrap to a second line before shrinking.
struct MedDetailLine: View {
    let text: String
    var color: Color = .black

    var body: some View {
        Text(text)
            .font(.karla(30))
            .foregroundStyle(color)
            .lineLimit(2)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity, minHeight: 35, alignment: .leading)
    }
}

extension Medi {
    static let nameCard = Color(hex: 0xE0E0E0)
    static let outline = Color(hex: 0xAEB0B9)
    static let stopFill = Color(hex: 0xFFE8E8)
    static let stopStroke = Color(hex: 0xED8E8E)
    static let compartment = Color(hex: 0xD9D9D9)
    static let pill = Color(hex: 0x494747)
    static let expiringText = Color(hex: 0xC93C3C)
}

/// The design's pill-shaped buttons: green (go), red (delete) and grey outline.
struct MediButton: View {
    enum Style { case go, stop, plain }
    let title: String
    var style: Style = .plain
    var width: CGFloat = 266
    var fontSize: CGFloat = 32
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.karla(fontSize))
                .foregroundStyle(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 12)
                .frame(width: width, height: 60)
                .background(Capsule().fill(fill))
                .overlay(Capsule().strokeBorder(stroke, lineWidth: 4))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
    }

    private var fill: Color {
        switch style {
        case .go: Medi.goFill
        case .stop: Medi.stopFill
        case .plain: .clear   // outline only: the background shows through, as in the design
        }
    }

    private var stroke: Color {
        switch style {
        case .go: Medi.goStroke
        case .stop: Medi.stopStroke
        case .plain: Medi.outline
        }
    }
}

/// How dosage, times and dates read on the redesigned screens.
enum MedText {
    static func dosage(strength: String, pills: Int, form: String) -> String {
        let unit = form.isEmpty ? "pill" : form
        let count = "\(pills) \(pills == 1 ? unit : unit + "s")"
        if strength.isEmpty { return count }
        return pills > 1 ? "\(strength) × \(pills)" : strength
    }

    static func dosage(_ l: ParsedLabel) -> String { dosage(strength: l.strength, pills: l.pillsPerDose, form: l.form) }
    static func dosage(_ d: MedDraft) -> String { dosage(strength: d.strength, pills: d.pillsPerDose, form: d.form) }
    static func dosage(_ m: Medication) -> String { dosage(strength: m.strength, pills: m.pillsPerDose, form: m.form) }

    /// "8 AM", "8:30 PM"
    static func time(_ minutes: Int) -> String {
        let h = (minutes / 60) % 24, m = minutes % 60
        let hour12 = h % 12 == 0 ? 12 : h % 12
        let suffix = h < 12 ? "AM" : "PM"
        return m == 0 ? "\(hour12) \(suffix)" : String(format: "%d:%02d %@", hour12, m, suffix)
    }

    static func times(_ minutes: [Int]) -> String {
        minutes.isEmpty ? "as needed" : minutes.sorted().map(time).joined(separator: ", ")
    }

    static func times(for label: ParsedLabel) -> String { times(MedDraft(parsed: label).previewTimes) }
    static func times(for med: Medication) -> String { times(Scheduler.times(for: med)) }

    /// "12/16/26"
    static func date(_ date: Date?) -> String {
        guard let date else { return "x/x/x" }
        let c = Calendar.current.dateComponents([.month, .day, .year], from: date)
        return "\(c.month ?? 0)/\(c.day ?? 0)/\(String(format: "%02d", (c.year ?? 0) % 100))"
    }
}

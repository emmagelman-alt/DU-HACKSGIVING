import SwiftUI

/// The shapes a pill can be drawn as. Read from the label's description when it has one
/// ("white oval tablet"), otherwise worked out from the form (capsule, softgel, liquid...).
enum PillShape: String, CaseIterable, Identifiable {
    case round, oval, oblong, capsule, softgel, diamond, triangle, square, rectangle, pentagon, hexagon, octagon, liquid, patch

    var id: String { rawValue }

    /// Shapes offered when someone picks one by hand.
    static let pickable: [PillShape] = [.round, .oval, .oblong, .capsule, .softgel, .diamond, .triangle, .square,
                                        .rectangle, .pentagon, .hexagon, .octagon, .liquid, .patch]

    var title: String {
        switch self {
        case .round: "Round"
        case .oval: "Oval"
        case .oblong: "Oblong"
        case .capsule: "Capsule"
        case .softgel: "Softgel"
        case .diamond: "Diamond"
        case .triangle: "Triangle"
        case .square: "Square"
        case .rectangle: "Rectangle"
        case .pentagon: "Pentagon"
        case .hexagon: "Hexagon"
        case .octagon: "Octagon"
        case .liquid: "Liquid"
        case .patch: "Patch"
        }
    }

    /// The saved shape, or a sensible one for the form when the label didn't describe the pill.
    static func resolve(shape: String, form: String) -> PillShape {
        if let s = PillShape(rawValue: shape) { return s }
        switch form {
        case "capsule": return .capsule
        case "softgel": return .softgel
        case "mL", "teaspoon", "drop": return .liquid
        case "patch": return .patch
        default: return .round
        }
    }
}

extension Medication {
    var pillLook: PillShape { .resolve(shape: pillShape, form: form) }

    /// "Pink round tablet, scored, imprint 10", for VoiceOver.
    var pillDescription: String {
        var words = [pillColor, pillLook.title.lowercased(), form].filter { !$0.isEmpty }
        if pillLook.title.lowercased() == form { words.removeLast() }
        var text = words.joined(separator: " ")
        if pillScored { text += ", scored" }
        if !pillImprint.isEmpty { text += ", imprint \(pillImprint)" }
        return text.prefix(1).uppercased() + text.dropFirst()
    }
}

/// A line drawing of one pill: its outline, the bevel just inside the edge, a score line if it has one,
/// and its imprint. Drawn in a square `size` points wide.
struct PillOutline: View {
    let shape: PillShape
    var scored = false
    var imprint = ""
    var size: CGFloat = 96
    var color: Color = Medi.ink
    /// A light wash inside the outline (the pill box uses the palette's lavender).
    var fill: Color?

    init(shape: PillShape, scored: Bool = false, imprint: String = "", size: CGFloat = 96, color: Color = Medi.ink, fill: Color? = nil) {
        self.shape = shape
        self.scored = scored
        self.imprint = imprint
        self.size = size
        self.color = color
        self.fill = fill
    }

    init(med: Medication, size: CGFloat = 96, color: Color = Medi.ink, fill: Color? = nil) {
        self.init(shape: med.pillLook, scored: med.pillScored, imprint: med.pillImprint, size: size, color: color, fill: fill)
    }

    var body: some View {
        Canvas { ctx, canvasSize in
            let s = min(canvasSize.width, canvasSize.height)
            let c = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let line = max(1.5, s * 0.035)
            let thin = StrokeStyle(lineWidth: line * 0.55, lineCap: .round, lineJoin: .round)
            let bold = StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round)
            let ink = GraphicsContext.Shading.color(color)
            let faint = GraphicsContext.Shading.color(color.opacity(0.55))

            // Long pills lie at an angle, like a pill resting on a table.
            var g = ctx
            if let tilt = shape.tilt {
                g.translateBy(x: c.x, y: c.y)
                g.rotate(by: tilt)
                g.translateBy(x: -c.x, y: -c.y)
            }

            let geo = PillGeometry(shape: shape, center: c, size: s)
            if let fill { g.fill(geo.outline, with: .color(fill)) }
            g.stroke(geo.outline, with: ink, style: bold)
            if let inner = geo.bevel { g.stroke(inner, with: faint, style: thin) }
            for extra in geo.details { g.stroke(extra, with: ink, style: thin) }
            if let dashed = geo.dashed {
                g.stroke(dashed, with: faint, style: StrokeStyle(lineWidth: line * 0.55, lineCap: .round, dash: [s * 0.05, s * 0.045]))
            }
            if scored, let score = geo.score { g.stroke(score, with: ink, style: bold) }

            if !imprint.isEmpty {
                let fontSize = s * (imprint.count > 4 ? 0.11 : 0.14)
                let text = g.resolve(Text(imprint).font(.karla(fontSize, .bold)).foregroundStyle(color))
                g.draw(text, at: geo.imprintCenter(scored: scored), anchor: .center)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private extension PillShape {
    /// Capsules and other long pills are drawn tilted.
    var tilt: Angle? {
        switch self {
        case .capsule, .oblong: .degrees(-32)
        case .softgel: .degrees(-24)
        default: nil
        }
    }
}

/// The paths for each shape, centred on `center` inside a square `size` wide.
private struct PillGeometry {
    let shape: PillShape
    let center: CGPoint
    let size: CGFloat

    private var c: CGPoint { center }
    private var s: CGFloat { size }

    var outline: Path { path(inset: 0) }

    /// The edge of the pill's face, just inside the outline.
    var bevel: Path? {
        switch shape {
        case .capsule, .softgel, .liquid, .patch: nil
        default: path(inset: s * 0.075)
        }
    }

    /// Lines that make a shape read as what it is: the two halves of a capsule, a softgel's shine,
    /// the dashed backing of a patch.
    var details: [Path] {
        switch shape {
        case .capsule:
            let w = s * 0.98, h = s * 0.42
            let seam = c.x + w * 0.04
            var p = Path()
            for x in [seam - s * 0.025, seam + s * 0.025] {
                // The two halves overlap: two gently curved lines where one slides over the other.
                p.move(to: CGPoint(x: x, y: c.y - h / 2))
                p.addQuadCurve(to: CGPoint(x: x, y: c.y + h / 2), control: CGPoint(x: x + s * 0.05, y: c.y))
            }
            var shine = Path()
            shine.move(to: CGPoint(x: c.x - w * 0.36, y: c.y - h * 0.24))
            shine.addLine(to: CGPoint(x: c.x - w * 0.12, y: c.y - h * 0.24))
            return [p, shine]
        case .softgel:
            let w = s * 0.86, h = s * 0.58
            let shine = Path { p in
                p.move(to: CGPoint(x: c.x - w * 0.30, y: c.y - h * 0.10))
                p.addQuadCurve(to: CGPoint(x: c.x - w * 0.05, y: c.y - h * 0.30),
                               control: CGPoint(x: c.x - w * 0.28, y: c.y - h * 0.30))
            }
            return [shine]
        case .liquid:
            let r = s * 0.27
            let bottom = CGPoint(x: c.x, y: c.y + s * 0.13)
            return [Path { p in
                p.addArc(center: bottom, radius: r * 0.62, startAngle: .degrees(150), endAngle: .degrees(205), clockwise: false)
            }]
        case .patch:
            return [Path(ellipseIn: CGRect(x: c.x - s * 0.09, y: c.y - s * 0.09, width: s * 0.18, height: s * 0.18))]
        default:
            return []
        }
    }

    /// A patch's sticky edge, drawn dashed.
    var dashed: Path? {
        guard shape == .patch else { return nil }
        let inner = CGRect(x: c.x - s * 0.27, y: c.y - s * 0.27, width: s * 0.54, height: s * 0.54)
        return Path(roundedRect: inner, cornerRadius: s * 0.08, style: .continuous)
    }

    /// The groove across the middle of a scored tablet.
    var score: Path? {
        let half: CGFloat
        switch shape {
        case .round: half = s * 0.31
        case .square: half = s * 0.28
        case .oval, .rectangle: half = s * 0.22
        case .oblong: half = s * 0.17
        case .diamond, .pentagon, .hexagon, .octagon: half = s * 0.26
        case .triangle: return Path { p in
            p.move(to: CGPoint(x: c.x, y: c.y - s * 0.16)); p.addLine(to: CGPoint(x: c.x, y: c.y + s * 0.22))
        }
        default: return nil
        }
        // Across the short side of long pills, side to side on round ones.
        let vertical = [.oval, .oblong, .rectangle].contains(shape)
        return Path { p in
            if vertical {
                p.move(to: CGPoint(x: c.x, y: c.y - half)); p.addLine(to: CGPoint(x: c.x, y: c.y + half))
            } else {
                p.move(to: CGPoint(x: c.x - half, y: c.y)); p.addLine(to: CGPoint(x: c.x + half, y: c.y))
            }
        }
    }

    func imprintCenter(scored: Bool) -> CGPoint {
        switch shape {
        case .capsule: return CGPoint(x: c.x - s * 0.2, y: c.y)                 // on the longer half
        case .oval, .oblong, .rectangle: return scored ? CGPoint(x: c.x - s * 0.2, y: c.y) : c
        case .triangle: return CGPoint(x: c.x, y: c.y + s * (scored ? 0.02 : 0.06))
        default: return scored ? CGPoint(x: c.x, y: c.y - s * 0.13) : c
        }
    }

    private func path(inset d: CGFloat) -> Path {
        switch shape {
        case .round:
            let r = s * 0.40 - d
            return Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        case .oval:
            let w = s * 0.92 - d * 2, h = s * 0.62 - d * 2
            return Path(ellipseIn: CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h))
        case .oblong:
            let w = s * 0.98 - d * 2, h = s * 0.44 - d * 2
            return Path(roundedRect: CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h), cornerRadius: h / 2)
        case .capsule:
            let w = s * 0.98, h = s * 0.42
            return Path(roundedRect: CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h), cornerRadius: h / 2)
        case .softgel:
            let w = s * 0.86, h = s * 0.58
            return Path(ellipseIn: CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h))
        case .square:
            let w = s * 0.74 - d * 2
            return Path(roundedRect: CGRect(x: c.x - w / 2, y: c.y - w / 2, width: w, height: w), cornerRadius: s * 0.14 - d * 0.6, style: .continuous)
        case .rectangle:
            let w = s * 0.92 - d * 2, h = s * 0.56 - d * 2
            return Path(roundedRect: CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h), cornerRadius: s * 0.12 - d * 0.6, style: .continuous)
        case .diamond:
            return rounded([CGPoint(x: c.x, y: c.y - s * 0.40 + d * 1.3), CGPoint(x: c.x + s * 0.46 - d * 1.3, y: c.y),
                            CGPoint(x: c.x, y: c.y + s * 0.40 - d * 1.3), CGPoint(x: c.x - s * 0.46 + d * 1.3, y: c.y)],
                           radius: s * 0.08)
        case .triangle:
            return polygon(sides: 3, radius: s * 0.48 - d * 2, offsetY: s * 0.08, cornerRadius: s * 0.10)
        case .pentagon:
            return polygon(sides: 5, radius: s * 0.44 - d * 1.2, offsetY: s * 0.02, cornerRadius: s * 0.07)
        case .hexagon:
            return polygon(sides: 6, radius: s * 0.44 - d * 1.15, offsetY: 0, cornerRadius: s * 0.07, rotation: .degrees(30))
        case .octagon:
            return polygon(sides: 8, radius: s * 0.43 - d * 1.08, offsetY: 0, cornerRadius: s * 0.05, rotation: .degrees(22.5))
        case .liquid:
            // A drop: a point at the top flowing into a round bottom.
            let r = s * 0.27
            let bottom = CGPoint(x: c.x, y: c.y + s * 0.13)
            let top = CGPoint(x: c.x, y: c.y - s * 0.42)
            return Path { p in
                p.move(to: top)
                p.addCurve(to: CGPoint(x: bottom.x + r, y: bottom.y),
                           control1: CGPoint(x: c.x + s * 0.06, y: c.y - s * 0.28),
                           control2: CGPoint(x: bottom.x + r, y: bottom.y - r * 0.8))
                p.addArc(center: bottom, radius: r, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
                p.addCurve(to: top,
                           control1: CGPoint(x: bottom.x - r, y: bottom.y - r * 0.8),
                           control2: CGPoint(x: c.x - s * 0.06, y: c.y - s * 0.28))
            }
        case .patch:
            let w = s * 0.78
            return Path(roundedRect: CGRect(x: c.x - w / 2, y: c.y - w / 2, width: w, height: w), cornerRadius: s * 0.16, style: .continuous)
        }
    }

    private func polygon(sides: Int, radius: CGFloat, offsetY: CGFloat, cornerRadius: CGFloat, rotation: Angle = .zero) -> Path {
        let start = -Double.pi / 2 + rotation.radians
        let points = (0..<sides).map { i -> CGPoint in
            let a = start + Double(i) * 2 * .pi / Double(sides)
            return CGPoint(x: c.x + radius * cos(a), y: c.y + offsetY + radius * sin(a))
        }
        return rounded(points, radius: cornerRadius)
    }

    /// A closed shape through `points` with rounded corners, like a pressed tablet.
    private func rounded(_ points: [CGPoint], radius: CGFloat) -> Path {
        Path { p in
            let n = points.count
            let mid = { (a: CGPoint, b: CGPoint) in CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
            p.move(to: mid(points[n - 1], points[0]))
            for i in 0..<n {
                p.addArc(tangent1End: points[i], tangent2End: points[(i + 1) % n], radius: radius)
            }
            p.closeSubpath()
        }
    }
}

/// Every shape, for checking the drawings side by side.
#Preview {
    LazyVGrid(columns: Array(repeating: GridItem(.fixed(110)), count: 3), spacing: 12) {
        ForEach(PillShape.allCases) { shape in
            VStack {
                PillOutline(shape: shape, scored: [.round, .oval, .oblong].contains(shape), imprint: shape == .round ? "10" : "")
                    .background(Medi.well, in: RoundedRectangle(cornerRadius: 20))
                Text(shape.title).font(.karla(14))
            }
        }
    }
}

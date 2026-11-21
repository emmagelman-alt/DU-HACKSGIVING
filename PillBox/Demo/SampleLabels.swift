import Foundation

/// Text of the sample pharmacy labels used for the demo (and drawn into the label images in Assets).
/// The people, doctors and pharmacies are made up.
struct SampleLabel {
    let title: String
    let asset: String
    let pharmacy: String
    let lines: [String]

    static let all: [SampleLabel] = [
        SampleLabel(title: "Lisinopril 10 mg", asset: "label-lisinopril", pharmacy: "MAIN STREET PHARMACY", lines: [
            "412 Main St, Pittsburgh PA 15213  (412) 555-0142",
            "RX# 6043921            DATE FILLED: 10/28/2026",
            "JORDAN RIVERA",
            "LISINOPRIL 10 MG TABLET",
            "TAKE ONE TABLET BY MOUTH",
            "ONCE DAILY IN THE MORNING",
            "QTY: 30        REFILLS: 2",
            "DR. SARAH CHEN",
            "DISCARD AFTER: 12/16/2026",
            "DESCRIPTION: PINK ROUND TABLET, SCORED, IMPRINT 10"
        ]),
        SampleLabel(title: "Metformin 500 mg (bottle 1)", asset: "label-metformin-a", pharmacy: "MAIN STREET PHARMACY", lines: [
            "412 Main St, Pittsburgh PA 15213  (412) 555-0142",
            "RX# 6043977            DATE FILLED: 11/26/2025",
            "JORDAN RIVERA",
            "METFORMIN HCL 500 MG TABLET",
            "TAKE 1 TABLET BY MOUTH TWICE DAILY",
            "WITH MEALS",
            "QTY: 60        REFILLS: 0",
            "DR. MARCUS PATEL",
            "EXP: 11/26/2026",
            "DESCRIPTION: WHITE OBLONG TABLET, IMPRINT 500"
        ]),
        SampleLabel(title: "Metformin 500 mg (bottle 2)", asset: "label-metformin-b", pharmacy: "MAIN STREET PHARMACY", lines: [
            "412 Main St, Pittsburgh PA 15213  (412) 555-0142",
            "RX# 6051140            DATE FILLED: 11/14/2026",
            "JORDAN RIVERA",
            "METFORMIN HCL 500 MG TABLET",
            "TAKE 1 TABLET BY MOUTH TWICE DAILY",
            "WITH MEALS",
            "QTY: 60        REFILLS: 5",
            "DR. MARCUS PATEL",
            "EXP: 09/2027",
            "DESCRIPTION: WHITE OBLONG TABLET, IMPRINT 500"
        ]),
        SampleLabel(title: "Amoxicillin 500 mg", asset: "label-amoxicillin", pharmacy: "CORNER DRUG PHARMACY #2291", lines: [
            "88 Forbes Ave, Pittsburgh PA 15213  (412) 555-0177",
            "RX# 7781204            FILLED: 11/19/2026",
            "JORDAN RIVERA",
            "AMOXICILLIN 500 MG CAPSULE",
            "TAKE 1 CAPSULE BY MOUTH EVERY 8 HOURS",
            "UNTIL ALL GONE",
            "QTY: 30        NO REFILLS",
            "DR. SARAH CHEN",
            "USE BY: 12/03/2026",
            "DESCRIPTION: PINK AND RED CAPSULE"
        ]),
        SampleLabel(title: "Atorvastatin 20 mg", asset: "label-atorvastatin", pharmacy: "MAIN STREET PHARMACY", lines: [
            "412 Main St, Pittsburgh PA 15213  (412) 555-0142",
            "RX# 5998310            DATE FILLED: 11/18/2025",
            "JORDAN RIVERA",
            "ATORVASTATIN 20 MG TABLET",
            "TAKE ONE TABLET BY MOUTH AT BEDTIME",
            "AVOID GRAPEFRUIT JUICE",
            "QTY: 90        REFILLS: 1",
            "DR. SARAH CHEN",
            "EXP: 11/18/2026",
            "DESCRIPTION: WHITE OVAL TABLET, IMPRINT 20"
        ]),
        SampleLabel(title: "Levothyroxine 75 mcg", asset: "label-levothyroxine", pharmacy: "MAIN STREET PHARMACY", lines: [
            "412 Main St, Pittsburgh PA 15213  (412) 555-0142",
            "RX# 6058812            DATE FILLED: 11/20/2026",
            "JORDAN RIVERA",
            "LEVOTHYROXINE 75 MCG TABLET",
            "TAKE 1 TABLET BY MOUTH EVERY MORNING",
            "ON AN EMPTY STOMACH",
            "QTY: 90        REFILLS: 3",
            "DR. MARCUS PATEL",
            "EXP: 11/20/2027",
            "DESCRIPTION: PURPLE CAPSULE-SHAPED TABLET, SCORED, IMPRINT 75"
        ]),
        SampleLabel(title: "Vitamin D3 1000 IU", asset: "label-vitamind", pharmacy: "MAIN STREET PHARMACY", lines: [
            "412 Main St, Pittsburgh PA 15213  (412) 555-0142",
            "RX# 6012255            DATE FILLED: 09/02/2026",
            "JORDAN RIVERA",
            "VITAMIN D3 1000 IU SOFTGEL",
            "TAKE 1 SOFTGEL BY MOUTH DAILY",
            "WITH FOOD",
            "QTY: 120       REFILLS: 3",
            "DR. SARAH CHEN",
            "EXP: 03/2028",
            "DESCRIPTION: YELLOW OVAL SOFTGEL"
        ])
    ]

    /// All lines including the pharmacy name, as the label reads top to bottom.
    var fullText: [String] { [pharmacy] + lines }
}

import Foundation

/// Medication names MEDI knows. They pick out the drug name on a label, fix small misreads
/// ("LISINOPRLL" → "Lisinopril"), and help text recognition on photos.
enum KnownDrugs {
    static let generics: [String] = [
        "Acetaminophen", "Acyclovir", "Albuterol", "Alendronate", "Allopurinol", "Alprazolam", "Amiodarone",
        "Amlodipine", "Amoxicillin", "Amphetamine", "Anastrozole", "Apixaban", "Aripiprazole", "Armodafinil", "Aspirin",
        "Atenolol", "Atomoxetine", "Atorvastatin", "Azithromycin", "Baclofen", "Benazepril", "Benzonatate",
        "Bisoprolol", "Budesonide", "Bumetanide", "Buprenorphine", "Bupropion", "Buspirone", "Calcium Carbonate",
        "Carbamazepine", "Carbidopa", "Carvedilol", "Cefdinir", "Cefuroxime", "Cephalexin", "Cetirizine",
        "Chlorthalidone", "Ciprofloxacin", "Citalopram", "Clindamycin", "Clonazepam", "Clonidine", "Clopidogrel",
        "Colchicine", "Cyanocobalamin", "Cyclobenzaprine", "Dapagliflozin", "Desvenlafaxine", "Dexamethasone",
        "Dexmethylphenidate", "Dextroamphetamine", "Diazepam", "Dicyclomine", "Digoxin", "Diltiazem",
        "Diphenhydramine", "Divalproex", "Docusate", "Donepezil", "Doxazosin", "Doxycycline", "Dulaglutide",
        "Duloxetine", "Empagliflozin", "Enalapril", "Escitalopram", "Esomeprazole", "Estradiol", "Eszopiclone",
        "Ezetimibe", "Famotidine", "Fenofibrate", "Ferrous Sulfate", "Fexofenadine", "Finasteride", "Fluconazole",
        "Fluoxetine", "Fluticasone", "Folic Acid", "Furosemide", "Gabapentin", "Gemfibrozil", "Glimepiride",
        "Glipizide", "Guanfacine", "Haloperidol", "Hydralazine", "Hydrochlorothiazide", "Hydrocodone",
        "Hydrocortisone", "Hydroxychloroquine", "Hydroxyzine", "Ibuprofen", "Insulin", "Ipratropium", "Irbesartan",
        "Isosorbide", "Labetalol", "Lamotrigine", "Lansoprazole", "Letrozole", "Levetiracetam", "Levocetirizine",
        "Levodopa", "Levofloxacin", "Levothyroxine", "Liothyronine", "Liraglutide", "Lisdexamfetamine", "Lisinopril",
        "Lithium", "Loperamide", "Loratadine", "Lorazepam", "Losartan", "Lurasidone", "Magnesium Oxide", "Meclizine",
        "Medroxyprogesterone", "Melatonin", "Meloxicam", "Memantine", "Metformin", "Methocarbamol", "Methotrexate",
        "Methylphenidate", "Methylprednisolone", "Metoclopramide", "Metoprolol", "Metronidazole", "Mirabegron",
        "Mirtazapine", "Modafinil", "Mometasone", "Montelukast", "Morphine", "Naloxone", "Naltrexone", "Naproxen",
        "Nebivolol", "Nifedipine", "Nitrofurantoin", "Nitroglycerin", "Norethindrone", "Olanzapine", "Olmesartan",
        "Omeprazole", "Ondansetron", "Oseltamivir", "Oxcarbazepine", "Oxybutynin", "Oxycodone", "Pantoprazole",
        "Paroxetine", "Penicillin", "Phentermine", "Pioglitazone", "Potassium Chloride", "Pramipexole", "Pravastatin",
        "Prazosin", "Prednisolone", "Prednisone", "Pregabalin", "Progesterone", "Promethazine", "Propranolol",
        "Quetiapine", "Quinapril", "Raloxifene", "Ramipril", "Risperidone", "Rivaroxaban", "Rizatriptan",
        "Ropinirole", "Rosuvastatin", "Semaglutide", "Sertraline", "Sildenafil", "Simvastatin", "Sitagliptin",
        "Spironolactone", "Sucralfate", "Sulfamethoxazole", "Sumatriptan", "Tadalafil", "Tamoxifen", "Tamsulosin",
        "Telmisartan", "Temazepam", "Terazosin", "Terbinafine", "Tiotropium", "Tirzepatide", "Tizanidine",
        "Tolterodine", "Topiramate", "Torsemide", "Tramadol", "Trazodone", "Triamcinolone", "Triamterene",
        "Trimethoprim", "Valacyclovir", "Valproic Acid", "Valsartan", "Varenicline", "Venlafaxine", "Verapamil",
        "Vitamin D3", "Vortioxetine", "Warfarin", "Ziprasidone", "Zolpidem"
    ]

    /// Brand names as pharmacies print them, release suffix included.
    static let brands: [String] = [
        "Abilify", "Adderall", "Adderall XR", "Advair", "Aldactone", "Allegra", "Ambien", "Aricept", "Armour Thyroid",
        "Ativan", "Augmentin", "Azstarys", "Bactrim", "Basaglar", "Benadryl", "Benicar", "Brilinta", "Buspar",
        "Cardizem", "Celebrex", "Celexa", "Chantix", "Cialis", "Cipro", "Claritin", "Concerta", "Coreg", "Coumadin",
        "Cozaar", "Crestor", "Cymbalta", "Cytomel", "Daytrana", "Deltasone", "Depakote", "Desyrel", "Detrol",
        "Diflucan", "Diovan", "Ditropan XL", "Dupixent", "Dyanavel XR", "Effexor XR", "Eliquis", "Entresto",
        "Estrace", "Evekeo", "Farxiga", "Flexeril", "Flomax", "Flonase", "Focalin", "Focalin XR", "Fosamax",
        "Glucophage", "Humalog", "Humira", "Imitrex", "Intuniv", "Invokana", "Janumet", "Januvia", "Jardiance",
        "Jornay PM", "Keflex", "Keppra", "Klonopin", "Lamictal", "Lanoxin", "Lantus", "Lasix", "Latuda", "Levaquin",
        "Levemir", "Levoxyl", "Lexapro", "Lipitor", "Lopressor", "Lunesta", "Lyrica", "Macrobid", "Maxalt", "Medrol",
        "Mirapex", "Mobic", "Mounjaro", "Mydayis", "Myrbetriq", "Namenda", "Neurontin", "Nexium", "Norco", "Norvasc",
        "Novolog", "Nurtec ODT", "Nuvigil", "Ozempic", "Paxil", "Paxlovid", "Pepcid", "Percocet", "Plaquenil",
        "Plavix", "Pravachol", "Premarin", "Prilosec", "Prinivil", "Pristiq", "ProAir", "Proscar", "Protonix",
        "Provera", "Provigil", "Prozac", "Qelbree", "Quillichew ER", "Quillivant XR", "Reglan", "Remeron", "Requip",
        "Restoril", "Rexulti", "Risperdal", "Ritalin", "Ritalin LA", "Rybelsus", "Seroquel", "Sinemet", "Singulair",
        "Spiriva", "Sprintec", "Strattera", "Suboxone", "Symbicort", "Synthroid", "Tamiflu", "Tegretol", "Tenormin",
        "Topamax", "Toprol XL", "Toujeo", "Tresiba", "Trileptal", "Trintellix", "Trulicity", "Ubrelvy", "Ultram",
        "Unithroid", "Valium", "Valtrex", "Ventolin", "Viagra", "Vicodin", "Victoza", "Vraylar", "Vyvanse", "Wegovy",
        "Wellbutrin", "Wellbutrin XL", "Xanax", "Xarelto", "Xyzal", "Yaz", "Zanaflex", "Zepbound", "Zestril", "Zetia",
        "Zithromax", "Zocor", "Zofran", "Zoloft", "Zyprexa", "Zyrtec"
    ]

    static let displayNames = generics + brands
    /// Upper case, for matching label text.
    static let names = displayNames.map { $0.uppercased() }

    /// Release and salt words printed after a drug name. They're kept in capitals ("Metformin ER").
    static let suffixes: Set<String> = ["ER", "XR", "XL", "SR", "CR", "LA", "ODT", "CD", "XT", "EC", "IR", "DR", "HCL", "HCT", "DS", "PM"]

    /// A known name found on a line: what to show, and the index of the last word it covered.
    struct Match: Equatable {
        let name: String
        let lastWord: Int
        let exact: Bool
    }

    /// The known medication named in a line of label text, if any. Exact names win; otherwise a name with
    /// one letter misread (two for long names) still counts, as long as the first letter is right.
    static func match(in line: String) -> Match? {
        let words = words(of: line)
        guard !words.isEmpty else { return nil }
        var best: (match: Match, distance: Int, length: Int)?
        func consider(_ e: Entry, distance: Int, last: Int) {
            if let b = best, (b.distance, -b.length) <= (distance, -e.letters.count) { return }
            best = (Match(name: e.display, lastWord: last, exact: distance == 0), distance, e.letters.count)
        }
        for size in 1...min(4, words.count) {
            for start in 0...(words.count - size) {
                let letters = words[start..<start + size].joined()
                if let i = exact[letters] { consider(entries[i], distance: 0, last: start + size - 1); continue }
                guard letters.count >= 6, !labelWords.contains(letters), let first = letters.first else { continue }
                let chars = Array(letters.utf8)
                for i in byFirstLetter[first] ?? [] {
                    let e = entries[i]
                    let allowed = e.letters.count >= 9 ? 2 : 1
                    guard e.letters.count >= 6, abs(e.words - size) <= 1, abs(e.chars.count - chars.count) <= allowed else { continue }
                    let d = editDistance(chars, e.chars, limit: allowed)
                    if d <= allowed { consider(e, distance: d, last: start + size - 1) }
                }
            }
        }
        guard var found = best?.match else { return nil }
        // "METFORMIN ER 500 MG": keep the release word that follows the name.
        if found.name.split(separator: " ").last.map({ !suffixes.contains($0.uppercased()) }) ?? true,
           found.lastWord + 1 < words.count, ["ER", "XR", "XL", "SR", "CR", "LA", "ODT", "DR", "EC"].contains(words[found.lastWord + 1]) {
            found = Match(name: found.name + " " + words[found.lastWord + 1], lastWord: found.lastWord + 1, exact: found.exact)
        }
        return found
    }

    /// True when a known medication name appears as whole words, spelled exactly.
    static func containsExact(_ line: String) -> Bool {
        match(in: line)?.exact == true
    }

    // MARK: Matching

    private struct Entry {
        let display: String
        let letters: String
        let chars: [UInt8]
        let words: Int
    }

    private static func words(of line: String) -> [String] {
        line.uppercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    private static let entries: [Entry] = displayNames.map { d in
        let w = words(of: d)
        let letters = w.joined()
        return Entry(display: d, letters: letters, chars: Array(letters.utf8), words: w.count)
    }
    private static let exact: [String: Int] = Dictionary(entries.enumerated().map { ($1.letters, $0) }, uniquingKeysWith: { a, _ in a })
    private static let byFirstLetter: [Character: [Int]] = Dictionary(grouping: entries.indices) { entries[$0].letters.first ?? " " }

    /// Common label words that must never be "corrected" into a drug name.
    private static let labelWords: Set<String> = [
        "TABLET", "TABLETS", "CAPSULE", "CAPSULES", "CHEWABLE", "MORNING", "EVENING", "BEDTIME", "NIGHTLY", "PHARMACY",
        "REFILLS", "REFILL", "QUANTITY", "DISCARD", "EXPIRES", "EXPIRATION", "PRESCRIBER", "DIRECTIONS", "EXTENDED",
        "RELEASE", "DELAYED", "PATIENT", "WARNING", "CAUTION", "ORIGINAL", "GENERIC", "MANUFACTURER", "DOCTOR",
        "PHYSICIAN", "PROVIDER", "SWALLOW", "STOMACH", "ALCOHOL", "DROWSINESS", "SUNLIGHT", "CHILDREN", "MEDICINE",
        "MEDICATION", "DESCRIPTION", "IMPRINT", "SCORED", "PRESCRIPTION"
    ]

    /// Levenshtein distance, giving up (returning limit + 1) once it's clearly over the limit.
    private static func editDistance(_ a: [UInt8], _ b: [UInt8], limit: Int) -> Int {
        if a == b { return 0 }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            var rowBest = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
                rowBest = min(rowBest, current[j])
            }
            if rowBest > limit { return limit + 1 }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}

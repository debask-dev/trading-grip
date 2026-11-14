#if os(macOS)
import Foundation
import GripCore

/// Language of the app: follows the Mac, or chosen in Settings.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, nl, en
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "Automatisch (taal van je Mac)"
        case .nl: return "Nederlands"
        case .en: return "English"
        }
    }
}

/// Dutch is the source language. English comes from `Translations.swift`: exact sentences, and templates where
/// `{}` stands for an inserted value ("Sluit {}%" → "Close {}%"), so texts with numbers in them translate too.
enum L10n {
    static var isEnglish = false

    static func apply(_ pref: AppLanguage) {
        switch pref {
        case .nl: isEnglish = false
        case .en: isEnglish = true
        case .system: isEnglish = !(Locale.preferredLanguages.first ?? "nl").hasPrefix("nl")
        }
        Fmt.useEnglishNumbers(isEnglish)
        cache.removeAll()
    }

    private struct Template {
        let chunks: [String]       // literal parts between the {} slots
        let english: String
        let longest: String        // quick filter before trying the regex
        let regex: NSRegularExpression
    }

    private static let table: (exact: [String: String], templates: [Template]) = {
        var exact: [String: String] = [:]
        var templates: [Template] = []
        for raw in translationsTSV.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = raw.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let nl = String(parts[0]).replacingOccurrences(of: "\\n", with: "\n")
            let en = String(parts[1]).replacingOccurrences(of: "\\n", with: "\n")
            if nl.contains("{}") {
                let chunks = nl.components(separatedBy: "{}")
                let pattern = "^" + chunks.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "(.+?)") + "$"
                guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { continue }
                templates.append(Template(chunks: chunks, english: en, longest: chunks.max { $0.count < $1.count } ?? "", regex: re))
            } else {
                exact[nl] = en
            }
        }
        // Most specific templates first.
        templates.sort { $0.chunks.joined().count > $1.chunks.joined().count }
        return (exact, templates)
    }()

    private static var cache: [String: String] = [:]

    static func translate(_ s: String) -> String {
        guard isEnglish, !s.isEmpty else { return s }
        if let hit = cache[s] { return hit }
        let out = lookup(s)
        if cache.count > 4000 { cache.removeAll() }
        cache[s] = out
        return out
    }

    private static func lookup(_ s: String) -> String {
        if let e = table.exact[s] { return e }
        let ns = s as NSString
        for t in table.templates where t.longest.isEmpty || s.contains(t.longest) {
            guard let m = t.regex.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { continue }
            var values: [String] = []
            for i in 1..<m.numberOfRanges { values.append(ns.substring(with: m.range(at: i))) }
            var out = ""
            var rest = Substring(t.english)
            var k = 0
            while let r = rest.range(of: "{}") {
                out += rest[rest.startIndex..<r.lowerBound]
                let v = k < values.count ? values[k] : ""
                out += table.exact[v] ?? v          // inserted words ("long", "Stop-loss") translate too
                k += 1
                rest = rest[r.upperBound...]
            }
            return out + rest
        }
        return s
    }
}

/// Translate a Dutch UI text to the current language.
@inline(__always) func T(_ s: String) -> String { L10n.translate(s) }
#endif

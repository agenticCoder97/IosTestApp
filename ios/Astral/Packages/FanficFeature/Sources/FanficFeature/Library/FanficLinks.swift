import Foundation
import Core
import DesignSystem

/// Source pages for a saved story and its authors, opened in Add.
@MainActor
enum FanficLinks {
    static func story(_ fanfic: LocalFanfic) -> URL? {
        guard let url = fanfic.sourceUrl.flatMap(URL.init(string:)) else { return nil }
        return AO3ImportService.workURL(from: url) ?? AO3ImportService.ffnetURL(from: url) ?? url
    }

    static func authors(_ fanfic: LocalFanfic) -> [String] {
        (fanfic.authorsText ?? "").components(separatedBy: ", ")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != "Anonymous" }
    }

    /// AO3 bylines read "pseud (user)" when a pseud is used. FanFiction.net profile
    /// links need an ID the import doesn't keep, so those open a writer search.
    static func author(_ name: String, sourceKey: String) -> URL? {
        switch sourceKey {
        case "ao3":
            if let match = name.wholeMatch(of: /(.+) \((.+)\)/) {
                return URL(string: "https://archiveofourown.org/users/\(segment(String(match.2)))/pseuds/\(segment(String(match.1)))")
            }
            return URL(string: "https://archiveofourown.org/users/\(segment(name))")
        case "ffnet":
            return URL(string: "https://www.fanfiction.net/search/?keywords=\(BrowserAddress.query(name))&type=writer")
        default:
            return nil
        }
    }

    private static func segment(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? text
    }
}


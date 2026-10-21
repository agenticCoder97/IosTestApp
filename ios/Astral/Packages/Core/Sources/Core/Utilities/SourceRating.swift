import Foundation
public enum SourceRating {
    public static func canonical(_ rating: String?) -> String {
        switch (rating ?? "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
        case "g", "general audiences", "k", "k+": "G"
        case "t", "teen and up audiences": "T"
        case "m", "mature": "M"
        case "e", "explicit": "E"
        default: "NR"
        }
    }
}

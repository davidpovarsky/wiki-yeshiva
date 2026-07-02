import Foundation

struct WikiSourceSelection {
    static let defaultsKey = "WMFSelectedWikiSourceIdentifier"

    static var selectedIdentifier: String {
        let identifier = UserDefaults.standard.string(forKey: defaultsKey) ?? "wikipedia"
        return identifier.isEmpty ? "wikipedia" : identifier
    }

    static var isWikipedia: Bool {
        selectedIdentifier == "wikipedia"
    }

    static func siteURL(for baseSiteURL: URL?) -> URL? {
        let identifier = selectedIdentifier

        if identifier == "wikipedia" {
            return baseSiteURL ?? makeURL(host: "he.wikipedia.org")
        }

        if identifier == "wikiYeshiva" {
            return makeURL(host: "www.yeshiva.org.il")
        }

        guard let rootDomain = rootDomain(for: identifier) else {
            return baseSiteURL ?? makeURL(host: "he.wikipedia.org")
        }

        let languageCode = baseSiteURL?.wmf_languageCode ?? "he"
        return makeURL(host: "\(languageCode).\(rootDomain)")
    }

    static func siteURLs(for baseSiteURLs: [URL]) -> [URL] {
        if isWikipedia {
            return baseSiteURLs
        }

        let sourceURLs = baseSiteURLs.isEmpty ? [makeURL(host: "he.wikipedia.org")].compactMap { $0 } : baseSiteURLs
        var seen = Set<String>()

        return sourceURLs.compactMap { baseURL in
            guard let mappedURL = siteURL(for: baseURL) else { return nil }
            guard !seen.contains(mappedURL.absoluteString) else { return nil }
            seen.insert(mappedURL.absoluteString)
            return mappedURL
        }
    }

    private static func makeURL(host: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        return components.url
    }

    private static func rootDomain(for identifier: String) -> String? {
        switch identifier {
        case "wiktionary": return "wiktionary.org"
        case "wikisource": return "wikisource.org"
        case "wikiquote": return "wikiquote.org"
        case "wikibooks": return "wikibooks.org"
        case "wikiversity": return "wikiversity.org"
        case "wikinews": return "wikinews.org"
        case "wikivoyage": return "wikivoyage.org"
        default: return nil
        }
    }
}

import Foundation
import WMFData

@objc public enum WMFWikiSourceIdentifier: Int, CaseIterable {
    case wikipedia
    case wiktionary
    case wikisource
    case wikiYeshiva

    public var stringIdentifier: String {
        switch self {
        case .wikipedia: return "wikipedia"
        case .wiktionary: return "wiktionary"
        case .wikisource: return "wikisource"
        case .wikiYeshiva: return "wikiYeshiva"
        }
    }

    public init(string: String?) {
        switch string {
        case "wiktionary": self = .wiktionary
        case "wikisource": self = .wikisource
        case "wikiYeshiva": self = .wikiYeshiva
        default: self = .wikipedia
        }
    }

    public var displayName: String {
        switch self {
        case .wikipedia: return "ויקיפדיה"
        case .wiktionary: return "ויקימילון"
        case .wikisource: return "ויקיטקסט"
        case .wikiYeshiva: return "ויקישיבה"
        }
    }

    public var defaultHost: String {
        switch self {
        case .wikipedia: return "he.wikipedia.org"
        case .wiktionary: return "he.wiktionary.org"
        case .wikisource: return "he.wikisource.org"
        case .wikiYeshiva: return "www.yeshiva.org.il"
        }
    }

    public var apiPath: String {
        switch self {
        case .wikiYeshiva: return "/wiki/api.php"
        default: return "/w/api.php"
        }
    }

    public var restBasePath: String {
        switch self {
        case .wikiYeshiva: return "/wiki/rest.php"
        default: return "/w/rest.php"
        }
    }

    public var articlePathPrefix: String {
        switch self {
        case .wikiYeshiva: return "/wiki/index.php/"
        default: return "/wiki/"
        }
    }

    public var usesNativePCS: Bool {
        switch self {
        case .wikipedia, .wiktionary: return true
        case .wikisource, .wikiYeshiva: return false
        }
    }

    public func wmfProject(language: WMFLanguage = WMFLanguage(languageCode: "he", languageVariantCode: nil)) -> WMFProject {
        switch self {
        case .wikipedia: return .wikipedia(language)
        case .wiktionary: return .wiktionary(language)
        case .wikisource: return .wikisource(language)
        case .wikiYeshiva: return .wikiYeshiva
        }
    }
}

@objc(WMFWikiSourceManager)
public final class WikiSourceManager: NSObject {

    @objc public static let shared = WikiSourceManager()

    @objc public static let didChangeSourceNotification = Notification.Name("WMFWikiSourceSelectionDidChangeNotification")
    @objc public static let defaultsKey = "WMFSelectedWikiSourceIdentifier"

    private override init() {
        super.init()
    }

    @objc public var activeSource: WMFWikiSourceIdentifier {
        get {
            let string = UserDefaults.standard.string(forKey: Self.defaultsKey)
            return WMFWikiSourceIdentifier(string: string)
        }
        set {
            let previous = activeSource
            guard previous != newValue else { return }
            UserDefaults.standard.set(newValue.stringIdentifier, forKey: Self.defaultsKey)
            UserDefaults.standard.synchronize()
            NotificationCenter.default.post(name: Self.didChangeSourceNotification, object: self, userInfo: ["source": newValue.stringIdentifier])
        }
    }

    @objc public var activeSourceIdentifier: String {
        get { activeSource.stringIdentifier }
        set { activeSource = WMFWikiSourceIdentifier(string: newValue) }
    }

    @objc public var isCurrentSourceWikipedia: Bool {
        activeSource == .wikipedia
    }

    @objc public var currentSiteURL: URL {
        siteURL(for: nil) ?? URL(string: "https://\(activeSource.defaultHost)")!
    }

    public var currentProject: WMFProject {
        activeSource.wmfProject()
    }

    @objc public func siteURL(for baseSiteURL: URL?) -> URL? {
        let source = activeSource
        if source == .wikipedia {
            return baseSiteURL ?? makeURL(host: source.defaultHost)
        }
        if source == .wikiYeshiva {
            return makeURL(host: source.defaultHost)
        }

        // For Wiktionary and Wikisource, map language from baseSiteURL or default to "he"
        let languageCode = baseSiteURL?.wmf_languageCode ?? "he"
        let rootDomain: String
        switch source {
        case .wiktionary: rootDomain = "wiktionary.org"
        case .wikisource: rootDomain = "wikisource.org"
        default: rootDomain = "wikipedia.org"
        }
        return makeURL(host: "\(languageCode).\(rootDomain)")
    }

    @objc public func siteURLs(for baseSiteURLs: [URL]) -> [URL] {
        if isCurrentSourceWikipedia {
            return baseSiteURLs
        }

        let sourceURLs = baseSiteURLs.isEmpty ? [currentSiteURL] : baseSiteURLs
        var seen = Set<String>()

        return sourceURLs.compactMap { baseURL in
            guard let mappedURL = siteURL(for: baseURL) else { return nil }
            guard !seen.contains(mappedURL.absoluteString) else { return nil }
            seen.insert(mappedURL.absoluteString)
            return mappedURL
        }
    }

    @objc public func isWikiYeshivaHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "www.yeshiva.org.il" || host == "yeshiva.org.il"
    }

    @objc public func isNativeWikiHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        if isWikiYeshivaHost(host) { return true }
        let domains = ["wikipedia.org", "wiktionary.org", "wikisource.org", "wikiquote.org", "wikibooks.org", "wikiversity.org", "wikinews.org", "wikivoyage.org"]
        return domains.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    @objc public func articleURL(forSiteURL siteURL: URL, title: String) -> URL? {
        let source = sourceIdentifier(forHost: siteURL.host)
        var components = URLComponents(url: siteURL, resolvingAgainstBaseURL: false) ?? URLComponents()
        components.scheme = "https"
        components.host = siteURL.host ?? source.defaultHost

        let denormalizedTitle = title.replacingOccurrences(of: " ", with: "_")
        let encodedTitle = denormalizedTitle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? denormalizedTitle

        let prefix = source.articlePathPrefix
        components.percentEncodedPath = prefix + encodedTitle
        return components.url
    }

    @objc public func title(fromArticleURL url: URL) -> String? {
        let path = url.path
        let prefix: String
        if path.hasPrefix("/wiki/index.php/") {
            prefix = "/wiki/index.php/"
        } else if path.hasPrefix("/wiki/") {
            prefix = "/wiki/"
        } else {
            return nil
        }

        let subpath = String(path.dropFirst(prefix.count))
        guard !subpath.isEmpty else { return nil }
        return subpath.removingPercentEncoding?.replacingOccurrences(of: "_", with: " ")
    }

    @objc public func apiURL(for siteURL: URL?) -> URL? {
        let targetSite = siteURL ?? currentSiteURL
        let source = sourceIdentifier(forHost: targetSite.host)
        var components = URLComponents(url: targetSite, resolvingAgainstBaseURL: false) ?? URLComponents()
        components.scheme = "https"
        components.path = source.apiPath
        return components.url
    }

    public func sourceIdentifier(forHost host: String?) -> WMFWikiSourceIdentifier {
        guard let host = host?.lowercased() else { return activeSource }
        if host.contains("yeshiva.org.il") { return .wikiYeshiva }
        if host.contains("wiktionary.org") { return .wiktionary }
        if host.contains("wikisource.org") { return .wikisource }
        if host.contains("wikipedia.org") { return .wikipedia }
        return activeSource
    }

    private func makeURL(host: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        return components.url
    }
}

public struct WikiSourceSelection {
    public static var selectedIdentifier: String {
        WikiSourceManager.shared.activeSourceIdentifier
    }
    public static var isWikipedia: Bool {
        WikiSourceManager.shared.isCurrentSourceWikipedia
    }
    public static func siteURL(for baseSiteURL: URL?) -> URL? {
        WikiSourceManager.shared.siteURL(for: baseSiteURL)
    }
    public static func siteURLs(for baseSiteURLs: [URL]) -> [URL] {
        WikiSourceManager.shared.siteURLs(for: baseSiteURLs)
    }
}

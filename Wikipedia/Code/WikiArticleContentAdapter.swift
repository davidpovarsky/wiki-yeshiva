import Foundation

public protocol WikiArticleContentAdapter: AnyObject {
    func canHandleMobileHTMLRequest(_ url: URL?) -> Bool
    func upstreamRequest(forMobileHTMLRequest url: URL) -> URLRequest?
    func title(fromMobileHTMLRequest url: URL) -> String?
    func adaptedMobileHTMLDocument(from upstreamData: Data, urlResponse: HTTPURLResponse, title: String) -> String?
}

public enum WikiArticleContentAdapterRegistry {
    private static let adapters: [WikiArticleContentAdapter] = [
        WikisourceArticleAdapter(),
        WikiYeshivaArticleAdapter()
    ]

    public static func adapter(forMobileHTMLRequest url: URL?) -> WikiArticleContentAdapter? {
        guard let url = url else { return nil }
        return adapters.first { $0.canHandleMobileHTMLRequest(url) }
    }
}

// MARK: - Wikisource Adapter

public final class WikisourceArticleAdapter: WikiArticleContentAdapter {
    public let host = "he.wikisource.org"

    public func canHandleMobileHTMLRequest(_ url: URL?) -> Bool {
        guard let url = url, let host = url.host?.lowercased() else { return false }
        return host == self.host && url.pathComponents.contains("mobile-html")
    }

    public func title(fromMobileHTMLRequest url: URL) -> String? {
        extractTitle(fromMobileHTMLURL: url)
    }

    public func upstreamRequest(forMobileHTMLRequest url: URL) -> URLRequest? {
        guard let title = title(fromMobileHTMLRequest: url) else { return nil }
        let denormalized = title.replacingOccurrences(of: " ", with: "_")
        guard let encodedTitle = denormalized.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let restURL = URL(string: "https://\(host)/w/rest.php/v1/page/\(encodedTitle)/html") else {
            return nil
        }
        var request = URLRequest(url: restURL)
        request.setValue("text/html; charset=utf-8", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 WikipediaApp/7.5.0", forHTTPHeaderField: "User-Agent")
        return request
    }

    public func adaptedMobileHTMLDocument(from upstreamData: Data, urlResponse: HTTPURLResponse, title: String) -> String? {
        guard let rawHTML = String(data: upstreamData, encoding: .utf8) else { return nil }
        let baseURL = URL(string: "https://\(host)/wiki/")!
        return WikiHTMLTemplate.wrapHTML(rawHTML, title: title, baseURL: baseURL, languageCode: "he", isRTL: true)
    }
}

// MARK: - WikiYeshiva Adapter

public final class WikiYeshivaArticleAdapter: WikiArticleContentAdapter {
    public let host = "www.yeshiva.org.il"

    public func canHandleMobileHTMLRequest(_ url: URL?) -> Bool {
        guard let url = url, let host = url.host?.lowercased() else { return false }
        let isYeshiva = host == self.host || host == "yeshiva.org.il"
        return isYeshiva && url.pathComponents.contains("mobile-html")
    }

    public func title(fromMobileHTMLRequest url: URL) -> String? {
        extractTitle(fromMobileHTMLURL: url)
    }

    public func upstreamRequest(forMobileHTMLRequest url: URL) -> URLRequest? {
        guard let title = title(fromMobileHTMLRequest: url) else { return nil }
        let denormalized = title.replacingOccurrences(of: " ", with: "_")
        guard let encodedTitle = denormalized.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let restURL = URL(string: "https://\(host)/wiki/rest.php/v1/page/\(encodedTitle)/html") else {
            return nil
        }
        var request = URLRequest(url: restURL)
        request.setValue("text/html; charset=utf-8", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 WikipediaApp/7.5.0", forHTTPHeaderField: "User-Agent")
        return request
    }

    public func adaptedMobileHTMLDocument(from upstreamData: Data, urlResponse: HTTPURLResponse, title: String) -> String? {
        guard let rawHTML = String(data: upstreamData, encoding: .utf8) else { return nil }
        // Clean out any Facebook iframe or tracker widgets if present
        let cleanedHTML = sanitizeYeshivaHTML(rawHTML)
        let baseURL = URL(string: "https://\(host)/wiki/index.php/")!
        return WikiHTMLTemplate.wrapHTML(cleanedHTML, title: title, baseURL: baseURL, languageCode: "he", isRTL: true)
    }

    private func sanitizeYeshivaHTML(_ html: String) -> String {
        var result = html
        // Remove Facebook iframe table if present
        if let fbStart = result.range(of: "<table"),
           let fbEnd = result.range(of: "</table>"),
           fbStart.lowerBound < fbEnd.upperBound {
            let tableSub = result[fbStart.lowerBound..<fbEnd.upperBound]
            if tableSub.contains("facebook.com") || tableSub.contains("fb-root") {
                result.removeSubrange(fbStart.lowerBound..<fbEnd.upperBound)
            }
        }
        return result
    }
}

// MARK: - Helper Functions

private func extractTitle(fromMobileHTMLURL url: URL) -> String? {
    guard let index = url.pathComponents.firstIndex(of: "mobile-html") else { return nil }
    let remaining = url.pathComponents.dropFirst(index + 1)
    guard let first = remaining.first, !first.isEmpty else { return nil }
    return first.removingPercentEncoding?.replacingOccurrences(of: "_", with: " ")
}

// MARK: - HTML Wrapper & PCS Shim

private enum WikiHTMLTemplate {
    private static let pcsShimJS = """
    (function(){
      window.wmf = window.wmf || {};
      window.wmf.elementLocation = window.wmf.elementLocation || {};
      window.wmf.elementLocation.getFirstOnScreenSection = function() {
        return { id: -1, anchor: '' };
      };
      window.wmf.findInPage = window.wmf.findInPage || {};
      window.wmf.findInPage.removeSearchTermHighlights = function() {};

      window.pcs = window.pcs || {};
      window.pcs.c1 = window.pcs.c1 || {};
      window.pcs.c1.Themes = { LIGHT: 'LIGHT', DARK: 'DARK', BLACK: 'BLACK', SEPIA: 'SEPIA' };
      window.pcs.c1.Page = {
        getLeadImage: function() { return null; },
        getTableOfContents: function() {
          var headings = document.querySelectorAll('h2, h3, h4');
          return Array.prototype.map.call(headings, function(h, i) {
            if (!h.id) { h.id = 'section-' + (i + 1); }
            var level = parseInt(h.tagName.replace('H', ''), 10) - 1;
            return {
              id: i + 1,
              level: Math.max(level, 1),
              anchor: h.id,
              title: (h.textContent || '').trim()
            };
          }).filter(function(item) { return item.title.length > 0; });
        },
        setTheme: function(theme) {
          document.documentElement.setAttribute('data-theme', theme);
        },
        setMargins: function(margins) {
          if (margins && margins.top) { document.body.style.paddingTop = margins.top; }
          if (margins && margins.bottom) { document.body.style.paddingBottom = margins.bottom; }
        },
        setTextSizeAdjustmentPercentage: function(percentage) {
          document.documentElement.style.fontSize = percentage;
        },
        setEditButtons: function() {},
        prepareForScrollToAnchor: function(anchor) {
          var el = document.getElementById(anchor);
          if (el) { el.scrollIntoView(); }
        },
        removeHighlightsFromHighlightedElements: function() {}
      };
      window.pcs.c1.Footer = { add: function() {} };
    })();
    """

    static func wrapHTML(_ bodyContent: String, title: String, baseURL: URL, languageCode: String, isRTL: Bool) -> String {
        let direction = isRTL ? "rtl" : "ltr"
        let escapedTitle = title
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        return """
        <!doctype html>
        <html lang="\(languageCode)" dir="\(direction)" data-theme="LIGHT">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=yes">
          <base href="\(baseURL.absoluteString)">
          <title>\(escapedTitle)</title>
          <style>
            :root {
              --bg-color: #ffffff;
              --text-color: #202122;
              --link-color: #3366cc;
              --border-color: #eaecf0;
              --secondary-text: #72777d;
            }
            [data-theme="DARK"] {
              --bg-color: #101418;
              --text-color: #ebebeb;
              --link-color: #6999ff;
              --border-color: #272d33;
              --secondary-text: #9aa0a7;
            }
            [data-theme="BLACK"] {
              --bg-color: #000000;
              --text-color: #ffffff;
              --link-color: #6999ff;
              --border-color: #202122;
              --secondary-text: #808080;
            }
            [data-theme="SEPIA"] {
              --bg-color: #f8f1e3;
              --text-color: #3a322c;
              --link-color: #7b4f2c;
              --border-color: #e5d9c5;
              --secondary-text: #7f7365;
            }
            html, body {
              margin: 0;
              padding: 0;
              direction: \(direction);
              background-color: var(--bg-color);
              color: var(--text-color);
              -webkit-text-size-adjust: 100%;
            }
            body {
              padding: 16px 18px 48px 18px;
              font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
              font-size: 1.05rem;
              line-height: 1.68;
              word-wrap: break-word;
            }
            main {
              max-width: 960px;
              margin: 0 auto;
            }
            h1.article-title {
              font-size: 1.85rem;
              font-weight: 700;
              line-height: 1.3;
              margin: 16px 0 20px 0;
              padding-bottom: 8px;
              border-bottom: 1px solid var(--border-color);
            }
            h2 {
              font-size: 1.4rem;
              font-weight: 700;
              margin: 28px 0 14px 0;
              border-bottom: 1px solid var(--border-color);
              padding-bottom: 4px;
            }
            h3 {
              font-size: 1.2rem;
              font-weight: 600;
              margin: 20px 0 10px 0;
            }
            h4, h5, h6 {
              font-size: 1.05rem;
              font-weight: 600;
              margin: 16px 0 8px 0;
            }
            p {
              margin: 0 0 14px 0;
            }
            a {
              color: var(--link-color);
              text-decoration: none;
            }
            a:active {
              opacity: 0.7;
            }
            img {
              max-width: 100%;
              height: auto;
            }
            table {
              border-collapse: collapse;
              max-width: 100%;
              overflow-x: auto;
              display: block;
              margin: 14px 0;
            }
            th, td {
              border: 1px solid var(--border-color);
              padding: 8px 12px;
            }
            blockquote {
              margin: 14px 20px;
              padding: 8px 14px;
              border-inline-start: 4px solid var(--border-color);
              color: var(--secondary-text);
            }
            ul, ol {
              padding-inline-start: 24px;
              margin: 0 0 14px 0;
            }
            li {
              margin-bottom: 6px;
            }
          </style>
          <script>
          \(pcsShimJS)
          </script>
        </head>
        <body>
          <main>
            <h1 class="article-title">\(escapedTitle)</h1>
            <div id="content-body">
              \(bodyContent)
            </div>
          </main>
        </body>
        </html>
        """
    }
}

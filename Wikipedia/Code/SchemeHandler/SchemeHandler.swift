import WebKit
import WMFNativeLocalizations
import WMFData

enum SchemeHandlerError: Error {
    case invalidParameters
    case createHTTPURLResponseFailure
    case unexpectedResponse
    
    public var errorDescription: String? {
         return CommonStrings.genericErrorDescription
    }
}

class SchemeHandler: NSObject {
    let scheme: String
    open var didReceiveDataCallback: ((WKURLSchemeTask, Data) -> Void)?
    private let session: Session
    private var activeSessionTasks: [URLRequest: URLSessionTask] = [:]
    private var activeCacheOperations: [URLRequest: Operation] = [:]
    private var activeSchemeTasks = NSMutableSet(array: [])
    
    private let cacheQueue: OperationQueue = OperationQueue()
    private let pageLoadMeasurementUrlString = "page/mobile-html/"

    required init(scheme: String, session: Session) {
        self.scheme = scheme
        self.session = session
    }
}

private struct WikiSiteProfile {
    let host: String
    let languageCode: String
    let isRTL: Bool
    let articleBaseURL: URL
}

private protocol WikiArticleContentAdapter {
    func canHandleMobileHTMLRequest(_ url: URL?) -> Bool
    func upstreamRequest(forMobileHTMLRequest url: URL) -> URLRequest?
    func title(fromMobileHTMLRequest url: URL) -> String?
    func adaptedMobileHTMLDocument(from upstreamHTML: String, title: String) -> String
}

private enum WikiSiteRegistry {
    static let articleAdapters: [WikiArticleContentAdapter] = [
        WikiYeshivaArticleAdapter(siteProfile: WikiSiteProfile(
            host: "www.yeshiva.org.il",
            languageCode: "he",
            isRTL: true,
            articleBaseURL: URL(string: "https://www.yeshiva.org.il/wiki/")!
        ))
    ]

    static func articleAdapter(forMobileHTMLRequest url: URL?) -> WikiArticleContentAdapter? {
        return articleAdapters.first { $0.canHandleMobileHTMLRequest(url) }
    }
}

private struct WikiYeshivaArticleAdapter: WikiArticleContentAdapter {
    let siteProfile: WikiSiteProfile
    private let pcsShimBase64 = "KGZ1bmN0aW9uKCl7d2luZG93LndtZj13aW5kb3cud21mfHx7fTt3aW5kb3cud21mLmVsZW1lbnRMb2NhdGlvbj13aW5kb3cud21mLmVsZW1lbnRMb2NhdGlvbnx8e307d2luZG93LndtZi5lbGVtZW50TG9jYXRpb24uZ2V0Rmlyc3RPblNjcmVlblNlY3Rpb249ZnVuY3Rpb24oKXtyZXR1cm57aWQ6LTEsYW5jaG9yOicnfTt9O3dpbmRvdy53bWYuZmluZEluUGFnZT13aW5kb3cud21mLmZpbmRJblBhZ2V8fHt9O3dpbmRvdy53bWYuZmluZEluUGFnZS5yZW1vdmVTZWFyY2hUZXJtSGlnaGxpZ2h0cz1mdW5jdGlvbigpe307d2luZG93LnBjcz13aW5kb3cucGNzfHx7fTt3aW5kb3cucGNzLmMxPXdpbmRvdy5wY3MuYzF8fHt9O3dpbmRvdy5wY3MuYzEuVGhlbWVzPXtMSUdIVDonTElHSFQnLERBUks6J0RBUksnLEJMQUNLOidCTEFDSycsU0VQSUE6J1NFUElBJ307d2luZG93LnBjcy5jMS5QYWdlPXtnZXRMZWFkSW1hZ2U6ZnVuY3Rpb24oKXtyZXR1cm4gbnVsbDt9LGdldFRhYmxlT2ZDb250ZW50czpmdW5jdGlvbigpe3ZhciBoZWFkaW5ncz1kb2N1bWVudC5xdWVyeVNlbGVjdG9yQWxsKCdoMixoMyxoNCcpO3JldHVybiBBcnJheS5wcm90b3R5cGUubWFwLmNhbGwoaGVhZGluZ3MsZnVuY3Rpb24oaGVhZGluZyxpbmRleCl7aWYoIWhlYWRpbmcuaWQpe2hlYWRpbmcuaWQ9J3NlY3Rpb24tJysoaW5kZXgrMSk7fXZhciBsZXZlbD1wYXJzZUludChoZWFkaW5nLnRhZ05hbWUucmVwbGFjZSgnSCcsJycpLDEwKS0xO3JldHVybntpZDppbmRleCsxLGxldmVsOk1hdGgubWF4KGxldmVsLDEpLGFuY2hvcjpoZWFkaW5nLmlkLHRpdGxlOihoZWFkaW5nLnRleHRDb250ZW50fHwnJykudHJpbSgpfTt9KS5maWx0ZXIoZnVuY3Rpb24oaXRlbSl7cmV0dXJuIGl0ZW0udGl0bGUubGVuZ3RoPjA7fSk7fSxzZXRUaGVtZTpmdW5jdGlvbih0aGVtZSl7ZG9jdW1lbnQuZG9jdW1lbnRFbGVtZW50LnNldEF0dHJpYnV0ZSgnZGF0YS10aGVtZScsdGhlbWUpO30sc2V0TWFyZ2luczpmdW5jdGlvbihtYXJnaW5zKXtpZihtYXJnaW5zJiZtYXJnaW5zLnRvcCl7ZG9jdW1lbnQuYm9keS5zdHlsZS5wYWRkaW5nVG9wPW1hcmdpbnMudG9wO31pZihtYXJnaW5zJiZtYXJnaW5zLmJvdHRvbSl7ZG9jdW1lbnQuYm9keS5zdHlsZS5wYWRkaW5nQm90dG9tPW1hcmdpbnMuYm90dG9tO319LHNldFRleHRTaXplQWRqdXN0bWVudFBlcmNlbnRhZ2U6ZnVuY3Rpb24ocGVyY2VudGFnZSl7ZG9jdW1lbnQuZG9jdW1lbnRFbGVtZW50LnN0eWxlLmZvbnRTaXplPXBlcmNlbnRhZ2U7fSxzZXRFZGl0QnV0dG9uczpmdW5jdGlvbigpe30scHJlcGFyZUZvclNjcm9sbFRvQW5jaG9yOmZ1bmN0aW9uKGFuY2hvcil7dmFyIGVsZW1lbnQ9ZG9jdW1lbnQuZ2V0RWxlbWVudEJ5SWQoYW5jaG9yKTtpZihlbGVtZW50KXtlbGVtZW50LnNjcm9sbEludG9WaWV3KCk7fX0scmVtb3ZlSGlnaGxpZ2h0c0Zyb21IaWdobGlnaHRlZEVsZW1lbnRzOmZ1bmN0aW9uKCl7fX07d2luZG93LnBjcy5jMS5Gb290ZXI9e2FkZDpmdW5jdGlvbigpe319O30pKCk7"

    func canHandleMobileHTMLRequest(_ url: URL?) -> Bool {
        guard let url = url, url.host == siteProfile.host else {
            return false
        }
        let components = url.pathComponents
        return components.contains("page") && components.contains("mobile-html")
    }

    func upstreamRequest(forMobileHTMLRequest url: URL) -> URLRequest? {
        guard let title = title(fromMobileHTMLRequest: url) else {
            return nil
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = siteProfile.host
        components.path = "/wiki/index.php"
        components.queryItems = [
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "action", value: "render")
        ]
        guard let renderURL = components.url else {
            return nil
        }
        var request = URLRequest(url: renderURL)
        request.setValue("text/html; charset=utf-8", forHTTPHeaderField: "Accept")
        return request
    }

    func title(fromMobileHTMLRequest url: URL) -> String? {
        guard let mobileHTMLIndex = url.pathComponents.firstIndex(of: "mobile-html") else {
            return nil
        }
        let titleComponents = url.pathComponents.dropFirst(mobileHTMLIndex + 1)
        guard let encodedTitle = titleComponents.first, !encodedTitle.isEmpty else {
            return nil
        }
        return encodedTitle.removingPercentEncoding?.replacingOccurrences(of: "_", with: " ")
    }

    func adaptedMobileHTMLDocument(from upstreamHTML: String, title: String) -> String {
        let escapedTitle = htmlEscaped(title)
        let normalizedHTML = normalize(upstreamHTML)
        let direction = siteProfile.isRTL ? "rtl" : "ltr"
        let languageCode = siteProfile.languageCode
        let baseURLString = siteProfile.articleBaseURL.absoluteString

        return """
        <!doctype html>
        <html lang="\(languageCode)" dir="\(direction)">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=yes">
          <base href="\(baseURLString)">
          <title>\(escapedTitle)</title>
          <style>
            html, body { margin: 0; padding: 0; direction: \(direction); }
            body { padding: 0 16px 32px 16px; font: -apple-system-body; line-height: 1.65; }
            main { max-width: 920px; margin: 0 auto; }
            h1 { font: -apple-system-title1; font-weight: 700; line-height: 1.25; margin: 20px 0 16px; }
            h2, h3, h4 { line-height: 1.3; margin-top: 1.4em; }
            a { color: #36c; text-decoration: none; }
            img, video { max-width: 100%; height: auto; }
            table { max-width: 100%; border-collapse: collapse; overflow-x: auto; display: block; }
            th, td { border: 1px solid rgba(128,128,128,.35); padding: 6px; }
            #toc, .toc, .reference, .mw-editsection, .noprint, .printfooter, #fb-root, .fb-root { display: none !important; }
          </style>
          <script src="data:text/javascript;base64,\(pcsShimBase64)"></script>
        </head>
        <body>
          <main>
            <h1>\(escapedTitle)</h1>
            <article id="content">\(normalizedHTML)</article>
          </main>
        </body>
        </html>
        """
    }

    private func normalize(_ html: String) -> String {
        var result = html
        result = removingMatches("<script[\\s\\S]*?</script>", from: result)
        result = removingMatches("<iframe[\\s\\S]*?</iframe>", from: result)
        result = removingMatches("<noscript[\\s\\S]*?</noscript>", from: result)
        return result
    }

    private func removingMatches(_ pattern: String, from value: String) -> String {
        return value.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive], range: nil)
    }

    private func htmlEscaped(_ value: String) -> String {
        return value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

extension SchemeHandler: WKURLSchemeHandler {
    
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        assert(Thread.isMainThread)
        
        let originalRequest = urlSchemeTask.request
        guard let originalRequestURL = originalRequest.url else {
            urlSchemeTask.didFailWithError(SchemeHandlerError.invalidParameters)
            return
        }
        guard let components = NSURLComponents(url: originalRequestURL, resolvingAgainstBaseURL: false) else {
            urlSchemeTask.didFailWithError(SchemeHandlerError.invalidParameters)
            return
        }
        
        switch Configuration.current.environment {
        case .local(let options):
            if options.contains(.localPCS) {
                components.scheme = components.host == Configuration.Domain.localhost ? "http" : "https"
            } else {
                components.scheme =  "https"
            }
        default:
            components.scheme =  "https"
        }
        
        guard
            let requestURL = components.url,
            let request = urlRequestWithoutCustomScheme(from: originalRequest, newURL: requestURL)
        else {
            urlSchemeTask.didFailWithError(SchemeHandlerError.invalidParameters)
            return
        }
        
        addSchemeTask(urlSchemeTask: urlSchemeTask)

        if let adapter = WikiSiteRegistry.articleAdapter(forMobileHTMLRequest: request.url) {
            kickOffAdaptedArticleTask(request: request, urlSchemeTask: urlSchemeTask, adapter: adapter)
            return
        }

        let op = BlockOperation { [weak urlSchemeTask] in
            DispatchQueue.main.async {
                guard let urlSchemeTask = urlSchemeTask else {
                    return
                }
                self.activeCacheOperations.removeValue(forKey: urlSchemeTask.request)
                self.kickOffDataTask(request: request, urlSchemeTask: urlSchemeTask)
            }
        }
        activeCacheOperations[urlSchemeTask.request] = op
        cacheQueue.addOperation(op)
        
    }
    
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        assert(Thread.isMainThread)
        
        removeSchemeTask(urlSchemeTask: urlSchemeTask)
        
        if let task = activeSessionTasks[urlSchemeTask.request] {
            removeSessionTask(request: urlSchemeTask.request)

            switch task.state {
            case .canceling:
                fallthrough
            case .completed:
                break
            default:
                task.cancel()
            }
        }
        
        if let op = activeCacheOperations.removeValue(forKey: urlSchemeTask.request) {
            op.cancel()
        }
    }
}

private extension SchemeHandler {
    
    func urlRequestWithoutCustomScheme(from originalRequest: URLRequest, newURL: URL) -> URLRequest? {
        var mutableRequest = originalRequest
        mutableRequest.url = newURL
        
        let containsType = mutableRequest.allHTTPHeaderFields?[Header.persistentCacheItemType] != nil
        let containsIfNoneMatch = mutableRequest.allHTTPHeaderFields?[URLRequest.ifNoneMatchHeaderKey] != nil

        if !containsType {
            let typeHeaders: [String: String]
            if isMimeTypeImage(type: (newURL as NSURL).wmf_mimeTypeForExtension()) {
                typeHeaders = session.typeHeadersForType(.image)
            } else {
                typeHeaders = session.typeHeadersForType(.article)
            }
            for (key, value) in typeHeaders {
                mutableRequest.setValue(value, forHTTPHeaderField: key)
            }
        }
        
        guard !containsIfNoneMatch else {
            return mutableRequest
        }

        let additionalHeaders: [String: String]
        if isMimeTypeImage(type: (newURL as NSURL).wmf_mimeTypeForExtension()) {
            additionalHeaders = session.additionalHeadersForType(.image, urlRequest: mutableRequest)
        } else {
            additionalHeaders = session.additionalHeadersForType(.article, urlRequest: mutableRequest)
        }
        
        for (key, value) in additionalHeaders {
            mutableRequest.setValue(value, forHTTPHeaderField: key)
        }
        
        return mutableRequest
    }
    
    func isMimeTypeImage(type: String) -> Bool {
        return type.hasPrefix("image")
    }

    func kickOffAdaptedArticleTask(request: URLRequest, urlSchemeTask: WKURLSchemeTask, adapter: WikiArticleContentAdapter) {
        guard schemeTaskIsActive(urlSchemeTask: urlSchemeTask),
              let requestURL = request.url,
              let upstreamRequest = adapter.upstreamRequest(forMobileHTMLRequest: requestURL),
              let articleTitle = adapter.title(fromMobileHTMLRequest: requestURL) else {
            urlSchemeTask.didFailWithError(SchemeHandlerError.invalidParameters)
            removeSchemeTask(urlSchemeTask: urlSchemeTask)
            return
        }

        SessionsFunnel.shared.setPageLoadStartTime()

        let dataTask = URLSession.shared.dataTask(with: upstreamRequest) { [weak self, weak urlSchemeTask] data, response, error in
            DispatchQueue.main.async {
                guard let self = self, let urlSchemeTask = urlSchemeTask else {
                    return
                }
                guard self.schemeTaskIsActive(urlSchemeTask: urlSchemeTask) else {
                    return
                }
                defer {
                    self.removeSessionTask(request: urlSchemeTask.request)
                    self.removeSchemeTask(urlSchemeTask: urlSchemeTask)
                }

                if let error = error {
                    SessionsFunnel.shared.clearPageLoadStartTime()
                    urlSchemeTask.didFailWithError(error)
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse,
                      HTTPStatusCode.isSuccessful(httpResponse.statusCode),
                      let data = data,
                      let upstreamHTML = String(data: data, encoding: .utf8),
                      let adaptedData = adapter.adaptedMobileHTMLDocument(from: upstreamHTML, title: articleTitle).data(using: .utf8),
                      let adaptedResponse = HTTPURLResponse(url: requestURL, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-cache"]) else {
                    SessionsFunnel.shared.clearPageLoadStartTime()
                    urlSchemeTask.didFailWithError(SchemeHandlerError.unexpectedResponse)
                    return
                }

                urlSchemeTask.didReceive(adaptedResponse)
                urlSchemeTask.didReceive(adaptedData)
                self.didReceiveDataCallback?(urlSchemeTask, adaptedData)
                urlSchemeTask.didFinish()
                SessionsFunnel.shared.endPageLoadStartTime()
            }
        }

        addSessionTask(request: urlSchemeTask.request, dataTask: dataTask)
        dataTask.resume()
    }
    
    func kickOffDataTask(request: URLRequest, urlSchemeTask: WKURLSchemeTask) {
        guard schemeTaskIsActive(urlSchemeTask: urlSchemeTask) else { return }
        
        if ((urlSchemeTask.request.url?.absoluteString) ?? "").contains(pageLoadMeasurementUrlString) {
            SessionsFunnel.shared.setPageLoadStartTime()
        }
        
        let callback = Session.Callback(response: {  [weak urlSchemeTask] response in
            DispatchQueue.main.async {
                guard let urlSchemeTask = urlSchemeTask else { return }
                guard self.schemeTaskIsActive(urlSchemeTask: urlSchemeTask) else { return }
                if let httpResponse = response as? HTTPURLResponse, !HTTPStatusCode.isSuccessful(httpResponse.statusCode) {
                    let error = RequestError.from(code: httpResponse.statusCode)
                    self.removeSessionTask(request: urlSchemeTask.request)
                    urlSchemeTask.didFailWithError(error)
                    self.removeSchemeTask(urlSchemeTask: urlSchemeTask)
                    if ((urlSchemeTask.request.url?.absoluteString) ?? "").contains(self.pageLoadMeasurementUrlString) {
                        SessionsFunnel.shared.clearPageLoadStartTime()
                    }
                } else {
                    guard self.schemeTaskIsActive(urlSchemeTask: urlSchemeTask) else { return }
                    urlSchemeTask.didReceive(response)
                }
            }
        }, data: { [weak urlSchemeTask] data in
            DispatchQueue.main.async {
                guard let urlSchemeTask = urlSchemeTask else { return }
                guard self.schemeTaskIsActive(urlSchemeTask: urlSchemeTask) else { return }
                urlSchemeTask.didReceive(data)
                self.didReceiveDataCallback?(urlSchemeTask, data)
            }
        }, success: { [weak urlSchemeTask, weak self] usedPermanentCache in
            guard let self else { return }
            DispatchQueue.main.async {
                guard let urlSchemeTask = urlSchemeTask else { return }
                guard self.schemeTaskIsActive(urlSchemeTask: urlSchemeTask) else { return }
                urlSchemeTask.didFinish()
                self.removeSessionTask(request: urlSchemeTask.request)
                self.removeSchemeTask(urlSchemeTask: urlSchemeTask)
                if ((urlSchemeTask.request.url?.absoluteString) ?? "").contains(self.pageLoadMeasurementUrlString) {
                    if usedPermanentCache { SessionsFunnel.shared.clearPageLoadStartTime() } else { SessionsFunnel.shared.endPageLoadStartTime() }
                }
            }
        }, failure: { [weak urlSchemeTask] error in
            DispatchQueue.main.async {
                guard let urlSchemeTask = urlSchemeTask else { return }
                guard self.schemeTaskIsActive(urlSchemeTask: urlSchemeTask) else { return }
                self.removeSessionTask(request: urlSchemeTask.request)
                urlSchemeTask.didFailWithError(error)
                self.removeSchemeTask(urlSchemeTask: urlSchemeTask)
                if ((urlSchemeTask.request.url?.absoluteString) ?? "").contains(self.pageLoadMeasurementUrlString) {
                    SessionsFunnel.shared.clearPageLoadStartTime()
                }
            }
        }, cacheFallbackError: { error in
            DispatchQueue.main.async {
                WMFToastManager.sharedInstance.showErrorAlert(error, sticky: false, dismissPreviousToasts: false)
            }
        })
        
        if let dataTask = session.dataTask(with: request, callback: callback) {
            addSessionTask(request: request, dataTask: dataTask)
            dataTask.resume()
        }
    }
    
    func schemeTaskIsActive(urlSchemeTask: WKURLSchemeTask) -> Bool {
        assert(Thread.isMainThread)
        return activeSchemeTasks.contains(urlSchemeTask)
    }
    
    func removeSchemeTask(urlSchemeTask: WKURLSchemeTask) {
        assert(Thread.isMainThread)
        activeSchemeTasks.remove(urlSchemeTask)
    }
    
    func removeSessionTask(request: URLRequest) {
        assert(Thread.isMainThread)
        activeSessionTasks.removeValue(forKey: request)
    }
    
    func addSchemeTask(urlSchemeTask: WKURLSchemeTask) {
        assert(Thread.isMainThread)
        activeSchemeTasks.add(urlSchemeTask)
    }
    
    func addSessionTask(request: URLRequest, dataTask: URLSessionTask) {
        assert(Thread.isMainThread)
        activeSessionTasks[request] = dataTask
    }
}
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

private enum WikiYeshivaArticleAdapter {
    static let host = "www.yeshiva.org.il"

    static func canHandleMobileHTMLRequest(_ url: URL?) -> Bool {
        guard let url = url, url.host == host else {
            return false
        }

        let components = url.pathComponents
        return components.contains("mobile-html") && components.contains("page")
    }

    static func renderRequest(from url: URL) -> URLRequest? {
        guard let title = title(from: url) else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = host
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

    static func title(from url: URL) -> String? {
        let components = url.pathComponents
        guard let mobileHTMLIndex = components.firstIndex(of: "mobile-html") else {
            return nil
        }

        let titleComponents = components.dropFirst(mobileHTMLIndex + 1)
        guard let encodedTitle = titleComponents.first, !encodedTitle.isEmpty else {
            return nil
        }

        return encodedTitle.removingPercentEncoding?.replacingOccurrences(of: "_", with: " ")
    }

    static func mobileHTMLDocument(renderedHTML: String, title: String) -> String {
        let escapedTitle = htmlEscaped(title)

        return """
        <!doctype html>
        <html lang="he" dir="rtl">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=yes">
          <title>\(escapedTitle)</title>
          <style>
            :root { color-scheme: light dark; }
            body {
              margin: 0;
              padding: 0 16px 32px 16px;
              font: -apple-system-body;
              line-height: 1.65;
              background: Canvas;
              color: CanvasText;
              direction: rtl;
            }
            main { max-width: 920px; margin: 0 auto; }
            h1 { font: -apple-system-title1; font-weight: 700; line-height: 1.25; margin: 20px 0 16px; }
            h2, h3, h4 { line-height: 1.3; margin-top: 1.4em; }
            a { color: #36c; text-decoration: none; }
            a:visited { color: #6b4ba1; }
            img, video { max-width: 100%; height: auto; }
            table { max-width: 100%; border-collapse: collapse; overflow-x: auto; display: block; }
            th, td { border: 1px solid rgba(128,128,128,.35); padding: 6px; }
            .reference, .mw-editsection, .noprint, .printfooter { display: none !important; }
            [data-theme="DARK"], [data-theme="BLACK"] { background: #101418; color: #eaecf0; }
            [data-theme="SEPIA"] { background: #f8f1e3; color: #202122; }
          </style>
          <script>
            (function() {
              function post(action, data) {
                try {
                  if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.pcs) {
                    window.webkit.messageHandlers.pcs.postMessage({ action: action, data: data || {} });
                  }
                } catch (e) {}
              }

              window.pcs = window.pcs || {};
              window.pcs.c1 = window.pcs.c1 || {};
              window.pcs.c1.Themes = { LIGHT: 'LIGHT', DARK: 'DARK', BLACK: 'BLACK', SEPIA: 'SEPIA' };
              window.pcs.c1.Page = {
                setTheme: function(theme) { document.documentElement.setAttribute('data-theme', theme); },
                setMargins: function(margins) {
                  if (margins && margins.top) { document.body.style.paddingTop = margins.top; }
                  if (margins && margins.bottom) { document.body.style.paddingBottom = margins.bottom; }
                },
                setTextSizeAdjustmentPercentage: function(percentage) { document.documentElement.style.fontSize = percentage; },
                setEditButtons: function() {},
                prepareForScrollToAnchor: function(anchor) {
                  var id = String(anchor || '');
                  var el = document.getElementById(id) || document.querySelector('[name="' + CSS.escape(id) + '"]');
                  if (el) { el.scrollIntoView(); }
                },
                removeHighlightsFromHighlightedElements: function() {}
              };
              window.pcs.c1.Footer = { add: function() {} };

              document.addEventListener('click', function(event) {
                var link = event.target.closest && event.target.closest('a');
                if (!link) { return; }
                var href = link.getAttribute('href');
                if (!href) { return; }
                post('link', { href: href, text: link.textContent, title: link.getAttribute('title') });
                event.preventDefault();
              }, true);

              document.addEventListener('DOMContentLoaded', function() {
                post('setup');
                post('tableOfContents', []);
                post('final_setup');
              });
            })();
          </script>
        </head>
        <body>
          <main>
            <h1>\(escapedTitle)</h1>
            <article id="content">\(renderedHTML)</article>
          </main>
        </body>
        </html>
        """
    }

    private static func htmlEscaped(_ value: String) -> String {
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

        if WikiYeshivaArticleAdapter.canHandleMobileHTMLRequest(request.url) {
            kickOffWikiYeshivaArticleAdapterTask(request: request, urlSchemeTask: urlSchemeTask)
            return
        }

        // IMPORTANT: Ensure the urlSchemeTask is not strongly captured by this block operation
        // Otherwise it will sometimes be deallocated on a non-main thread, causing a crash https://phabricator.wikimedia.org/T224113
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
        
        // set persistentCacheItemType in header if it doesn't already exist
        // set If-None-Match in header if it doesn't already exist
        
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

    func kickOffWikiYeshivaArticleAdapterTask(request: URLRequest, urlSchemeTask: WKURLSchemeTask) {
        guard schemeTaskIsActive(urlSchemeTask: urlSchemeTask),
              let requestURL = request.url,
              let renderRequest = WikiYeshivaArticleAdapter.renderRequest(from: requestURL),
              let articleTitle = WikiYeshivaArticleAdapter.title(from: requestURL) else {
            urlSchemeTask.didFailWithError(SchemeHandlerError.invalidParameters)
            removeSchemeTask(urlSchemeTask: urlSchemeTask)
            return
        }

        SessionsFunnel.shared.setPageLoadStartTime()

        let dataTask = URLSession.shared.dataTask(with: renderRequest) { [weak self, weak urlSchemeTask] data, response, error in
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
                      let renderedHTML = String(data: data, encoding: .utf8),
                      let adaptedData = WikiYeshivaArticleAdapter.mobileHTMLDocument(renderedHTML: renderedHTML, title: articleTitle).data(using: .utf8),
                      let adaptedResponse = HTTPURLResponse(url: requestURL, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
                        "Content-Type": "text/html; charset=utf-8",
                        "Cache-Control": "no-cache"
                      ]) else {
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
        guard schemeTaskIsActive(urlSchemeTask: urlSchemeTask) else {
             return
         }
        
        // IMPORTANT: Ensure the urlSchemeTask is not strongly captured by the callback blocks.
        // Otherwise it will sometimes be deallocated on a non-main thread, causing a crash https://phabricator.wikimedia.org/T224113
        
        if ((urlSchemeTask.request.url?.absoluteString) ?? "").contains(pageLoadMeasurementUrlString) {
            SessionsFunnel.shared.setPageLoadStartTime()
        }
        
        let callback = Session.Callback(response: {  [weak urlSchemeTask] response in
            DispatchQueue.main.async {
                guard let urlSchemeTask = urlSchemeTask else {
                    return
                }
                guard self.schemeTaskIsActive(urlSchemeTask: urlSchemeTask) else {
                    return
                }
                if let httpResponse = response as? HTTPURLResponse, !HTTPStatusCode.isSuccessful(httpResponse.statusCode) {
                    let error = RequestError.from(code: httpResponse.statusCode)
                    self.removeSessionTask(request: urlSchemeTask.request)
                    urlSchemeTask.didFailWithError(error)
                    self.removeSchemeTask(urlSchemeTask: urlSchemeTask)
                    
                    if ((urlSchemeTask.request.url?.absoluteString) ?? "").contains(self.pageLoadMeasurementUrlString) {
                        SessionsFunnel.shared.clearPageLoadStartTime()
                    }
                } else {
                    
                    // May fix potential crashes if we have already called urlSchemeTask.didFinish() or webView(_ webView: WKWebView, stop urlSchemeTask) has already been called.
                    // https://developer.apple.com/documentation/webkit/wkurlschemetask/2890839-didreceive
                    guard self.schemeTaskIsActive(urlSchemeTask: urlSchemeTask) else {
                        return
                    }
                    
                    urlSchemeTask.didReceive(response)
                }
            }
        }, data: { [weak urlSchemeTask] data in
            
            DispatchQueue.main.async {
                guard let urlSchemeTask = urlSchemeTask else {
                    return
                }
                guard self.schemeTaskIsActive(urlSchemeTask: urlSchemeTask) else {
                    return
                }
                urlSchemeTask.didReceive(data)
                self.didReceiveDataCallback?(urlSchemeTask, data)
            }
        }, success: { [weak urlSchemeTask, weak self] usedPermanentCache in
            
            guard let self else {
                return
            }
            
            DispatchQueue.main.async {
                guard let urlSchemeTask = urlSchemeTask else {
                    return
                }
                guard self.schemeTaskIsActive(urlSchemeTask: urlSchemeTask) else {
                    return
                }
                urlSchemeTask.didFinish()
                self.removeSessionTask(request: urlSchemeTask.request)
                self.removeSchemeTask(urlSchemeTask: urlSchemeTask)
                
                if ((urlSchemeTask.request.url?.absoluteString) ?? "").contains(self.pageLoadMeasurementUrlString) {
                    
                    // To reduce inaccurate load times, do not consider load time if we had to lean on our local permanent cache (i.e. Saved Articles)
                    if usedPermanentCache {
                        SessionsFunnel.shared.clearPageLoadStartTime()
                    } else {
                        SessionsFunnel.shared.endPageLoadStartTime()
                    }
                }
            }
            
        }, failure: { [weak urlSchemeTask] error in
            
            DispatchQueue.main.async {
                
                guard let urlSchemeTask = urlSchemeTask else {
                    return
                }
                guard self.schemeTaskIsActive(urlSchemeTask: urlSchemeTask) else {
                    return
                }
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

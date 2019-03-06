import WebKit

public protocol WebViewDelegate: class {
    func webView(_ webView: WebView, didProposeVisitToLocation location: URL, withAction action: Action)
    func webViewDidInvalidatePage(_ webView: WebView)
    func webView(_ webView: WebView, didFailJavaScriptEvaluationWithError error: NSError)
}

public protocol WebViewPageLoadDelegate: class {
    func webView(_ webView: WebView, didLoadPageWithRestorationIdentifier restorationIdentifier: String)
}

public protocol WebViewVisitDelegate: class {
    func webView(_ webView: WebView, didStartVisitWithIdentifier identifier: String, hasCachedSnapshot: Bool)
    func webView(_ webView: WebView, didStartRequestForVisitWithIdentifier identifier: String)
    func webView(_ webView: WebView, didCompleteRequestForVisitWithIdentifier identifier: String)
    func webView(_ webView: WebView, didFailRequestForVisitWithIdentifier identifier: String, statusCode: Int)
    func webView(_ webView: WebView, didFinishRequestForVisitWithIdentifier identifier: String)
    func webView(_ webView: WebView, didRenderForVisitWithIdentifier identifier: String)
    func webView(_ webView: WebView, didCompleteVisitWithIdentifier identifier: String, restorationIdentifier: String)
}

open class WebView: WKWebView {
    public weak var delegate: WebViewDelegate?
    public weak var pageLoadDelegate: WebViewPageLoadDelegate?
    public weak var visitDelegate: WebViewVisitDelegate?

    public init(configuration: WKWebViewConfiguration) {
        super.init(frame: CGRect.zero, configuration: configuration)

        let bundle = Bundle(for: type(of: self))
        let source = try! String(contentsOf: bundle.url(forResource: "WebView", withExtension: "js")!, encoding: String.Encoding.utf8)
        let userScript = WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        configuration.userContentController.addUserScript(userScript)
        configuration.userContentController.add(self, name: "turbolinks")

        translatesAutoresizingMaskIntoConstraints = false
        scrollView.decelerationRate = UIScrollView.DecelerationRate.normal
        
        if #available(iOS 11, *) {
            scrollView.contentInsetAdjustmentBehavior = .never
        }
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    open override func load(_ request: URLRequest) -> WKNavigation? {
        requestWithRedirectHandling(request, success: { (newRequest , response, data) in
            DispatchQueue.main.async {
                if let data = data, let response = response {
                    let _ = self.webViewLoad(data: data, response: response)
                } else {
                    let _ = super.load(request)
                }
            }
        }, failure: {
            // let WKWebView handle the network error
            DispatchQueue.main.async {
                let _ = super.load(request)
            }
        })
        
        return nil
    }
    
    private func requestWithRedirectHandling(_ request: URLRequest, success: @escaping (URLRequest, HTTPURLResponse?, Data?) -> Void, failure: @escaping () -> Void) {
        let sessionConfig = URLSessionConfiguration.default
        let session = URLSession(configuration: sessionConfig, delegate: self, delegateQueue: nil)
        let task = session.dataTask(with: request) { (data, response, error) in
            if let _ = error {
                failure()
            } else {
                if let response = response as? HTTPURLResponse {
                    let code = response.statusCode
                    if code == 200 {
                        // for code 200 return data to load data directly
                        success(request, response, data)
                        
                    } else if code >= 300 && code <  400  {
                        // for redirect get location in header,and make a new URLRequest
                        guard let location = response.allHeaderFields["Location"] as? String, let redirectURL = URL(string: location) else {
                            failure()
                            return
                        }
                        
                        let request = URLRequest(url: redirectURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 5)
                        success(request, nil, nil)
                    } else {
                        success(request, response, data)
                    }
                }
            }
        }
        task.resume()
    }
    
    private func webViewLoad(data: Data, response: URLResponse) -> WKNavigation! {
        guard let url = response.url else {
            return nil
        }
        
        let encode = response.textEncodingName ?? "utf8"
        let mine = response.mimeType ?? "text/html"
        
        return self.load(data, mimeType: mine, characterEncodingName: encode, baseURL: url)
    }
    
    func visitLocation(_ location: URL, withAction action: Action, restorationIdentifier: String?) {
        callJavaScriptFunction("webView.visitLocationWithActionAndRestorationIdentifier", withArguments: [location.absoluteString as Optional<AnyObject>, action.rawValue as Optional<AnyObject>, restorationIdentifier as Optional<AnyObject>])
    }

    func issueRequestForVisitWithIdentifier(_ identifier: String) {
        callJavaScriptFunction("webView.issueRequestForVisitWithIdentifier", withArguments: [identifier as Optional<AnyObject>])
    }

    func changeHistoryForVisitWithIdentifier(_ identifier: String) {
        callJavaScriptFunction("webView.changeHistoryForVisitWithIdentifier", withArguments: [identifier as Optional<AnyObject>])
    }

    func loadCachedSnapshotForVisitWithIdentifier(_ identifier: String) {
        callJavaScriptFunction("webView.loadCachedSnapshotForVisitWithIdentifier", withArguments: [identifier as Optional<AnyObject>])
    }

    func loadResponseForVisitWithIdentifier(_ identifier: String) {
        callJavaScriptFunction("webView.loadResponseForVisitWithIdentifier", withArguments: [identifier as Optional<AnyObject>])
    }

    func cancelVisitWithIdentifier(_ identifier: String) {
        callJavaScriptFunction("webView.cancelVisitWithIdentifier", withArguments: [identifier as Optional<AnyObject>])
    }

    // MARK: JavaScript Evaluation

    private func callJavaScriptFunction(_ functionExpression: String, withArguments arguments: [AnyObject?] = [], completionHandler: ((AnyObject?) -> ())? = nil) {
        guard let script = scriptForCallingJavaScriptFunction(functionExpression, withArguments: arguments) else {
            NSLog("Error encoding arguments for JavaScript function `%@'", functionExpression)
            return
        }
        
        evaluateJavaScript(script) { (result, error) in
            if let result = result as? [String: AnyObject] {
                if let error = result["error"] as? String, let stack = result["stack"] as? String {
                    NSLog("Error evaluating JavaScript function `%@': %@\n%@", functionExpression, error, stack)
                } else {
                    completionHandler?(result["value"])
                }
            } else if let error = error {
                self.delegate?.webView(self, didFailJavaScriptEvaluationWithError: error as NSError)
            }
        }
    }

    private func scriptForCallingJavaScriptFunction(_ functionExpression: String, withArguments arguments: [AnyObject?]) -> String? {
        guard let encodedArguments = encodeJavaScriptArguments(arguments) else { return nil }

        return
            "(function(result) {\n" +
            "  try {\n" +
            "    result.value = " + functionExpression + "(" + encodedArguments + ")\n" +
            "  } catch (error) {\n" +
            "    result.error = error.toString()\n" +
            "    result.stack = error.stack\n" +
            "  }\n" +
            "  return result\n" +
            "})({})"
    }

    private func encodeJavaScriptArguments(_ arguments: [AnyObject?]) -> String? {
        let arguments = arguments.map { $0 == nil ? NSNull() : $0! }

        if let data = try? JSONSerialization.data(withJSONObject: arguments, options: []),
            let string = NSString(data: data, encoding: String.Encoding.utf8.rawValue) as String? {
                let startIndex = string.index(after: string.startIndex)
                let endIndex = string.index(before: string.endIndex)
                return String(string[startIndex..<endIndex])
        }
        
        return nil
    }
}

extension WebView : URLSessionTaskDelegate {
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request)
    }
}

extension WebView: WKScriptMessageHandler {
    open func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let message = ScriptMessage.parse(message) else { return }
        
        switch message.name {
        case .PageLoaded:
            pageLoadDelegate?.webView(self, didLoadPageWithRestorationIdentifier: message.restorationIdentifier!)
        case .PageInvalidated:
            delegate?.webViewDidInvalidatePage(self)
        case .VisitProposed:
            delegate?.webView(self, didProposeVisitToLocation: message.location!, withAction: message.action!)
        case .VisitStarted:
            visitDelegate?.webView(self, didStartVisitWithIdentifier: message.identifier!, hasCachedSnapshot: message.data["hasCachedSnapshot"] as! Bool)
        case .VisitRequestStarted:
            visitDelegate?.webView(self, didStartRequestForVisitWithIdentifier: message.identifier!)
        case .VisitRequestCompleted:
            visitDelegate?.webView(self, didCompleteRequestForVisitWithIdentifier: message.identifier!)
        case .VisitRequestFailed:
            visitDelegate?.webView(self, didFailRequestForVisitWithIdentifier: message.identifier!, statusCode: message.data["statusCode"] as! Int)
        case .VisitRequestFinished:
            visitDelegate?.webView(self, didFinishRequestForVisitWithIdentifier: message.identifier!)
        case .VisitRendered:
            visitDelegate?.webView(self, didRenderForVisitWithIdentifier: message.identifier!)
        case .VisitCompleted:
            visitDelegate?.webView(self, didCompleteVisitWithIdentifier: message.identifier!, restorationIdentifier: message.restorationIdentifier!)
        case .ErrorRaised:
            let error = message.data["error"] as? String
            NSLog("JavaScript error: %@", error ?? "<unknown error>")
        }
    }
}

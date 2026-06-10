import UIKit
import WMFComponents
import WMFData

extension ArticleViewController: ArticleToolbarHandling {
    var navigationToolbar: UIToolbar? {
        return navigationController?.toolbar
    }
    
    func updateToolbarItems() {
        if let items = toolbarController?.currentItems {
            self.toolbarItems = items
        }
    }
    
    func backInTab(article: WMFData.WMFArticleTabsDataController.WMFArticle, controller: ArticleToolbarController) {
        guard let navigationController,
              let siteURL = article.project.siteURL,
              let articleURL = siteURL.wmf_URL(withTitle: article.title),
              let tabIdentifier = coordinator?.tabIdentifier,
              let tabItemIdentifier = article.identifier else {
            return
        }
        
        let identifiers = WMFArticleTabsDataController.Identifiers(tabIdentifier: tabIdentifier, tabItemIdentifier: tabItemIdentifier)
        let articleCoordinator = ArticleCoordinator(navigationController: navigationController, articleURL: articleURL, dataStore: dataStore, theme: theme, needsAnimation: false, source: .undefined, tabConfig: .adjacentArticleInTab(identifiers))
        articleCoordinator.start()
    }
    
    func forwardInTab(article: WMFData.WMFArticleTabsDataController.WMFArticle, controller: ArticleToolbarController) {
        guard let navigationController,
              let siteURL = article.project.siteURL,
              let articleURL = siteURL.wmf_URL(withTitle: article.title),
              let tabIdentifier = coordinator?.tabIdentifier,
              let tabItemIdentifier = article.identifier else {
            return
        }
        
        let identifiers = WMFArticleTabsDataController.Identifiers(tabIdentifier: tabIdentifier, tabItemIdentifier: tabItemIdentifier)
        let articleCoordinator = ArticleCoordinator(navigationController: navigationController, articleURL: articleURL, dataStore: dataStore, theme: theme, needsAnimation: false, source: .undefined, tabConfig: .adjacentArticleInTab(identifiers))
        articleCoordinator.start()
    }
    
    
    func showTableOfContents(from controller: ArticleToolbarController) {
        showTableOfContents()
        NavigationEventsFunnel.shared.logEvent(action: .articleToolbarTOC)
    }
    
    func hideTableOfContents(from controller: ArticleToolbarController) {
        hideTableOfContents()
    }
    
    var isTableOfContentsVisible: Bool {
        return tableOfContentsController.viewController.displayMode == .inline && tableOfContentsController.viewController.isVisible
    }
    
    func toggleSave(from controller: ArticleToolbarController) {
        NavigationEventsFunnel.shared.logEvent(action: .articleToolbarSave)
        let isSaved = dataStore.savedPageList.toggleSavedPage(for: articleURL)
        if isSaved {
            readingListsFunnel.logArticleSaveInCurrentArticle(articleURL)
            NavigationEventsFunnel.shared.logEvent(action: .articleToolbarSaveSuccess)
        } else {
            readingListsFunnel.logArticleUnsaveInCurrentArticle(articleURL)
        }
    }
    
    func showThemePopover(from controller: ArticleToolbarController) {
        themesPresenter?.showReadingThemesControlsPopup(on: self, responder: self, theme: theme)
        NavigationEventsFunnel.shared.logEvent(action: .articleToolbarAppearence)
    }
    
    func saveButtonWasLongPressed(from controller: ArticleToolbarController) {
        let addArticlesToReadingListVC = AddArticlesToReadingListViewController(with: dataStore, articles: [article], theme: theme)
        let navigationController = WMFComponentNavigationController(rootViewController: addArticlesToReadingListVC, modalPresentationStyle: .overFullScreen)
        present(navigationController, animated: true)
        NavigationEventsFunnel.shared.logEvent(action: .articleToolbarSave)
    }
    
    func showLanguagePicker(from controller: ArticleToolbarController) {
        NavigationEventsFunnel.shared.logEvent(action: .articleToolbarLang)
        let alert = UIAlertController(title: "Language and Wiki", message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Article languages", style: .default, handler: { [weak self] _ in
            self?.showLanguages()
        }))
        alert.addAction(UIAlertAction(title: "Choose Wiki source", style: .default, handler: { [weak self] _ in
            self?.presentWikiSourcePicker(from: controller)
        }))
        alert.addAction(UIAlertAction(title: CommonStrings.cancelActionTitle, style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.barButtonItem = controller.languagesButton
            popover.sourceView = view
            popover.sourceRect = view.bounds
        }

        present(alert, animated: true)
    }

    func showWikiSourcePicker(from controller: ArticleToolbarController) {
        presentWikiSourcePicker(from: controller)
    }
    
    func share(from controller: ArticleToolbarController) {
        NavigationEventsFunnel.shared.logEvent(action: .articleToolbarShare)
        shareArticle()
    }
    
    func showFindInPage(from controller: ArticleToolbarController) {
        NavigationEventsFunnel.shared.logEvent(action: .articleToolbarSearch)
        showFindInPage()
    }
    
    func showRevisionHistory(from controller: ArticleToolbarController) {
        showEditHistory()
    }
    
    func watch(from controller: ArticleToolbarController) {
        watch()
    }
    
    func unwatch(from controller: ArticleToolbarController) {
        unwatch()
    }
    
    func showArticleTalkPage(from controller: ArticleToolbarController) {
        showTalkPage()
    }
    
    func editArticle(from controller: ArticleToolbarController) {
        showEditorForFullSource()
    }
    
}

private extension ArticleViewController {
    func presentWikiSourcePicker(from controller: ArticleToolbarController) {
        guard let currentTitle = articleURL.wmf_title, !currentTitle.isEmpty else {
            let alert = UIAlertController(title: "Choose Wiki", message: "This page does not have a title that can be opened on another wiki.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: CommonStrings.okTitle, style: .default))
            present(alert, animated: true)
            return
        }

        let languageCode = articleURL.wmf_languageCode ?? dataStore.languageLinkController.appLanguage?.languageCode ?? "he"
        let sources = WikiReadingSource.defaultSources(languageCode: languageCode)
        let alert = UIAlertController(title: "Choose Wiki", message: "Open this title on another wiki source.", preferredStyle: .actionSheet)

        for source in sources {
            let title = source.matches(articleURL) ? "✓ \(source.displayName)" : source.displayName
            alert.addAction(UIAlertAction(title: title, style: .default, handler: { [weak self] _ in
                self?.open(currentTitle: currentTitle, in: source, languageCode: languageCode)
            }))
        }

        alert.addAction(UIAlertAction(title: CommonStrings.cancelActionTitle, style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.barButtonItem = controller.languagesButton
            popover.sourceView = view
            popover.sourceRect = view.bounds
        }

        present(alert, animated: true)
    }

    func open(currentTitle: String, in source: WikiReadingSource, languageCode: String) {
        guard let navigationController,
              let newURL = source.articleURL(for: currentTitle, languageCode: languageCode) else {
            return
        }

        guard newURL != articleURL else {
            return
        }

        let articleCoordinator = ArticleCoordinator(
            navigationController: navigationController,
            articleURL: newURL,
            dataStore: dataStore,
            theme: theme,
            needsAnimation: true,
            source: .undefined,
            tabConfig: .appendArticleAndAssignCurrentTabAndCleanoutFutureArticles
        )
        articleCoordinator.start()
    }
}

private struct WikiReadingSource {
    enum PathStyle {
        case languageSubdomain(rootDomain: String)
        case fixedHost(host: String, articlePathPrefix: String)
    }

    let displayName: String
    let style: PathStyle

    static func defaultSources(languageCode: String) -> [WikiReadingSource] {
        return [
            WikiReadingSource(displayName: "Wikipedia", style: .languageSubdomain(rootDomain: "wikipedia.org")),
            WikiReadingSource(displayName: "Wiktionary", style: .languageSubdomain(rootDomain: "wiktionary.org")),
            WikiReadingSource(displayName: "Wikisource", style: .languageSubdomain(rootDomain: "wikisource.org")),
            WikiReadingSource(displayName: "Wikiquote", style: .languageSubdomain(rootDomain: "wikiquote.org")),
            WikiReadingSource(displayName: "Wikibooks", style: .languageSubdomain(rootDomain: "wikibooks.org")),
            WikiReadingSource(displayName: "Wikiversity", style: .languageSubdomain(rootDomain: "wikiversity.org")),
            WikiReadingSource(displayName: "Wikinews", style: .languageSubdomain(rootDomain: "wikinews.org")),
            WikiReadingSource(displayName: "Wikivoyage", style: .languageSubdomain(rootDomain: "wikivoyage.org")),
            WikiReadingSource(displayName: "WikiYeshiva", style: .fixedHost(host: "www.yeshiva.org.il", articlePathPrefix: "/wiki/"))
        ]
    }

    func matches(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else {
            return false
        }

        switch style {
        case .languageSubdomain(let rootDomain):
            return host == rootDomain || host.hasSuffix(".\(rootDomain)")
        case .fixedHost(let fixedHost, _):
            return host == fixedHost.lowercased()
        }
    }

    func articleURL(for title: String, languageCode: String) -> URL? {
        let normalizedLanguageCode = languageCode.isEmpty ? "he" : languageCode
        let normalizedTitle = title.replacingOccurrences(of: " ", with: "_")
        var allowedCharacters = CharacterSet.urlPathAllowed
        allowedCharacters.remove(charactersIn: "/")

        guard let encodedTitle = normalizedTitle.addingPercentEncoding(withAllowedCharacters: allowedCharacters) else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "https"

        switch style {
        case .languageSubdomain(let rootDomain):
            components.host = "\(normalizedLanguageCode).\(rootDomain)"
            components.path = "/wiki/\(encodedTitle)"
        case .fixedHost(let host, let articlePathPrefix):
            components.host = host
            components.path = "\(articlePathPrefix)\(encodedTitle)"
        }

        return components.url
    }
}

import UIKit

#if compiler(<6.2)
extension UIBarButtonItem {
    var hidesSharedBackground: Bool {
        get { false }
        set { }
    }

    var sharesBackground: Bool {
        get { false }
        set { }
    }
}
#endif

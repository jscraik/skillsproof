import Foundation

enum AppResources {
    private final class BundleMarker: NSObject {}

    static func url(forResource name: String, withExtension extensionName: String) -> URL? {
        let bundleName = "SkillsBar_SkillsBar.bundle"
        let roots = [
            Bundle.main.resourceURL,
            Bundle.main.bundleURL.deletingLastPathComponent(),
            Bundle(for: BundleMarker.self).bundleURL.deletingLastPathComponent()
        ]
        for root in roots.compactMap({ $0 }) {
            if let bundle = Bundle(url: root.appendingPathComponent(bundleName)),
               let url = bundle.url(forResource: name, withExtension: extensionName) {
                return url
            }
        }
        #if DEBUG
        return Bundle.module.url(forResource: name, withExtension: extensionName)
        #else
        return nil
        #endif
    }
}

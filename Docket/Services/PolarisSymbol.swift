import AppKit

/// The user's original StarDime alpha artwork, with its original aspect ratio.
/// Template rendering lets macOS choose black or white for the current menu bar.
enum PolarisSymbol {
    private static let cachedMenuImage: NSImage = {
        guard let url = Bundle.main.url(forResource: "PolarisLogo", withExtension: "png"),
              let source = NSImage(contentsOf: url) else {
            assertionFailure("Missing original Polaris logo resource")
            return NSImage(size: NSSize(width: 24, height: 18))
        }
        let width: CGFloat = 24
        let height = width * source.size.height / source.size.width
        let image = NSImage(size: NSSize(width: width, height: 18), flipped: false) { _ in
            NSGraphicsContext.current?.imageInterpolation = .high
            source.draw(in: NSRect(x: 0, y: (18 - height) / 2, width: width, height: height),
                        from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Polaris 星辰维度 Logo"
        return image
    }()
    static func menuImage() -> NSImage { cachedMenuImage }
}

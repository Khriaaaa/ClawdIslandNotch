import UIKit

/// 精灵加载器。
///
/// 关键点：**不要用 UIImage(named:)**。
/// Asset Catalog 会把整张图解成全尺寸，一张 900x900 的图解出来就是 3.2MB，
/// 而键盘扩展的内存上限只有 30~50MB（再多就被 jetsam 杀进程），
/// 放几张就爆。这里直接从 bundle 里的裸 PNG 用
/// CGImageSourceCreateThumbnailAtIndex 只解出需要的小尺寸。
final class PetSpriteStore {

    static let shared = PetSpriteStore()

    private var cache: [String: UIImage] = [:]
    private let maxPixelSize: CGFloat = 256

    func image(named name: String) -> UIImage? {
        if let cached = cache[name] { return cached }
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let image = UIImage(cgImage: cg, scale: 3, orientation: .up)
        cache[name] = image
        return image
    }

    /// 内存告急时丢掉缓存 —— 键盘扩展里这很常见，重新加载比被杀掉强
    func purge() { cache.removeAll() }

    var cachedCount: Int { cache.count }
}

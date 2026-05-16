import LyricsService

#if canImport(CoreGraphics)

import CoreGraphics

extension LyricsProviders.ServiceID {
    fileprivate var drawingMethod: ((CGRect) -> Void)? {
        switch self {
        case .netease:
            return LyricsSourceIconDrawing.drawNetEaseMusic
        case .kugou:
            return LyricsSourceIconDrawing.drawKugou
        case .qq:
            return LyricsSourceIconDrawing.drawQQMusic
        default:
            return nil
        }
    }
}

#endif

#if canImport(Cocoa)

import Cocoa

extension LyricsSourceIconDrawing {
    public static let defaultSize = CGSize(width: 48, height: 48)

    public static func icon(of service: LyricsProviders.ServiceID, size: CGSize = defaultSize) -> NSImage {
        return NSImage(size: size, flipped: false) { NSRect -> Bool in
            service.drawingMethod?(CGRect(origin: .zero, size: size))
            return true
        }
    }
}

#elseif canImport(UIKit)

import UIKit

extension LyricsSourceIconDrawing {
    public static let defaultSize = CGSize(width: 48, height: 48)

    public static func icon(of service: LyricsProviders.ServiceID, size: CGSize = defaultSize) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        service.drawingMethod?(CGRect(origin: .zero, size: size))
        let image = UIGraphicsGetImageFromCurrentImageContext()?.withRenderingMode(.alwaysOriginal)
        UIGraphicsEndImageContext()
        return image ?? UIImage()
    }
}

#endif

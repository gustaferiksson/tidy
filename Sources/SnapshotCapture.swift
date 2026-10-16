#if DEBUG
import AppKit

@MainActor
enum SnapshotCapture {
    static func hideOffScreen(_ window: NSWindow) {
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        guard !NSScreen.screens.contains(where: { $0.frame.intersects(window.frame) }) else { exit(1) }
    }

    static func window(where matches: (NSWindow) -> Bool) async -> NSWindow {
        for _ in 0..<250 {
            if let window = NSApp.windows.first(where: matches) { return window }
            try? await Task.sleep(for: .milliseconds(20))
        }
        exit(1)
    }

    @discardableResult
    static func write(_ window: NSWindow, to output: URL) async -> Bool {
        try? await Task.sleep(for: .seconds(1.5))
        guard !NSScreen.screens.contains(where: { $0.frame.intersects(window.frame) }) else { exit(1) }
        guard let image = image(of: window),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { return false }
        return (try? png.write(to: output)) != nil
    }

    // cacheDisplay skips Liquid Glass; CGWindowListCreateImage is SDK-obsoleted but still exported and captures own windows without Screen Recording.
    private static func image(of window: NSWindow) -> CGImage? {
        typealias CreateImage = @convention(c) (CGRect, CGWindowListOption, CGWindowID, CGWindowImageOption) -> Unmanaged<CGImage>?
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return nil }
        let create = unsafeBitCast(symbol, to: CreateImage.self)
        return create(.null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.boundsIgnoreFraming, .bestResolution])?.takeRetainedValue()
    }
}
#endif

import SwiftUI

#if canImport(RoomPlan) && os(iOS)
import RoomPlan
#endif

/// A drawing produced by something other than free-hand sketching — currently a
/// LiDAR room scan. Carries the same payload the sketch editor persists on a
/// `Proposal`: PencilKit ink bytes plus shape/text annotations. Deliberately
/// platform-neutral (no RoomPlan types) so the proposal editor can pass it around
/// on every platform the app builds for.
struct GeneratedSketch {
    var drawingData: Data
    var annotations: [SketchAnnotation]
}

/// Whether the current device can capture a LiDAR room scan. False on any platform
/// without RoomPlan (macOS, visionOS) and on iOS devices that lack a LiDAR Scanner.
enum LidarSupport {
    static var isAvailable: Bool {
        #if canImport(RoomPlan) && os(iOS)
        return RoomCaptureSession.isSupported
        #else
        return false
        #endif
    }
}

extension View {
    /// Presents the LiDAR scanner full-screen on iOS; a no-op on platforms that
    /// don't support RoomPlan so the shared editor code compiles everywhere.
    /// `onDismiss` fires after the cover fully closes — present follow-up UI (like
    /// the sketch editor) from there, not from `onFinish`, or the two presentations
    /// collide and SwiftUI wedges.
    @ViewBuilder
    func lidarScanCover(
        isPresented: Binding<Bool>,
        onFinish: @escaping (GeneratedSketch) -> Void,
        onDismiss: @escaping () -> Void = {}
    ) -> some View {
        #if os(iOS)
        self.fullScreenCover(isPresented: isPresented, onDismiss: onDismiss) {
            LidarScanView(onFinish: onFinish)
        }
        #else
        self
        #endif
    }
}

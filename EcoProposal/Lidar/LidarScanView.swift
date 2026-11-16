#if canImport(RoomPlan) && os(iOS)
import SwiftUI
import AVFoundation
import RoomPlan

/// Full-screen LiDAR room scanner. Wraps RoomPlan's `RoomCaptureView`, lets the rep
/// walk the space with the framework's built-in coaching overlays, and on "Done"
/// converts the captured room into a floor-plan drawing (`GeneratedSketch`) handed
/// back to the caller.
struct LidarScanView: View {
    var onFinish: (GeneratedSketch) -> Void
    @Environment(\.dismiss) private var dismiss

    /// nil while we're asking; the scanner only starts once this is true. ARKit
    /// renders a black view (no error) when camera access is denied, so we gate on
    /// permission explicitly instead of leaving the rep staring at a black screen.
    @State private var cameraAllowed: Bool?
    @State private var isScanning = true
    @State private var isProcessing = false
    @State private var errorMessage: String?
    /// Bumped on "Try Again" — changes the container's identity so SwiftUI tears
    /// down the failed session and builds a fresh one.
    @State private var scanAttempt = 0

    var body: some View {
        ZStack {
            if cameraAllowed == true {
                RoomCaptureContainer(
                    isScanning: $isScanning,
                    onProcessed: handleProcessed,
                    onError: { errorMessage = $0 }
                )
                .id(scanAttempt)
                .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
                if cameraAllowed == false {
                    cameraDeniedNotice
                } else {
                    // Permission check in flight. If this stays on screen, the
                    // camera consent prompt is being suppressed (Screen Time/MDM).
                    ProgressView("Requesting camera access…")
                        .tint(.white)
                        .foregroundStyle(.white)
                }
            }

            VStack {
                HStack {
                    Button("Cancel") { dismiss() }
                        .font(.headline)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                    Spacer()
                }

                Spacer()

                if isProcessing {
                    ProgressView("Building floor plan…")
                        .padding(.horizontal, 22)
                        .padding(.vertical, 16)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                } else if isScanning && cameraAllowed == true {
                    VStack(spacing: 10) {
                        Text("Walk the perimeter of the room, keeping walls in view.")
                            .font(.subheadline.weight(.medium))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())

                        Button {
                            isScanning = false
                            isProcessing = true
                        } label: {
                            Label("Done Scanning", systemImage: "checkmark.circle.fill")
                                .font(.headline)
                                .padding(.horizontal, 26)
                                .padding(.vertical, 14)
                                .background(Color.ecoGreen, in: Capsule())
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
            .padding()
        }
        .task { await checkCameraAccess() }
        .alert("Scan didn't work", isPresented: .constant(errorMessage != nil)) {
            Button("Try Again") {
                errorMessage = nil
                retryScan()
            }
            Button("Cancel", role: .cancel) {
                errorMessage = nil
                dismiss()
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var cameraDeniedNotice: some View {
        VStack(spacing: 14) {
            Image(systemName: "video.slash.fill")
                .font(.largeTitle)
                .foregroundStyle(.white)
            Text("Camera access is off")
                .font(.headline)
                .foregroundStyle(.white)
            Text("The LiDAR scanner needs the camera. Turn it on in Settings to scan.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(32)
    }

    private func checkCameraAccess() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        print("LIDAR: camera auth status = \(status.rawValue) (0=notDetermined 1=restricted 2=denied 3=authorized)")
        switch status {
        case .denied, .restricted:
            // Known-blocked: show the Open Settings notice instead of a black feed.
            cameraAllowed = false
        default:
            // .authorized — good to go. .notDetermined — ALSO proceed: starting the
            // AR session triggers the system consent prompt itself. Calling
            // AVCaptureDevice.requestAccess explicitly hangs without ever prompting
            // on iOS 26 (Apple Developer Forums #812496), so we deliberately don't.
            cameraAllowed = true
        }
        print("LIDAR: cameraAllowed = \(String(describing: cameraAllowed)), RoomPlan supported = \(RoomCaptureSession.isSupported)")
    }

    /// Tears down the failed capture and starts a brand-new scan session.
    private func retryScan() {
        isProcessing = false
        isScanning = true
        scanAttempt += 1
    }

    private func handleProcessed(_ room: CapturedRoom) {
        isProcessing = false
        if let sketch = FloorPlanBuilder.makeSketch(from: room) {
            onFinish(sketch)
            dismiss()
        } else {
            errorMessage = "No walls were detected. Try again, moving slowly so the scanner can see each wall."
        }
    }
}

/// Bridges RoomPlan's UIKit `RoomCaptureView` into SwiftUI. Starts the capture
/// session once the view is attached to a window and stops it when `isScanning`
/// flips to false, then reports the post-processed `CapturedRoom` through
/// `onProcessed`.
private struct RoomCaptureContainer: UIViewRepresentable {
    @Binding var isScanning: Bool
    var onProcessed: (CapturedRoom) -> Void
    var onError: (String) -> Void

    func makeCoordinator() -> RoomCaptureCoordinator {
        RoomCaptureCoordinator(onProcessed: onProcessed, onError: onError)
    }

    func makeUIView(context: Context) -> RoomCaptureView {
        let captureView = RoomCaptureView(frame: .zero)
        captureView.delegate = context.coordinator

        // Start the session only once the view is attached to a window — running
        // it while detached can leave the AR camera feed black. Retries briefly
        // because fullScreenCover attaches the view a beat after makeUIView.
        // Captures the coordinator, not `context` (invalid to use a representable
        // context outside make/update).
        startSessionWhenInWindow(captureView, coordinator: context.coordinator, attempt: 0)
        return captureView
    }

    private func startSessionWhenInWindow(
        _ captureView: RoomCaptureView,
        coordinator: RoomCaptureCoordinator,
        attempt: Int
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + (attempt == 0 ? 0 : 0.1)) {
            guard !coordinator.didStop, !coordinator.didStart else { return }
            guard captureView.window != nil || attempt >= 20 else {
                startSessionWhenInWindow(captureView, coordinator: coordinator, attempt: attempt + 1)
                return
            }
            var configuration = RoomCaptureSession.Configuration()
            configuration.isCoachingEnabled = true
            print("LIDAR: starting capture session (attempt \(attempt), in window: \(captureView.window != nil))")
            captureView.captureSession.run(configuration: configuration)
            coordinator.didStart = true
        }
    }

    func updateUIView(_ captureView: RoomCaptureView, context: Context) {
        // Keep the callbacks fresh, then stop exactly once when the rep taps Done.
        // The delegate delivers the post-processed room afterwards.
        context.coordinator.onProcessed = onProcessed
        context.coordinator.onError = onError
        if !isScanning && !context.coordinator.didStop {
            context.coordinator.didStop = true
            captureView.captureSession.stop()
        }
    }

    static func dismantleUIView(_ captureView: RoomCaptureView, coordinator: RoomCaptureCoordinator) {
        // Rep cancelled — kill the AR session so the camera doesn't keep running
        // (pauseARSession: fully tears down the underlying ARSession).
        if coordinator.didStart && !coordinator.didStop {
            coordinator.didStop = true
            captureView.captureSession.stop(pauseARSession: true)
        }
    }
}

/// Delegate for `RoomCaptureView`. Kept at file scope (not nested) so its
/// Objective-C name is stable — nested `@objc` delegate classes trip the archiving
/// warning that Xcode treats as an error.
@objc(EcoRoomCaptureCoordinator)
private final class RoomCaptureCoordinator: NSObject, RoomCaptureViewDelegate {
    var onProcessed: (CapturedRoom) -> Void
    var onError: (String) -> Void
    var didStart = false
    var didStop = false

    init(onProcessed: @escaping (CapturedRoom) -> Void, onError: @escaping (String) -> Void) {
        self.onProcessed = onProcessed
        self.onError = onError
    }

    // RoomCaptureViewDelegate refines NSCoding. The delegate is never archived, so
    // these are inert stubs to satisfy the protocol.
    init?(coder: NSCoder) { nil }
    func encode(with coder: NSCoder) {}

    // Return true so RoomCaptureView post-processes the raw data into a CapturedRoom.
    // Errors here can be transient (e.g. tracking wobble mid-scan) — log them and let
    // post-processing decide; only `didPresent` reports a final failure.
    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        if let error { print("LIDAR: shouldPresent error (continuing): \(error)") }
        return true
    }

    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        if let error {
            print("LIDAR: didPresent error: \(error)")
            onError(Self.friendlyMessage(for: error))
        } else {
            onProcessed(processedResult)
        }
    }

    /// ARKit's raw errors ("World tracking failure") mean nothing to a sales rep —
    /// translate the common ones into what to actually do differently.
    private static func friendlyMessage(for error: Error) -> String {
        let text = error.localizedDescription
        if text.localizedCaseInsensitiveContains("tracking") {
            return "The scanner lost track of the room. Make sure the space is well lit, hold the phone up facing the walls, and move slowly. Give it a second to find the room before walking."
        }
        return text
    }
}
#endif

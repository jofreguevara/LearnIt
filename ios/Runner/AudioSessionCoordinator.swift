import AVFAudio
import Flutter

/// Configures the iOS audio session for a user-started locked-screen session.
/// The inference worker remains CPU-only while the app is in the background.
final class AudioSessionCoordinator: NSObject {
    private let audioSession = AVAudioSession.sharedInstance()

    func activate() throws {
        try audioSession.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker]
        )
        try audioSession.setActive(true, options: [])
    }

    func deactivate() {
        try? audioSession.setActive(false, options: [.notifyOthersOnDeactivation])
    }

    func installInterruptionHandler(_ handler: @escaping (AVAudioSession.InterruptionType) -> Void) {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: audioSession,
            queue: .main
        ) { notification in
            guard
                let rawValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                let type = AVAudioSession.InterruptionType(rawValue: rawValue)
            else { return }
            handler(type)
        }
    }
}

final class AudioSessionPlugin: NSObject, FlutterPlugin {
    private let coordinator = AudioSessionCoordinator()

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "learnit/audio_session",
            binaryMessenger: registrar.messenger()
        )
        let instance = AudioSessionPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        do {
            switch call.method {
            case "start", "resume":
                try coordinator.activate()
                result(nil)
            case "pause", "finish":
                coordinator.deactivate()
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        } catch {
            result(FlutterError(code: "AUDIO_SESSION", message: error.localizedDescription, details: nil))
        }
    }
}

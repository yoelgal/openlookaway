import AppKit
import CoreAudio
import IOKit.pwr_mgt

enum System {
    /// Seconds since the last keyboard/mouse/trackpad event.
    static func idleSeconds() -> Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    /// True while any app is recording from the default microphone (Zoom, Meet, FaceTime, Slack huddles...).
    // ponytail: default input device only; iterate all input devices if people on external mics report missed calls.
    static func micInUse() -> Bool {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return false }

        var running = UInt32(0)
        size = UInt32(MemoryLayout<UInt32>.size)
        addr.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &running) == noErr else { return false }
        return running != 0
    }

    /// True when the frontmost app has a window covering a whole screen (videos, games, presentations).
    static func frontAppIsFullscreen() -> Bool {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return false }
        let screens = Set(NSScreen.screens.map { "\(Int($0.frame.width))x\(Int($0.frame.height))" })
        return windows.contains { w in
            guard w[kCGWindowOwnerPID as String] as? pid_t == pid,
                  w[kCGWindowLayer as String] as? Int == 0,
                  let dict = w[kCGWindowBounds as String] as! CFDictionary?,
                  let b = CGRect(dictionaryRepresentation: dict) else { return false }
            return screens.contains("\(Int(b.width))x\(Int(b.height))")
        }
    }

    /// True while something keeps the display awake: video players, browsers playing video, presentations.
    // ponytail: any display-sleep assertion counts, so tools like caffeinate also pause breaks; that's why it's opt-in.
    static func videoPlaying() -> Bool {
        var status: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsStatus(&status) == kIOReturnSuccess,
              let dict = status?.takeRetainedValue() as? [String: Int] else { return false }
        return (dict["PreventUserIdleDisplaySleep"] ?? 0) > 0
    }

    /// Locks the screen like the Control Center "Lock Screen" item.
    static func lockScreen() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_NOW),
              let sym = dlsym(handle, "SACLockScreenImmediate") else { return }
        typealias Lock = @convention(c) () -> Int32
        _ = unsafeBitCast(sym, to: Lock.self)()
    }
}

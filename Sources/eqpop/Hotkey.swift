import Cocoa
import Carbon.HIToolbox

/// `--screenshot` runs on a scratch suite, so it neither reads nor changes the user's settings.
let defaults: UserDefaults = CommandLine.arguments.contains("--screenshot") ? UserDefaults(suiteName: "eqpop-screenshot")! : .standard

struct Shortcut {
    var code: UInt32
    var mods: UInt32
    var label: String

    static let standard = Shortcut(code: UInt32(kVK_ANSI_T), mods: UInt32(optionKey | shiftKey), label: "⌥⇧T")

    static func load() -> Shortcut {
        guard defaults.object(forKey: "hotkeyCode") != nil else { return .standard }
        return Shortcut(code: UInt32(defaults.integer(forKey: "hotkeyCode")), mods: UInt32(defaults.integer(forKey: "hotkeyMods")),
                        label: defaults.string(forKey: "hotkeyLabel") ?? "?")
    }

    func save() {
        defaults.set(Int(code), forKey: "hotkeyCode")
        defaults.set(Int(mods), forKey: "hotkeyMods")
        defaults.set(label, forKey: "hotkeyLabel")
    }

    static func from(_ e: NSEvent) -> Shortcut? {
        let f = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var mods: UInt32 = 0
        var label = ""
        if f.contains(.control) { mods |= UInt32(controlKey); label += "⌃" }
        if f.contains(.option) { mods |= UInt32(optionKey); label += "⌥" }
        if f.contains(.shift) { mods |= UInt32(shiftKey); label += "⇧" }
        if f.contains(.command) { mods |= UInt32(cmdKey); label += "⌘" }
        guard f.contains(.control) || f.contains(.option) || f.contains(.command) else { return nil }
        let key = e.keyCode == UInt16(kVK_Space) ? "Space" : (e.charactersIgnoringModifiers ?? "?").uppercased()
        return Shortcut(code: UInt32(e.keyCode), mods: mods, label: label + key)
    }
}

/// A global hotkey through Carbon, which needs no privacy permission.
final class HotKey {
    static var action: (() -> Void)?
    private var ref: EventHotKeyRef?
    private var installed = false

    func register(_ s: Shortcut) -> Bool {
        if let r = ref { UnregisterEventHotKey(r); ref = nil }
        if !installed {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in HotKey.action?(); return noErr }, 1, &spec, nil, nil)
            installed = true
        }
        let id = EventHotKeyID(signature: OSType(0x45515031), id: 1)   // "EQP1"
        let status = RegisterEventHotKey(s.code, s.mods, id, GetApplicationEventTarget(), 0, &ref)
        if status != noErr { FileHandle.standardError.write(Data("eqpop: RegisterEventHotKey \(s.label) failed: OSStatus \(status)\n".utf8)) }
        return status == noErr
    }
}

/// The field of the "change shortcut" dialog: the next key combination pressed becomes the shortcut.
final class ShortcutCatcher: NSView {
    var captured: Shortcut?
    let field = NSTextField(labelWithString: "press the new shortcut…")
    override var acceptsFirstResponder: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        field.frame = bounds
        field.alignment = .center
        field.font = .systemFont(ofSize: 22, weight: .medium)
        addSubview(field)
    }
    required init?(coder: NSCoder) { fatalError() }
    private func take(_ e: NSEvent) -> Bool {
        guard let s = Shortcut.from(e) else { NSSound.beep(); return true }
        captured = s
        field.stringValue = s.label
        return true
    }
    override func keyDown(with event: NSEvent) { _ = take(event) }
    override func performKeyEquivalent(with event: NSEvent) -> Bool { take(event) }
}

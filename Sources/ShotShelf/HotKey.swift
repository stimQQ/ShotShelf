import Carbon.HIToolbox

/// Global hot key via Carbon. Needs no Accessibility permission.
@MainActor
final class HotKey {
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var handlerInstalled = false

    private var ref: EventHotKeyRef?

    /// Returns nil when the combination is already taken by another app.
    init?(keyCode: Int, modifiers: Int, handler: @escaping () -> Void) {
        HotKey.installHandlerIfNeeded()
        let id = HotKey.nextID
        HotKey.nextID += 1
        let hotKeyID = EventHotKeyID(signature: OSType(0x5353_4846), id: id) // 'SSHF'
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr else { return nil }
        HotKey.handlers[id] = handler
    }

    fileprivate static func fire(_ id: UInt32) {
        handlers[id]?()
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let id = hotKeyID.id
            Task { @MainActor in HotKey.fire(id) }
            return noErr
        }, 1, &spec, nil, nil)
    }
}

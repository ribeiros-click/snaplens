import Carbon.HIToolbox

/// Atalhos globais via Carbon (nativo, não exige permissão de acessibilidade).
enum HotKeys {
    nonisolated(unsafe) private static var handlers: [UInt32: () -> Void] = [:]
    nonisolated(unsafe) private static var installed = false
    nonisolated(unsafe) private static var refs: [UInt32: EventHotKeyRef] = [:]

    @discardableResult
    static func register(id: UInt32, keyCode: Int, modifiers: Int, handler: @escaping () -> Void) -> Bool {
        install()
        if let old = refs.removeValue(forKey: id) { UnregisterEventHotKey(old) }
        handlers[id] = handler
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: OSType(0x534E4150), id: id) // 'SNAP'
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hkID, GetApplicationEventTarget(), 0, &ref)
        if let ref { refs[id] = ref }
        return status == noErr
    }

    static func unregister(id: UInt32) {
        if let old = refs.removeValue(forKey: id) { UnregisterEventHotKey(old) }
        handlers[id] = nil
    }

    private static func install() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            if let h = HotKeys.handlers[hkID.id] {
                DispatchQueue.main.async { h() }
            }
            return noErr
        }, 1, &spec, nil, nil)
    }
}

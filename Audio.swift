import AppKit
import CoreAudio

enum AudioFailure: LocalizedError {
    case status(String, OSStatus), message(String)
    var errorDescription: String? {
        switch self { case let .status(action, code): return "\(action) (errore \(code))."; case let .message(text): return text }
    }
}
func check(_ status: OSStatus, _ action: String) throws { if status != noErr { throw AudioFailure.status(action, status) } }
func address(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
}
func scalar<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ initial: T, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> T {
    var value = initial, a = address(selector, scope), size = UInt32(MemoryLayout<T>.size)
    _ = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(object, &a, 0, nil, &size, $0) }
    return value
}
func objectString(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String {
    var value: CFString = "" as CFString, a = address(selector), size = UInt32(MemoryLayout<CFString>.size)
    let status = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(object, &a, 0, nil, &size, $0) }
    return status == noErr ? value as String : ""
}
func objectList(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> [AudioObjectID] {
    var a = address(selector, scope), size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(object, &a, 0, nil, &size) == noErr, size > 0 else { return [] }
    var values = [AudioObjectID](repeating: 0, count: Int(size)/4)
    let status = values.withUnsafeMutableBytes { AudioObjectGetPropertyData(object, &a, 0, nil, &size, $0.baseAddress!) }
    return status == noErr ? values : []
}
struct OutputDevice: Identifiable, Hashable {
    let id: AudioObjectID
    let uid: String
    let name: String
    static func all() -> [OutputDevice] {
        objectList(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices).compactMap { id in
            guard !objectList(id, kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput).isEmpty else { return nil }
            let uid = objectString(id, kAudioDevicePropertyDeviceUID)
            guard !uid.hasPrefix("it.domenicolella.ivolume.engine.") else { return nil }
            return OutputDevice(id: id, uid: uid, name: objectString(id, kAudioObjectPropertyName))
        }
    }
    static var currentID: AudioObjectID { scalar(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, AudioObjectID(0)) }
}
struct AudioApp: Identifiable, Equatable {
    let id: String
    let name: String
    let processes: [AudioObjectID]
    static func all() -> [AudioApp] {
        var groups: [String: (String, [AudioObjectID])] = [:]
        for object in objectList(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList) {
            let pid = scalar(object, kAudioProcessPropertyPID, pid_t(0))
            guard pid != getpid(), pid > 0 else { continue }
            let bundle = objectString(object, kAudioProcessPropertyBundleID)
            guard !bundle.contains("ivolume") else { continue }
            let running = NSRunningApplication(processIdentifier: pid)
            let id = bundle.isEmpty ? "pid.\(pid)" : bundle
            let name = running?.localizedName ?? bundle.split(separator: ".").last.map(String.init) ?? "Processo \(pid)"
            if groups[id] == nil { groups[id] = (name, []) }
            groups[id]!.1.append(object)
        }
        return groups.map { AudioApp(id: $0.key, name: $0.value.0, processes: $0.value.1.sorted()) }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

final class AudioRoute {
    private(set) var tap: AudioObjectID = 0
    private var aggregate: AudioObjectID = 0
    private var callback: AudioDeviceIOProcID?
    private var state: OpaquePointer
    private var description: CATapDescription?
    var callbacks: UInt64 { iv_callbacks(state) }
    var inputPeak: Float { iv_input(state) }
    var outputPeak: Float { iv_output(state) }
    init() { state = iv_create()! }
    deinit { stop(); iv_destroy(state) }
    func setGain(_ value: Float) { iv_gain(state, value) }
    func start(device: OutputDevice, processes: [AudioObjectID], exclusive: Bool, gain: Float) throws {
        stop(); setGain(gain)
        let d = exclusive ? CATapDescription(stereoGlobalTapButExcludeProcesses: processes) : CATapDescription(stereoMixdownOfProcesses: processes)
        d.uuid = UUID()
        d.name = "iVolume · \(device.name)"
        d.isPrivate = true
        // Stereo mixdown taps capture the selected processes across their outputs.
        d.muteBehavior = .unmuted // Switch only after render callbacks have been verified.
        description = d
        do {
            try check(AudioHardwareCreateProcessTap(d, &tap), "Accesso all’audio di sistema non disponibile")
            guard tap != 0 else { throw AudioFailure.message("Il sistema non ha creato il tap audio. Abilita il permesso audio di iVolume e riprova.") }
            let config: [String: Any] = [
                kAudioAggregateDeviceNameKey: "iVolume · \(device.name)",
                kAudioAggregateDeviceUIDKey: "it.domenicolella.ivolume.engine.\(UUID().uuidString)",
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceMainSubDeviceKey: device.uid,
                kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: device.uid]],
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: d.uuid.uuidString, kAudioSubTapDriftCompensationKey: true]],
                kAudioAggregateDeviceTapAutoStartKey: true
            ]
            try check(AudioHardwareCreateAggregateDevice(config as CFDictionary, &aggregate), "Impossibile creare il percorso audio")
            // This engine supports stereo Float32 PCM only. Refuse incompatible layouts.
            for scope in [kAudioDevicePropertyScopeInput, kAudioDevicePropertyScopeOutput] {
                var streams = objectList(aggregate, kAudioDevicePropertyStreams, scope: scope)
                for _ in 0..<10 where streams.isEmpty {
                    Thread.sleep(forTimeInterval: 0.02)
                    streams = objectList(aggregate, kAudioDevicePropertyStreams, scope: scope)
                }
                guard let stream = streams.first, streams.count == 1 else {
                    throw AudioFailure.message("Il percorso audio dell’uscita non è pronto. Ricollega la TV e riprova.")
                }
                let format = scalar(stream, kAudioStreamPropertyVirtualFormat, AudioStreamBasicDescription())
                guard format.mFormatID == kAudioFormatLinearPCM, format.mBitsPerChannel == 32,
                      format.mFormatFlags & kAudioFormatFlagIsFloat != 0, format.mChannelsPerFrame == 2 else {
                    throw AudioFailure.message("L’uscita deve usare audio PCM stereo a 32 bit. Controlla il formato in Configurazione MIDI Audio.")
                }
            }
            try check(AudioDeviceCreateIOProcID(aggregate, iv_render, UnsafeMutableRawPointer(state), &callback), "Impossibile preparare la riproduzione")
            try check(AudioDeviceStart(aggregate, callback), "Impossibile avviare la riproduzione")
        } catch { stop(); throw error }
    }
    func engage() throws {
        guard let d = description, tap != 0 else { return }
        d.muteBehavior = .mutedWhenTapped
        var a = address(kAudioTapPropertyDescription), value: CATapDescription = d
        try check(withUnsafePointer(to: &value) { AudioObjectSetPropertyData(tap, &a, 0, nil, UInt32(MemoryLayout<CATapDescription>.size), $0) }, "Impossibile attivare il volume software")
    }
    func stop() {
        if aggregate != 0 {
            if let callback { AudioDeviceStop(aggregate, callback); AudioDeviceDestroyIOProcID(aggregate, callback) }
            AudioHardwareDestroyAggregateDevice(aggregate)
        }
        if tap != 0 { AudioHardwareDestroyProcessTap(tap) }
        callback = nil; aggregate = 0; tap = 0; description = nil
    }
}

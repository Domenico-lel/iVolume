import AppKit
import ApplicationServices
import CoreAudio
import Combine

final class MediaKeys {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    var onKey: ((Int) -> Void)?
    var enabled = false
    var isInstalled: Bool { tap != nil }
    func install() {
        guard tap == nil, AXIsProcessTrusted() else { return }
        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let owner = Unmanaged<MediaKeys>.fromOpaque(context).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = owner.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            guard owner.enabled, let e = NSEvent(cgEvent: event), e.subtype.rawValue == 8 else { return Unmanaged.passUnretained(event) }
            let code = Int((e.data1 >> 16) & 0xffff), state = (e.data1 >> 8) & 0xff
            guard [0, 1, 7].contains(code) else { return Unmanaged.passUnretained(event) }
            if state == 0xA { DispatchQueue.main.async { owner.onKey?(code) } }
            return nil
        }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                               eventsOfInterest: CGEventMask(1 << 14), callback: callback,
                               userInfo: Unmanaged.passUnretained(self).toOpaque())
        if let tap { source = CFMachPortCreateRunLoopSource(nil, tap, 0); CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes); CGEvent.tapEnable(tap: tap, enable: true) }
    }
    func stop() {
        enabled = false
        if let tap { CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil
    }
    deinit { stop() }
}

final class VolumeModel: ObservableObject {
    @Published var outputs: [OutputDevice] = []
    @Published var selectedUID = ""
    @Published var volume: Double = 0.35 { didSet { defaults.set(volume, forKey: "masterVolume"); updateGains() } }
    @Published var muted = false { didSet { updateGains() } }
    @Published var active = false
    @Published var preparing = false
    @Published var message = "Attiva il controllo per regolare anche l’uscita HDMI."
    @Published var error: String?
    @Published var keyboardReady = false
    @Published var keyboardWanted = true
    @Published var apps: [AudioApp] = []
    @Published var levels: [String: Double] = [:]
    @Published var inputPeak: Float = 0
    @Published var outputPeak: Float = 0
    @Published var audioSeen = false
    @Published var testing = false
    private var routes: [(String?, AudioRoute)] = []
    private var timer: Timer?
    private var ticks = 0
    private var appSignature = ""
    private var desiredActive = false
    private var preparationDate = Date()
    private let defaults: UserDefaults
    let keys = MediaKeys()
    var onVolumeKey: (() -> Void)?
    var device: OutputDevice? { outputs.first { $0.uid == selectedUID } }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let prefs = defaults
        if prefs.object(forKey: "masterVolume") != nil { volume = min(1, max(0, prefs.double(forKey: "masterVolume"))) }
        levels = prefs.dictionary(forKey: "appVolumes") as? [String: Double] ?? [:]
        keyboardWanted = prefs.object(forKey: "keyboardWanted") == nil || prefs.bool(forKey: "keyboardWanted")
        refreshDevices(); apps = AudioApp.all()
        keys.onKey = { [weak self] code in self?.handleMediaKey(code) }
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in self?.poll() }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.suspend() }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now()+2) { guard let self else { return }; self.refreshDevices(); if self.desiredActive { self.activate() } }
        }
    }
    func handleMediaKey(_ code: Int) {
        guard [0, 1, 7].contains(code) else { return }
        if code == 7 { muted.toggle() }
        else { muted = false; volume = min(1, max(0, volume + (code == 0 ? 0.0625 : -0.0625))) }
        onVolumeKey?()
        writeDiagnostics()
    }
    func resumeIfWanted() { if defaults.bool(forKey: "controlEnabled") { activate() } }
    func refreshDevices() {
        outputs = OutputDevice.all()
        if let current = outputs.first(where: { $0.id == OutputDevice.currentID }) { selectedUID = current.uid }
    }
    func select(_ uid: String) {
        guard let target = outputs.first(where: { $0.uid == uid }) else { return }
        var id = target.id, a = address(kAudioHardwarePropertyDefaultOutputDevice)
        do { try check(AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, 4, &id), "Impossibile cambiare uscita"); selectedUID = uid; if desiredActive { activate() } }
        catch { self.error = error.localizedDescription }
    }
    func level(for app: AudioApp) -> Double { levels[app.id] ?? 1 }
    func setLevel(_ app: AudioApp, _ value: Double) {
        let wasModified = level(for: app) < 0.999
        levels[app.id] = min(1, max(0, value)); defaults.set(levels, forKey: "appVolumes")
        if active && wasModified == (value < 0.999) { updateGains() }
        else if desiredActive { activate() }
    }
    private func gain(_ app: String?) -> Float {
        muted ? 0 : Float(pow(volume, 2) * pow(app.flatMap { levels[$0] } ?? 1, 2))
    }
    private func updateGains() {
        guard active else { return }
        for (app, route) in routes { route.setGain(gain(app)) }
    }
    private func signature(_ apps: [AudioApp]) -> String {
        apps.filter { level(for: $0) < 0.999 }.map { "\($0.id):\($0.processes)" }.joined(separator: "|")
    }
    func activate() {
        desiredActive = true; defaults.set(true, forKey: "controlEnabled")
        stopRoutes(); refreshDevices(); error = nil; audioSeen = false
        guard let device else { message = "Collega un’uscita audio e riprova."; desiredActive = false; return }
        preparing = true; preparationDate = Date(); message = "Autorizza l’audio, poi avvia una riproduzione per completare l’attivazione."
        apps = AudioApp.all()
        let modified = apps.filter { level(for: $0) < 0.999 }
        let excluded = modified.flatMap(\.processes)
        // Exclude our own renderer to prevent feedback loops.
        var selfPID = getpid(), selfObject: AudioObjectID = 0, size: UInt32 = 4
        var a = address(kAudioHardwarePropertyTranslatePIDToProcessObject)
        let translation = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 4, &selfPID, &size, &selfObject)
        guard translation == noErr, selfObject != 0 else { fail("Impossibile isolare il motore audio. Riprova dopo aver riaperto iVolume."); return }
        do {
            let master = AudioRoute()
            try master.start(device: device, processes: excluded + [selfObject], exclusive: true, gain: 0)
            routes.append((nil, master))
            for app in modified {
                let route = AudioRoute()
                try route.start(device: device, processes: app.processes, exclusive: false, gain: 0)
                routes.append((app.id, route))
            }
            appSignature = signature(apps)
        } catch { fail(error.localizedDescription) }
        writeDiagnostics()
    }
    private func finishActivation() {
        do {
            for (_, route) in routes { try route.engage() }
            active = true; preparing = false; audioSeen = true
            updateGains(); message = "Controllo audio attivo su \(device?.name ?? "questa uscita")."
            updateKeyboard()
        } catch { fail(error.localizedDescription) }
    }
    private func poll() {
        ticks += 1; updateKeyboard()
        let inPeak = routes.map { $0.1.inputPeak }.max() ?? 0
        inputPeak = inPeak; outputPeak = routes.map { $0.1.outputPeak }.max() ?? 0
        if inPeak > 0.00001 { audioSeen = true }
        if preparing {
            // Never mute the original path until permission and incoming PCM are proven.
            if inPeak > 0.00001 && routes.contains(where: { $0.1.callbacks > 0 }) { finishActivation() }
            else if Date().timeIntervalSince(preparationDate) > 90 { fail("Non arriva audio. Consenti iVolume in Privacy e sicurezza → Registrazione schermo e audio di sistema, avvia un brano e premi Attiva controllo audio.") }
        }
        if ticks % 10 == 0 {
            let previous = selectedUID
            refreshDevices()
            if desiredActive && (device == nil || previous != selectedUID) {
                if device == nil { fail("L’uscita è stata scollegata. Ricollegala e riattiva il controllo.") }
                else { activate() }
            }
            let newApps = AudioApp.all()
            if newApps != apps { apps = newApps; if active && signature(newApps) != appSignature { activate() } }
            writeDiagnostics()
        }
    }
    func updateKeyboard() {
        if keyboardWanted { keys.install() } else { keys.stop() }
        keyboardReady = AXIsProcessTrusted() && keys.isInstalled
        keys.enabled = active && keyboardReady && keyboardWanted
    }
    func setKeyboard(_ wanted: Bool) { keyboardWanted = wanted; defaults.set(wanted, forKey: "keyboardWanted"); updateKeyboard() }
    func openAccessibility() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    func openAudioPrivacy() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }
    private func stopRoutes() { keys.enabled = false; for (_, route) in routes.reversed() { route.stop() }; routes.removeAll(); active = false; preparing = false; inputPeak = 0; outputPeak = 0 }
    private func suspend() { stopRoutes(); message = "Controllo sospeso durante lo stop del Mac." }
    func stop() { desiredActive = false; defaults.set(false, forKey: "controlEnabled"); stopRoutes(); message = "Controllo disattivato. Il volume torna a essere gestito dalla TV."; writeDiagnostics() }
    private func fail(_ text: String) { desiredActive = false; stopRoutes(); error = text; message = "Controllo audio non attivo."; writeDiagnostics() }
    func shutdown() { timer?.invalidate(); stopRoutes(); keys.stop(); writeDiagnostics() }
    func writeDiagnostics() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("iVolume")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data: [String: Any] = ["version": "0.10.0", "active": active, "preparing": preparing, "output": device?.name ?? "", "volume": volume, "muted": muted, "keyboardReady": keyboardReady, "inputPeak": inputPeak, "outputPeak": outputPeak, "callbacks": routes.reduce(UInt64(0)) { $0 + $1.1.callbacks }, "error": error ?? "", "date": ISO8601DateFormatter().string(from: Date())]
        if let json = try? JSONSerialization.data(withJSONObject: data, options: .prettyPrinted) { try? json.write(to: directory.appendingPathComponent("status.json"), options: .atomic) }
    }
}

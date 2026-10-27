import SwiftUI
import AppKit

struct VolumeView: View {
    @ObservedObject var model: VolumeModel
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                Image(systemName: "headphones").font(.system(size: 30, weight: .medium)).foregroundStyle(.tint).frame(width: 44)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Il volume, dalla tastiera.").font(.title2.weight(.semibold))
                    Text("Le cuffie restano collegate alla TV.").foregroundStyle(.secondary)
                }
                Spacer()
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Uscita audio").font(.headline)
                Picker("Uscita audio", selection: Binding(get: { model.selectedUID }, set: { model.select($0) })) {
                    ForEach(model.outputs) { output in Text(output.name).tag(output.uid) }
                }.labelsHidden().accessibilityLabel("Uscita audio").frame(maxWidth: .infinity)
                Label(model.active ? "Controllo attivo" : model.preparing ? "In attesa dell’audio" : "Controllo disattivato", systemImage: model.active ? "checkmark.circle.fill" : "circle")
                    .font(.callout).foregroundStyle(model.active ? Color.green : Color.secondary)
            }
            VStack(spacing: 14) {
                HStack {
                    Text("Volume generale").font(.headline)
                    Spacer()
                    Text(model.muted ? "Muto" : "\(Int((model.volume*100).rounded()))%")
                        .font(.title2.monospacedDigit().weight(.medium)).accessibilityIdentifier("masterPercent")
                }
                HStack(spacing: 14) {
                    Button { model.muted.toggle() } label: { Image(systemName: model.muted ? "speaker.slash.fill" : "speaker.wave.2.fill").frame(width: 22) }
                        .help("Attiva o disattiva l’audio").accessibilityLabel(model.muted ? "Riattiva audio" : "Disattiva audio")
                    Slider(value: $model.volume, in: 0...1).accessibilityLabel("Volume generale").accessibilityValue("\(Int(model.volume*100)) per cento")
                    Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                }.disabled(!model.active)
                Text(model.message).font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Usa i tasti volume del Mac", isOn: Binding(get: { model.keyboardWanted }, set: { model.setKeyboard($0) }))
                if model.keyboardWanted && !model.keyboardReady {
                    HStack(alignment: .top) {
                        Text("Per leggere i tasti volume, abilita iVolume in Accessibilità.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button("Apri Accessibilità…") { model.openAccessibility() }
                    }
                } else if model.keyboardWanted {
                    Label("Tasti volume e muto pronti", systemImage: "keyboard").font(.callout).foregroundStyle(.secondary)
                }
            }
            if let error = model.error {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Serve un controllo", systemImage: "exclamationmark.triangle").font(.headline)
                    Text(error).font(.callout).fixedSize(horizontal: false, vertical: true)
                    Button("Apri permessi audio…") { model.openAudioPrivacy() }
                }.padding(14).background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            }
            HStack {
                Text("iVolume 0.10 · Domenico Lella").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if model.active || model.preparing {
                    Button("Disattiva") { model.stop() }
                } else {
                    Button("Attiva controllo audio") { model.activate() }.buttonStyle(.borderedProminent).disabled(model.outputs.isEmpty)
                }
            }
            DisclosureGroup("Volume delle applicazioni") {
                if model.apps.isEmpty {
                    Text("Apri un’app che riproduce audio: comparirà qui.").foregroundStyle(.secondary).padding(.top, 10)
                } else {
                    ScrollView {
                        VStack(spacing: 14) {
                            ForEach(model.apps) { app in
                                HStack {
                                    Text(app.name).lineLimit(1).frame(width: 135, alignment: .leading).help(app.id)
                                    Slider(value: Binding(get: { model.level(for: app) }, set: { model.setLevel(app, $0) }), in: 0...1).accessibilityLabel("Volume \(app.name)")
                                    Text("\(Int(model.level(for: app)*100))%").monospacedDigit().frame(width: 42, alignment: .trailing)
                                }
                            }
                        }.padding(.top, 12)
                    }.frame(height: 125).disabled(!model.active)
                }
            }.font(.callout)
        }
        .padding(28).frame(width: 570)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = VolumeModel()
    var window: NSWindow!
    var statusItem: NSStatusItem!
    var hud: NSPanel?
    var hudGeneration = 0
    func applicationDidFinishLaunching(_ notification: Notification) {
        // A second launch always opens the existing app's window.
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "").filter { $0.processIdentifier != getpid() }
        if let existing = others.first { existing.activate(options: [.activateAllWindows]); NSApp.terminate(nil); return }
        NSApp.setActivationPolicy(.regular)
        let content = VolumeView(model: model)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 570, height: 560), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "iVolume"; window.identifier = NSUserInterfaceItemIdentifier("iVolumeMainWindow")
        window.contentView = NSHostingView(rootView: content); window.isReleasedWhenClosed = false; window.delegate = self
        window.center()
        let menu = NSMenu()
        menu.addItem(withTitle: "Apri iVolume", action: #selector(showWindow), keyEquivalent: "o").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Disattiva controllo audio", action: #selector(stopAudio), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Esci da iVolume", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "speaker.wave.2", accessibilityDescription: "iVolume")
        statusItem.menu = menu
        let appMenu = NSMenu(); let root = NSMenuItem(); appMenu.addItem(root)
        let submenu = NSMenu(); submenu.addItem(withTitle: "Informazioni su iVolume", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        submenu.addItem(.separator()); submenu.addItem(withTitle: "Apri iVolume", action: #selector(showWindow), keyEquivalent: "0").target = self
        submenu.addItem(withTitle: "Esci da iVolume", action: #selector(quit), keyEquivalent: "q").target = self
        root.submenu = submenu; NSApp.mainMenu = appMenu
        model.onVolumeKey = { [weak self] in self?.showHUD() }
        showWindow()
        DispatchQueue.main.async { self.model.resumeIfWanted() }
    }
    @objc func showWindow() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc func stopAudio() { model.stop() }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { model.shutdown() }
    func showHUD() {
        if hud == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 260, height: 96), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .floating; panel.isOpaque = false; panel.backgroundColor = .clear; panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; hud = panel
        }
        hud?.contentView = NSHostingView(rootView: HStack(spacing: 18) {
            Image(systemName: model.muted ? "speaker.slash.fill" : "speaker.wave.2.fill").font(.title)
            VStack(alignment: .leading, spacing: 6) {
                Text(model.device?.name ?? "iVolume").font(.caption).lineLimit(1)
                Text(model.muted ? "Muto" : "Volume \(Int((model.volume*100).rounded()))% ").font(.headline.monospacedDigit())
                ProgressView(value: model.muted ? 0 : model.volume).frame(width: 150)
            }
        }.padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)))
        if let screen = NSScreen.main { hud?.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX-130, y: screen.visibleFrame.minY+90)) }
        hud?.orderFrontRegardless(); hudGeneration += 1; let generation = hudGeneration
        DispatchQueue.main.asyncAfter(deadline: .now()+1.3) { [weak self] in if self?.hudGeneration == generation { self?.hud?.orderOut(nil) } }
    }
}

@main
struct IVolumeMain {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}

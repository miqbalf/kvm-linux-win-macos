import AppKit
import Foundation
import Metal

enum GPUMode: String, CaseIterable {
    case apple = "apple"
    case nvidia = "nvidia"
    case igpu = "igpu"

    var title: String {
        switch self {
        case .apple:  return "Auto (Optimus)"
        case .nvidia: return "NVIDIA Mode"
        case .igpu:   return "iGPU Mode"
        }
    }

    var shortBadge: String {
        switch self {
        case .apple:  return "N5 · Auto"
        case .nvidia: return "N5 · GTX"
        case .igpu:   return "N5 · iGPU"
        }
    }

    var subtitle: String {
        switch self {
        case .apple:  return "Balanced: Intel UHD 630 for desktop/light apps, GTX 1650 for GPU workloads."
        case .nvidia: return "Performance: GTX 1650 exposed to all non-UI apps (HDMI/compute/games)."
        case .igpu:   return "Eco: All apps stay on Intel UHD 630 unless pinned with 'nvidia <App>'."
        }
    }
}

struct LiveStatus {
    var mode: GPUMode = .apple
    var headless: String = "0"
    var nvaccelfb: String = "0"
    var heads: String = "0"
    var hotplugPoll: String = "0"
    var metalDevices: [String] = []
}

final class NitroGPUController: NSObject, NSApplicationDelegate {
    private let policyPath = "/Library/GPUBundles/nvmtl-gpu-policy.txt"
    private let helperPath = "/Library/NullMoth/nitro-gpu-ctl"

    private var statusItem: NSStatusItem!
    private var window: NSWindow!

    private var modeButtons: [GPUMode: NSButton] = [:]
    private var statusLabel: NSTextField!
    private var detailTextView: NSTextView!
    private var lastMetalDevices: [String] = []
    private var refreshTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        setupMenuBar()
        setupWindow()
        refreshAll(runProbe: true)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.refreshAll(runProbe: false)
        }
        showMainWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "N5 · GPU"

        let menu = NSMenu()
        let openItem = NSMenuItem(title: "Open NitroGPU Switcher", action: #selector(showMainWindow), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)
        menu.addItem(.separator())

        let autoItem = NSMenuItem(title: "Auto (Optimus)", action: #selector(menuSelectAuto), keyEquivalent: "1")
        let nvItem = NSMenuItem(title: "NVIDIA Mode (GTX 1650)", action: #selector(menuSelectNvidia), keyEquivalent: "2")
        let igpuItem = NSMenuItem(title: "iGPU Mode (UHD 630)", action: #selector(menuSelectIGPU), keyEquivalent: "3")
        for item in [autoItem, nvItem, igpuItem] {
            item.target = self
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let hdmiItem = NSMenuItem(title: "Arm Hot-Plugged HDMI", action: #selector(armHDMIAction), keyEquivalent: "h")
        hdmiItem.target = self
        menu.addItem(hdmiItem)

        let quitItem = NSMenuItem(title: "Quit NitroGPU", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(.separator())
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func setupWindow() {
        let frame = NSRect(x: 0, y: 0, width: 520, height: 430)
        window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Nitro 5 GPU Switcher — Acer AN515-55"
        window.center()
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(calibratedRed: 0.10, green: 0.10, blue: 0.12, alpha: 1.0)

        let root = NSView(frame: frame)
        root.wantsLayer = true
        window.contentView = root

        let header = makeLabel("NITRO 5 GPU CONTROL", size: 18, weight: .bold,
                               color: NSColor(calibratedRed: 0.95, green: 0.22, blue: 0.24, alpha: 1.0))
        header.frame = NSRect(x: 24, y: 382, width: 472, height: 28)
        root.addSubview(header)

        let sub = makeLabel("Intel UHD 630 (144 Hz Panel) + NVIDIA GTX 1650 (Offload & HDMI)", size: 12, weight: .regular, color: .secondaryLabelColor)
        sub.frame = NSRect(x: 24, y: 360, width: 472, height: 18)
        root.addSubview(sub)

        var y: CGFloat = 296
        for mode in [GPUMode.apple, GPUMode.nvidia, GPUMode.igpu] {
            let btn = NSButton(frame: NSRect(x: 24, y: y, width: 472, height: 48))
            btn.bezelStyle = .rounded
            btn.wantsLayer = true
            btn.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
            btn.title = "\(mode.title)   —   \(mode.subtitle)"
            btn.alignment = .left
            btn.target = self
            btn.action = #selector(modeButtonClicked(_:))
            btn.tag = GPUMode.allCases.firstIndex(of: mode) ?? 0
            root.addSubview(btn)
            modeButtons[mode] = btn
            y -= 56
        }

        statusLabel = makeLabel("Status: checking...", size: 12, weight: .medium, color: .labelColor)
        statusLabel.frame = NSRect(x: 24, y: 158, width: 472, height: 20)
        root.addSubview(statusLabel)

        let scroll = NSScrollView(frame: NSRect(x: 24, y: 58, width: 472, height: 94))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        detailTextView = NSTextView(frame: scroll.bounds)
        detailTextView.isEditable = false
        detailTextView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        detailTextView.backgroundColor = NSColor(calibratedRed: 0.06, green: 0.06, blue: 0.08, alpha: 1.0)
        detailTextView.textColor = .white
        scroll.documentView = detailTextView
        root.addSubview(scroll)

        let hdmiBtn = NSButton(title: "Activate HDMI Display", target: self, action: #selector(armHDMIAction))
        hdmiBtn.bezelStyle = .rounded
        hdmiBtn.frame = NSRect(x: 24, y: 18, width: 162, height: 28)
        root.addSubview(hdmiBtn)

        let probeBtn = NSButton(title: "Test Metal GPUs", target: self, action: #selector(probeAction))
        probeBtn.bezelStyle = .rounded
        probeBtn.frame = NSRect(x: 194, y: 18, width: 132, height: 28)
        root.addSubview(probeBtn)

        let openBtn = NSButton(title: "Show Policy File", target: self, action: #selector(openPolicyAction))
        openBtn.bezelStyle = .rounded
        openBtn.frame = NSRect(x: 334, y: 18, width: 162, height: 28)
        root.addSubview(openBtn)
    }

    private func makeLabel(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
        let lbl = NSTextField(labelWithString: text)
        lbl.font = NSFont.systemFont(ofSize: size, weight: weight)
        lbl.textColor = color
        return lbl
    }

    @objc private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func menuSelectAuto()   { switchMode(.apple) }
    @objc private func menuSelectNvidia() { switchMode(.nvidia) }
    @objc private func menuSelectIGPU()   { switchMode(.igpu) }

    @objc private func modeButtonClicked(_ sender: NSButton) {
        let modes = GPUMode.allCases
        guard sender.tag >= 0 && sender.tag < modes.count else { return }
        switchMode(modes[sender.tag])
    }

    @objc private func armHDMIAction() {
        let st = readStatus(runProbe: false)
        if st.heads == "0" {
            let res = runPrivilegedHelper(["arm-hdmi"])
            refreshAll(runProbe: false, extraMessage: res)
            return
        }
        var displayCount: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &displayCount)
        if displayCount <= 1 {
            let alert = NSAlert()
            alert.messageText = "Restart WindowServer to light up HDMI?"
            alert.informativeText = "macOS detected an external HDMI monitor (heads=\(st.heads)), but WindowServer started before it was connected. Activating HDMI resets the GUI login session for ~3 seconds — save open work first."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Activate HDMI (Re-login)")
            alert.addButton(withTitle: "Arm Kernel Only")
            alert.addButton(withTitle: "Cancel")
            let resp = alert.runModal()
            if resp == .alertFirstButtonReturn {
                let res = runPrivilegedHelper(["activate-hdmi"])
                refreshAll(runProbe: false, extraMessage: res)
            } else if resp == .alertSecondButtonReturn {
                let res = runPrivilegedHelper(["arm-hdmi"])
                refreshAll(runProbe: false, extraMessage: res)
            }
        } else {
            let res = runPrivilegedHelper(["arm-hdmi"])
            refreshAll(runProbe: true, extraMessage: res)
        }
    }

    @objc private func probeAction() {
        refreshAll(runProbe: true)
    }

    @objc private func openPolicyAction() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: policyPath)])
    }

    private func switchMode(_ mode: GPUMode) {
        let out = runPrivilegedHelper(["set", mode.rawValue])
        refreshAll(runProbe: true, extraMessage: out + "\n(Restart target apps to apply the updated GPU policy.)")
    }

    private func readStatus(runProbe: Bool) -> LiveStatus {
        var st = LiveStatus()
        if FileManager.default.isExecutableFile(atPath: helperPath) {
            let txt = runCommand(helperPath, args: ["status"])
            for line in txt.split(separator: "\n") {
                let parts = line.split(separator: "=", maxSplits: 1)
                guard parts.count == 2 else { continue }
                let k = String(parts[0]), v = String(parts[1])
                switch k {
                case "mode": st.mode = GPUMode(rawValue: v) ?? .apple
                case "headless": st.headless = v
                case "nvaccelfb": st.nvaccelfb = v
                case "heads": st.heads = v
                case "hotplug_poll": st.hotplugPoll = v
                default: break
                }
            }
        } else if let raw = try? String(contentsOfFile: policyPath, encoding: .utf8) {
            for line in raw.split(separator: "\n") {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("mode ") {
                    let arg = t.dropFirst(5).trimmingCharacters(in: .whitespaces)
                    st.mode = GPUMode(rawValue: arg) ?? .apple
                }
            }
        }
        if runProbe {
            lastMetalDevices = probeMetalInFreshSubprocess()
        }
        st.metalDevices = lastMetalDevices
        return st
    }

    private func probeMetalInFreshSubprocess() -> [String] {
        guard let exe = Bundle.main.executablePath else { return [] }
        let out = runCommand(exe, args: ["--probe"])
        return out.split(separator: "\n").map(String.init)
    }

    private func refreshAll(runProbe: Bool = false, extraMessage: String? = nil) {
        let st = readStatus(runProbe: runProbe)
        statusItem.button?.title = st.mode.shortBadge
        statusLabel.stringValue = "Active Policy: \(st.mode.title)  |  Headless: \(st.headless)  |  HDMI Heads: \(st.heads) (nvaccelfb=\(st.nvaccelfb), poll=\(st.hotplugPoll)s)"

        for (m, btn) in modeButtons {
            let active = (m == st.mode)
            btn.contentTintColor = active ? NSColor(calibratedRed: 0.95, green: 0.22, blue: 0.24, alpha: 1.0) : nil
            btn.title = "\(active ? "[ACTIVE] " : "         ")\(m.title) — \(m.subtitle)"
        }

        if let menu = statusItem.menu {
            for item in menu.items {
                switch item.action {
                case #selector(menuSelectAuto):   item.state = (st.mode == .apple) ? .on : .off
                case #selector(menuSelectNvidia): item.state = (st.mode == .nvidia) ? .on : .off
                case #selector(menuSelectIGPU):   item.state = (st.mode == .igpu) ? .on : .off
                default: break
                }
            }
        }

        var lines: [String] = []
        if let msg = extraMessage, !msg.isEmpty {
            lines.append(msg)
            lines.append("---")
        }
        lines.append("Policy file: \(policyPath)")
        lines.append("Metal probe (NSSupportsAutomaticGraphicsSwitching=YES):")
        if st.metalDevices.isEmpty {
            lines.append("  (none reported)")
        } else {
            for d in st.metalDevices { lines.append("  • \(d)") }
        }
        detailTextView.string = lines.joined(separator: "\n")
    }

    private func runCommand(_ launchPath: String, args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do {
            try p.run()
            p.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } catch {
            return "error: \(error.localizedDescription)"
        }
    }

    private func runPrivilegedHelper(_ args: [String]) -> String {
        guard FileManager.default.isExecutableFile(atPath: helperPath) else {
            return "Missing \(helperPath). Run scripts/05-install-nullmoth-optimus.sh first."
        }
        // Try non-interactive sudo first (works instantly if scoped sudoers.d is enabled)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        p.arguments = ["-n", helperPath] + args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        if (try? p.run()) != nil {
            p.waitUntilExit()
            if p.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "OK"
            }
        }

        // Fall back to standard macOS admin authorization dialog
        let quotedCmd = ([helperPath] + args).map { "'\($0)'" }.joined(separator: " ")
        let scriptSrc = "do shell script \"\(quotedCmd)\" with administrator privileges"
        var errDict: NSDictionary?
        if let script = NSAppleScript(source: scriptSrc) {
            let res = script.executeAndReturnError(&errDict)
            if let err = errDict {
                return "Cancelled or error: \(err[NSAppleScript.errorMessage] ?? "unknown")"
            }
            return res.stringValue ?? "OK"
        }
        return "Unable to run AppleScript authorization."
    }
}

if CommandLine.arguments.contains("--probe") {
    for dev in MTLCopyAllDevices() {
        print("\(dev.name) (lowPower=\(dev.isLowPower), headless=\(dev.isHeadless))")
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = NitroGPUController()
app.delegate = delegate
app.run()

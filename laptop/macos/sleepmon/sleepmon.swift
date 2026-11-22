// sleepmon: log every sleep/wake cycle on the Hackintosh, and detect failed wakes at the next boot.
// Runs as a LaunchDaemon (root). Log: /Library/Logs/SleepMon/sleepmon.log, CSV: events.csv
import Foundation
import IOKit
import IOKit.pwr_mgt

let dir = ProcessInfo.processInfo.environment["SLEEPMON_DIR"] ?? "/Library/Logs/SleepMon"
let logURL = URL(fileURLWithPath: dir + "/sleepmon.log")
let csvURL = URL(fileURLWithPath: dir + "/events.csv")
let stateURL = URL(fileURLWithPath: dir + "/state")
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

func now() -> String { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"; return f.string(from: Date()) }
func sh(_ cmd: String, timeout: Double = 8) -> String {
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/bash"); p.arguments = ["-c", cmd]
    let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
    do { try p.run() } catch { return "" }
    let deadline = Date().addingTimeInterval(timeout)
    while p.isRunning && Date() < deadline { usleep(50_000) }
    if p.isRunning { p.terminate(); return "(timeout)" }
    return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}
func append(_ url: URL, _ s: String) {
    if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(s.data(using: .utf8)!); try? h.close() }
    else { try? s.write(to: url, atomically: true, encoding: .utf8) }
}
func log(_ s: String) { append(logURL, "\(now())  \(s)\n") }
func csv(_ event: String, _ fields: [String]) {
    if !FileManager.default.fileExists(atPath: csvURL.path) {
        append(csvURL, "time,event,cycle,hibernatemode,battery,lid,cpu_temp,detail\n")
    }
    let clean = fields.map { $0.replacingOccurrences(of: ",", with: ";").replacingOccurrences(of: "\n", with: " | ") }
    append(csvURL, ([now(), event] + clean).joined(separator: ",") + "\n")
}
func setState(_ s: String) { try? s.write(to: stateURL, atomically: true, encoding: .utf8) }
func getState() -> String { (try? String(contentsOf: stateURL, encoding: .utf8)) ?? "" }

var cycle = 0
func quickInfo() -> (hib: String, batt: String, lid: String, temp: String) {
    let hib = sh("pmset -g | awk '/hibernatemode/ {print $2}'", timeout: 3)
    let batt = sh("pmset -g batt | grep -oE '[0-9]+%;[^;]*' | head -1", timeout: 3)
    let lid = sh("ioreg -r -k AppleClamshellState -d 1 | grep -m1 AppleClamshellState | grep -q Yes && echo closed || echo open", timeout: 3)
    let temp = sh("'/Library/Application Support/NitroSense/nitroctl' status 2>/dev/null | grep -oE 'CPU [0-9]+' | head -1", timeout: 3)
    return (hib, batt, lid, temp)
}

// ---- at start (boot or daemon restart): was the previous sleep followed by a wake?
let bootTime = sh("sysctl -n kern.boottime | sed -E 's/^\\{ sec = ([0-9]+),.*/\\1/'")
let prev = getState()   // "boot=<epoch> last=<sleep|wake|start>"
if !prev.contains("boot=\(bootTime) ") {
    let cause = sh("/usr/bin/log show --last boot --style compact --predicate 'eventMessage CONTAINS \"Previous shutdown cause\"' 2>/dev/null | grep -m1 -oE 'cause: -?[0-9]+' | grep -oE -- '-?[0-9]+'", timeout: 60)
    let lastEvents = sh("pmset -g log | grep -E '^[0-9-]+ [0-9:]+ [+0-9]+ (Sleep|Wake|DarkWake|Failure|Shutdown|Start|Restart|Hibernate)' | grep -v Requests | tail -6", timeout: 20)
    let failures = sh("pmset -g log | grep -iE 'Sleep Wake failure|Failure' | tail -3", timeout: 20)
    // VirtualSMC reports cause 5 even after panics/forced power-off on this laptop, so the cause is not used.
    let failed = prev.hasSuffix("last=sleep")
    log("BOOT  previous shutdown cause=\(cause.isEmpty ? "?" : cause)\(failed ? "  *** FAILED WAKE: last event before this boot was a sleep with no wake ***" : "")")
    log("      last power events before boot:\n        " + lastEvents.replacingOccurrences(of: "\n", with: "\n        "))
    if !failures.isEmpty { log("      pmset failures:\n        " + failures.replacingOccurrences(of: "\n", with: "\n        ")) }
    csv(failed ? "FAILED_WAKE" : "boot", ["0", "", "", "", "", "cause=\(cause); prev=\(prev)"])
}
setState("boot=\(bootTime) last=start")

// ---- power notifications
// iokit_common_msg(x) = 0xE0000000 | x (macros not imported into Swift)
let msgCanSystemSleep: UInt32 = 0xE000_0270
let msgSystemWillSleep: UInt32 = 0xE000_0280
let msgSystemHasPoweredOn: UInt32 = 0xE000_0300
var rootPort: io_connect_t = 0
var notifier: io_object_t = 0
var sleepStart = Date()

let callback: IOServiceInterestCallback = { _, _, messageType, messageArgument in
    switch messageType {
    case msgCanSystemSleep:
        IOAllowPowerChange(rootPort, Int(bitPattern: messageArgument))
    case msgSystemWillSleep:
        cycle += 1
        let q = quickInfo()
        let holders = sh("pmset -g assertions | grep -E '^ +pid [0-9]+' | grep -vE 'UserIsActive|BackgroundTask' | head -4 | sed -E 's/ +/ /g'", timeout: 3)
        setState("boot=\(bootTime) last=sleep")
        log("SLEEP #\(cycle)  hibernatemode=\(q.hib) battery=\(q.batt) lid=\(q.lid) \(q.temp)C" + (holders.isEmpty ? "" : "\n      assertions: " + holders.replacingOccurrences(of: "\n", with: "\n                  ")))
        csv("sleep", ["\(cycle)", q.hib, q.batt, q.lid, q.temp, holders])
        sleepStart = Date()
        IOAllowPowerChange(rootPort, Int(bitPattern: messageArgument))
    case msgSystemHasPoweredOn:
        setState("boot=\(bootTime) last=wake")
        let slept = Int(Date().timeIntervalSince(sleepStart))
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
            let wake = sh("pmset -g log | grep -E '^[0-9-]+ [0-9:]+ [+0-9]+ (Wake|DarkWake) ' | tail -1 | sed -E 's/ +/ /g'")
            let fail = sh("pmset -g log | grep -iE 'Sleep Wake failure' | tail -1")
            let q = quickInfo()
            log("WAKE  #\(cycle)  slept \(slept)s battery=\(q.batt) lid=\(q.lid) \(q.temp)C\n      \(wake)" + (fail.isEmpty ? "" : "\n      FAILURE: \(fail)"))
            csv("wake", ["\(cycle)", q.hib, q.batt, q.lid, q.temp, "slept=\(slept)s; \(wake)"])
        }
    default: break
    }
}

var notifyPort: IONotificationPortRef?
rootPort = IORegisterForSystemPower(nil, &notifyPort, callback, &notifier)
guard rootPort != 0, let port = notifyPort else { log("ERROR: IORegisterForSystemPower failed"); exit(1) }
CFRunLoopAddSource(CFRunLoopGetCurrent(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .defaultMode)
log("START sleepmon (hibernatemode=\(quickInfo().hib))")
CFRunLoopRun()

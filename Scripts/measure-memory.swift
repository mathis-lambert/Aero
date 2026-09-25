#!/usr/bin/env swift
// Reports the memory footprint of a running Auro and the WebKit processes it owns.
// Usage: swift Scripts/measure-memory.swift [process-name] [--sample seconds] [--detailed]
//
// Development tool only. WebKit XPC processes are children of launchd, so ownership is resolved
// with the private `responsibility_get_pid_responsible_for_pid` symbol, the attribution Activity
// Monitor also uses. It is looked up at run time and never linked into the application.

import Darwin
import Foundation

let defaultProcessName = "Auro"
let webKitProcessPattern = "com.apple.WebKit"

func run(_ tool: String, _ arguments: [String]) -> String {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = arguments
    process.standardOutput = output
    do { try process.run() } catch { fatalError("Cannot run \(tool): \(error)") }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return String(decoding: data, as: UTF8.self)
}

func pids(_ arguments: [String]) -> [pid_t] {
    run("/usr/bin/pgrep", arguments).split(separator: "\n").compactMap { pid_t($0) }
}

typealias ResponsiblePID = @convention(c) (pid_t) -> pid_t
guard let symbol = dlsym(dlopen(nil, RTLD_NOW), "responsibility_get_pid_responsible_for_pid") else {
    fatalError("Process attribution is unavailable on this system.")
}
let responsiblePID = unsafeBitCast(symbol, to: ResponsiblePID.self)

var arguments = Array(CommandLine.arguments.dropFirst())
var footprintOptions = ["--noCategories"]
if let index = arguments.firstIndex(of: "--detailed") {
    footprintOptions = []
    arguments.remove(at: index)
}
if let index = arguments.firstIndex(of: "--sample"), arguments.indices.contains(index + 1) {
    footprintOptions += ["--sample", arguments[index + 1]]
    arguments.removeSubrange(index...index + 1)
}
let processName = arguments.first ?? defaultProcessName

let applications = Set(pids(["-x", processName]))
guard !applications.isEmpty else {
    print("\(processName) is not running.")
    exit(1)
}
let webKit = pids(["-f", webKitProcessPattern]).filter { applications.contains(responsiblePID($0)) }
let targets = (applications.sorted() + webKit).flatMap { ["--pid", String($0)] }
print("\(processName): \(applications.count) process(es), WebKit: \(webKit.count) process(es)")
print(run("/usr/bin/footprint", footprintOptions + targets))

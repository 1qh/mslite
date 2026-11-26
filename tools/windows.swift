// Print every on-screen window a process owns, 1 per line: its title and its size.
// usage: swift windows.swift <pid>
import CoreGraphics
import Foundation

guard CommandLine.arguments.count == 2, let pid = Int(CommandLine.arguments[1]) else {
  FileHandle.standardError.write("usage: swift windows.swift <pid>\n".data(using: .utf8)!)
  exit(2)
}
let listed = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
for window in listed where (window[kCGWindowOwnerPID as String] as? Int) == pid {
  let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
  let title = window[kCGWindowName as String] as? String ?? ""
  let layer = window[kCGWindowLayer as String] as? Int ?? 0
  let onscreen = window[kCGWindowIsOnscreen as String] as? Bool ?? false
  let alpha = window[kCGWindowAlpha as String] as? Double ?? 0
  print("layer \(layer) \(bounds["Width"] ?? 0)x\(bounds["Height"] ?? 0) onscreen=\(onscreen) alpha=\(alpha) \(title)")
}

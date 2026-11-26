// Refuse any on-screen window of a process that reaches past the visible area of every screen: onscreen.swift <pid>
// Window bounds come from the window server with the origin at the top left of the main screen; each screen's visible
// frame comes from AppKit with the origin at the bottom left, so it is flipped against the main screen's height.
import AppKit
import CoreGraphics

guard CommandLine.arguments.count == 2, let pid = Int(CommandLine.arguments[1]) else {
  FileHandle.standardError.write("usage: onscreen.swift <pid>\n".data(using: .utf8)!)
  exit(2)
}
guard let main = NSScreen.screens.first else {
  FileHandle.standardError.write("no screen\n".data(using: .utf8)!)
  exit(1)
}
let visible = NSScreen.screens.map { screen -> CGRect in
  let frame = screen.visibleFrame
  return CGRect(x: frame.minX, y: main.frame.height - frame.maxY, width: frame.width, height: frame.height)
}
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
var judged = 0
var outside: [String] = []
for window in list where (window[kCGWindowOwnerPID as String] as? Int) == pid {
  let layer = window[kCGWindowLayer as String] as? Int ?? -1
  guard layer == 0 || layer == 3, let raw = window[kCGWindowBounds as String] as? [String: Any],
        let bounds = CGRect(dictionaryRepresentation: raw as CFDictionary), bounds.width > 1, bounds.height > 1 else { continue }
  judged += 1
  // a 1-point tolerance for the window server's rounding of a frame placed at the screen's very edge
  if !visible.contains(where: { $0.insetBy(dx: -1, dy: -1).contains(bounds) }) {
    outside.append("layer \(layer) window at \(Int(bounds.minX)),\(Int(bounds.minY)) size \(Int(bounds.width))x\(Int(bounds.height))")
  }
}
if judged == 0 {
  FileHandle.standardError.write("no on-screen window of process \(pid) to judge\n".data(using: .utf8)!)
  exit(1)
}
if !outside.isEmpty {
  FileHandle.standardError.write((["windows reaching past the screen's visible area:"] + outside).joined(separator: "\n").appending("\n").data(using: .utf8)!)
  exit(1)
}
print("ok (\(judged) windows inside the screen's visible area)")

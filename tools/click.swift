// Click the left mouse button at a screen point given in global display points: click.swift <x> <y>
import CoreGraphics
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3, let x = Double(arguments[1]), let y = Double(arguments[2]) else {
  FileHandle.standardError.write("usage: click.swift <x> <y>\n".data(using: .utf8)!)
  exit(2)
}
let point = CGPoint(x: x, y: y)
for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
  guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else {
    FileHandle.standardError.write("no mouse event could be made\n".data(using: .utf8)!)
    exit(1)
  }
  event.post(tap: .cghidEventTap)
  usleep(100_000)
}

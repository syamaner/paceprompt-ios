#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation

struct Window {
  let id: CGWindowID
  let bounds: CGRect
}

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data(("error: \(message)\n").utf8))
  exit(1)
}

let arguments = Array(CommandLine.arguments.dropFirst())
let requestedID: CGWindowID?
if arguments == ["--list"] {
  requestedID = nil
} else if arguments.count == 2, arguments[0] == "--require-id" {
  guard let value = UInt32(arguments[1]) else {
    fail("--require-id needs a numeric window ID")
  }
  requestedID = value
} else {
  fail("usage: find_codex_window.swift --list | --require-id WINDOW_ID")
}

guard
  let entries = CGWindowListCopyWindowInfo(
    [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
  ) as? [[String: Any]]
else {
  fail("could not enumerate on-screen windows")
}

let windows: [Window] = entries.compactMap { entry in
  guard
    let ownerPIDValue = entry[kCGWindowOwnerPID as String] as? NSNumber,
    let application = NSRunningApplication(
      processIdentifier: pid_t(ownerPIDValue.int32Value)
    ),
    application.bundleIdentifier == "com.openai.codex",
    let layer = entry[kCGWindowLayer as String] as? Int,
    layer == 0,
    let numberValue = entry[kCGWindowNumber as String] as? NSNumber,
    let boundsValue = entry[kCGWindowBounds as String]
  else { return nil }

  let boundsDictionary = boundsValue as! CFDictionary
  guard
    let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
    bounds.width >= 400,
    bounds.height >= 250
  else { return nil }

  return Window(
    id: CGWindowID(numberValue.uint32Value),
    bounds: bounds
  )
}

if let requestedID {
  guard let window = windows.first(where: { $0.id == requestedID }) else {
    fail("window \(requestedID) is not an on-screen Codex window")
  }
  print(
    "\(window.id)\t\(Int(window.bounds.origin.x))\t\(Int(window.bounds.origin.y))\t\(Int(window.bounds.width))\t\(Int(window.bounds.height))"
  )
  exit(0)
}

guard !windows.isEmpty else {
  fail("no on-screen Codex window was found")
}

print("WINDOW_ID\tX\tY\tWIDTH\tHEIGHT")
for window in windows.sorted(by: {
  $0.bounds.width * $0.bounds.height > $1.bounds.width * $1.bounds.height
}) {
  print(
    "\(window.id)\t\(Int(window.bounds.origin.x))\t\(Int(window.bounds.origin.y))\t\(Int(window.bounds.width))\t\(Int(window.bounds.height))"
  )
}

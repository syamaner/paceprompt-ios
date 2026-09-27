#!/usr/bin/env python3
"""Enforce the v1 profile dependency/side-effect boundary; no private data is read."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
profiles = root / "PacePrompt/Profiles"
errors = []
for name in ("PlanningProfile.swift", "PlanningProfileLifecycle.swift", "PlanningProfilesView.swift", "PlanningProfileSelector.swift", "HistoricalPlanCompatibility.swift"):
    text = (profiles / name).read_text()
    forbidden = r"\b(?:CoreBluetooth|CBPeripheral|CBCharacteristic|FileManager|FileHandle|URLSession|URLRequest|CryptoKit|Security|UserDefaults)\b"
    if re.search(forbidden, text):
        errors.append(f"{name}: infrastructure type crosses profile application/presentation boundary")
domain = (profiles / "HistoricalPlanCompatibility.swift").read_text()
if re.search(r"\b(?:SwiftUI|Combine|ObservableObject|PlanningProfilesViewModel|PlanningProfileRepository|PlanValueFormatter)\b", domain):
    errors.append("HistoricalPlanCompatibility.swift: historical policy depends on presentation or persistence")
for path in profiles.glob("*.swift"):
    text = path.read_text()
    if re.search(r"\b(?:URLSession|URLRequest|UserDefaults|NSUbiquitousKeyValueStore|print|os_log)\b|\.(?:writeValue|startScan|stopScan|connect|disconnect)\s*\(", text):
        errors.append(f"{path.name}: profile subsystem contains a prohibited network/logging/Bluetooth side effect")
for directory in ("Import", "Plans", "History", "Health", "Execution"):
    for path in (root / "PacePrompt" / directory).glob("*.swift"):
        if path.name == "WorkoutImportView.swift":
            continue
        if re.search(r"\b(?:PlanningProfile|PlanningProfilesViewModel|PlanningProfileStore|PlanningProfileSnapshot|PlanningProfileSelectorRow|OptionalPlanningProfileSelector)\b", path.read_text()):
            errors.append(f"{path.relative_to(root)}: profile dependency enters excluded domain/transport subsystem")
if errors:
    raise SystemExit("\n".join(errors))
print("Saved treadmill profile v1 dependency and side-effect boundaries verified.")

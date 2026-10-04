import Foundation
import SwiftUI
import HealthKit

@MainActor final class MemoryJournal: WatchJournalStore {
 var value: WatchWorkoutJournal?
 func load() throws -> WatchWorkoutJournal? { value }
 func save(_ journal: WatchWorkoutJournal) throws { value = journal }
 func containsRetiredIdentity(_ id: String) throws -> Bool { false }
 func archive(_ journal: WatchWorkoutJournal) throws {}
}

// The sole substitution is native companion mirroring. All native writer/session operations are forwarded.
@MainActor final class ProbeOperations: WatchSessionOperations {
 let native = WatchHealthKitAdapter()
 var pauseDates: [Date] = []
 var resumedAfterCallbacks: [Date] = []
 var savedID: String?
 #if !LEGACY_WRITER
 var sampleEvidence: WatchDistanceSampleEvidence?
 var nativeDecision: WatchNativeDistanceDecision?
 #endif
 var didAuthorize: () -> Void = {}
 var log: (String) -> Void = { _ in }
 var collectionStarted: Bool { native.collectionStarted }
 var activityStopped: Bool { native.activityStopped }
 var sourceExcludesDistance: Bool { native.sourceExcludesDistance }
 var hasDistance: Bool { native.hasDistance }
 var distanceAuthorized: Bool { native.distanceAuthorized }
 var activities: [WatchBuilderActivity] { native.activities }
 func resetForNewAttempt() throws { log("reset"); try native.resetForNewAttempt() }
 func authorize() async throws -> Bool { log("authorize"); let v = try await native.authorize(); log("authorized=\(v)"); if v {didAuthorize()}; return v }
 func recoverPrimary() async throws -> WatchRecoveredRecording? { log("recover"); return try await native.recoverPrimary() }
 func createPrimary(activity: String) throws { log("create"); try native.createPrimary(activity:activity) }
 func configureCollection() throws { log("configure"); try native.configureCollection() }
 func preparePrimary() { log("prepare"); native.preparePrimary() }
 func mirrorPrimary() async throws { log("mirror EXPLICIT TEST NO-OP") }
 func startPrimary() async throws -> Date { log("start"); return try await native.startPrimary() }
 func beginCollection(at date: Date) async throws { log("beginCollection"); try await native.beginCollection(at:date) }
 func pausePrimary() async throws -> Date { log("pause"); let date=try await native.pausePrimary();pauseDates.append(date);return date }
 func resumePrimary() async throws { log("resume"); try await native.resumePrimary();resumedAfterCallbacks.append(Date()) }
 func cancelPendingOperations() { native.cancelPendingOperations() }
 func stopActivityAndVerify(at date: Date) async throws { log("stopActivity"); try await native.stopActivityAndVerify(at:date);log("activityStopped") }
 func endPrimary() { log("end");native.endPrimary() }
 func stopPrimaryAndVerify() async throws { try await native.stopPrimaryAndVerify() }
 func discardBuilder() throws { log("discard");try native.discardBuilder() }
 func finishBuilder() async throws -> String? { log("finish"); savedID = try await native.finishBuilder();log("finished=\(savedID ?? "nil")");return savedID }
 func endCollection(at date: Date) async throws { log("endCollection");try await native.endCollection(at:date) }
 func addActivity(_ interval: WatchInterval, summaryID: String, activity: String) async throws { log("addActivity");try await native.addActivity(interval,summaryID:summaryID,activity:activity) }
 func addDistance(metres: Decimal, summaryID: String, start: Date, end: Date) async throws { log("addDistance");try await native.addDistance(metres:metres,summaryID:summaryID,start:start,end:end) }
 #if LEGACY_WRITER
 func addMetadata(_ value: WatchAssembly, distanceIncluded: Bool) async throws { log("addMetadata");try await native.addMetadata(value,distanceIncluded:distanceIncluded) }
 #else
 func distanceSampleEvidence() -> WatchDistanceSampleEvidence { let evidence=native.distanceSampleEvidence();sampleEvidence=evidence;return evidence }
 func addMetadata(_ value: WatchAssembly, distanceDecision: WatchNativeDistanceDecision) async throws { nativeDecision=distanceDecision;log("addMetadata decision=\(distanceDecision)");try await native.addMetadata(value,distanceDecision:distanceDecision) }
 #endif
}

@MainActor final class ProbeModel: ObservableObject {
 @Published var status = "Ready: synthetic simulator only"
 var lines: [String] = []
 lazy var operations = ProbeOperations()
 let journal = MemoryJournal()
 var lifecycle: WatchWorkoutLifecycle?
 var responses: [WatchWireMessage] = []
 var started = false
 var root: URL { FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0] }
 func log(_ s: String) {
  status=s;lines.append(s)
  try? FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
  try? lines.joined(separator:"\n").write(to:root.appendingPathComponent("probe.log"),atomically:true,encoding:.utf8)
 }
 func run() async {
  #if !targetEnvironment(simulator)
  fatalError("Synthetic probe is simulator-only")
  #endif
  guard ProcessInfo.processInfo.environment["SIMULATOR_UDID"] == "__WATCH_UDID__" else {log("REFUSED: not dedicated synthetic simulator");return}
  guard !started else {return};started=true
  operations.log = { [weak self] in self?.log($0) }
  let recording=WatchRecordingAdapter(operations:operations)
  let flow=WatchWorkoutLifecycle(store:journal,recording:recording,now:Date.init,monotonic:{ProcessInfo.processInfo.systemUptime},send:{[weak self] data in
   guard let m=try? WatchWire.decode(data) else{return};self?.responses.append(m);self?.log("response=\(m.kind.rawValue)")
  })
  lifecycle=flow
  operations.native.paused = { [weak flow] in flow?.recordingState(paused:$0) }
  operations.native.failed = { [weak flow] in await flow?.failed() }
  flow.changed = { [weak self,weak flow] in self?.log("lifecycle=\(flow?.display ?? "nil")") }
  operations.didAuthorize = { [weak self] in
   Task { [weak self] in
   try? await Task.sleep(for:.seconds(90))
   guard let self,self.journal.value?.phase != .saved else{return}
   self.log("TIMEOUT: \(String(describing:self.journal.value?.phase))")
   await self.lifecycle?.forceStop()
   }
  }
  do {
   let legacyCases=["v1-complete", "v2-paused", "v2-rich", "v2-incomplete", "v2-rich-rejected"]
   #if LEGACY_WRITER
   let cases=legacyCases
   #else
   let cases=legacyCases + ["v3-paused", "v3-zero", "v3-incomplete"] + (0..<8).map { "v3-safe-\($0)" } + ["v3-rich"]
   #endif
   guard let name=ProcessInfo.processInfo.arguments.first(where: { cases.contains($0) }) else {log("READY: choose an explicit synthetic scenario through the harness");return}
   let pausedCase=name.hasSuffix("-paused")
   let rich=name.hasSuffix("-rich") || name=="v2-rich-rejected"
   let rejected=name=="v2-rich-rejected"
   let incomplete=name.hasSuffix("-incomplete")
   let version=name=="v1-complete" ? 1 : name.hasPrefix("v2-") ? 2 : 3
   let zero=name=="v3-zero"

   log("SETUP: real producer authorization before lifecycle startup deadline")
   guard try await operations.native.authorize() else {throw ProbeError.failure("preflight write authorization denied")}
   await flow.launch(activity:"indoorWalking")
   let suffix = __CASE_SUFFIXES__[name]!
   let summary="00000000-0000-4000-8000-00000000"+suffix
   var bind=WatchWireMessage(.bind,summaryID:summary);bind.workoutActivity="indoorWalking"
   await flow.receive(try WatchWire.encode(bind))
   guard let start=responses.last(where:{$0.kind == .bound})?.workoutStart else {throw ProbeError.failure("no bound: \(flow.display)")}
   var pausedBoundary:Date?, resumedBoundary:Date?
   if pausedCase {
    try await Task.sleep(for:.seconds(2))
    var pause=WatchWireMessage(.recordingState,summaryID:summary);pause.sequence=1;pause.state="paused";pause.observedAt=Date()
    await flow.receive(try WatchWire.encode(pause));pausedBoundary=operations.pauseDates.last
    guard journal.value?.paused == true else {throw ProbeError.failure("native pause not confirmed")}
    try await Task.sleep(for:.seconds(3))
    var resume=WatchWireMessage(.recordingState,summaryID:summary);resume.sequence=2;resume.state="running";resume.observedAt=Date()
    await flow.receive(try WatchWire.encode(resume));resumedBoundary=operations.resumedAfterCallbacks.last
    guard journal.value?.paused == false else {throw ProbeError.failure("native resume not confirmed")}
    try await Task.sleep(for:.seconds(2))
   } else {try await Task.sleep(for:.seconds(rich ? 6 : 3))}
   var prepare=WatchWireMessage(.prepareEnd,summaryID:summary);prepare.sequence=pausedCase ? 3 : 1
   await flow.receive(try WatchWire.encode(prepare))
   guard let end=responses.last(where:{$0.kind == .endPrepared})?.workoutEnd else {throw ProbeError.failure("no preparedEnd")}
   let a=start.addingTimeInterval(0.5),b=end.addingTimeInterval(-0.5)
   let i=WatchInterval(segmentIndex:0,intervalIndex:0,startedAt:a,endedAt:b,prescribed:.init(kind:"interval",speedKilometresPerHour:3,inclinationPercent:0),effectiveSpeed:.init(kilometresPerHour:3,source:"planned"),effectiveInclination:.init(percent:0,source:"planned"),settledObservation:.init(observedAt:a,speedKilometresPerHour:3,inclinationPercent:0,provenance:"fr30zTreadmillDataCurrentEpoch"),endReason:"completed",intervalDistance:version == 1 ? nil : .observed(startMetres:100,endMetres:zero ? 100 : 110,start:a,end:b))
   var intervals=[i]
   if rich {
    let c=start.addingTimeInterval(2.125),d=start.addingTimeInterval(2.75)
    intervals=[
     WatchInterval(segmentIndex:0,intervalIndex:0,startedAt:a,endedAt:c,prescribed:.init(kind:"interval",speedKilometresPerHour:Decimal(string:"3.125")!,inclinationPercent:Decimal(string:"1.25")!),effectiveSpeed:.init(kilometresPerHour:Decimal(string:"3.5")!,source:"manualOverride"),effectiveInclination:.init(percent:Decimal(string:"2.75")!,source:"manualOverride"),settledObservation:.init(observedAt:a,speedKilometresPerHour:Decimal(string:rejected ? "3.375" : "3.5")!,inclinationPercent:Decimal(string:rejected ? "2.5" : "2.75")!,provenance:"fr30zTreadmillDataCurrentEpoch"),endReason:"targetChanged",intervalDistance:.observed(startMetres:Decimal(string:"100.125")!,endMetres:Decimal(string:"112.5")!,start:a.addingTimeInterval(0.125),end:c.addingTimeInterval(-0.125))),
     WatchInterval(segmentIndex:0,intervalIndex:1,startedAt:d,endedAt:b,prescribed:.init(kind:"interval",speedKilometresPerHour:Decimal(string:"5.125")!,inclinationPercent:Decimal(string:"3.25")!),effectiveSpeed:.init(kilometresPerHour:Decimal(string:"4.875")!,source:"manualOverride"),effectiveInclination:.init(percent:3,source:"manualOverride"),settledObservation:.init(observedAt:d,speedKilometresPerHour:Decimal(string:rejected ? "4.625" : "4.875")!,inclinationPercent:Decimal(string:rejected ? "2.875" : "3")!,provenance:"fr30zTreadmillDataCurrentEpoch"),endReason:"completed",intervalDistance:.unavailable())]
   }
   if pausedCase {
    guard let pause=pausedBoundary,let resume=resumedBoundary else {throw ProbeError.failure("missing native pause/resume boundaries")}
    let c=pause.addingTimeInterval(-0.2),d=resume.addingTimeInterval(0.2)
    intervals=[
     WatchInterval(segmentIndex:0,intervalIndex:0,startedAt:a,endedAt:c,prescribed:i.prescribed,effectiveSpeed:i.effectiveSpeed,effectiveInclination:i.effectiveInclination,settledObservation:i.settledObservation,endReason:"paused",intervalDistance:.observed(startMetres:100,endMetres:130,start:a,end:c)),
     WatchInterval(segmentIndex:0,intervalIndex:1,startedAt:d,endedAt:b,prescribed:i.prescribed,effectiveSpeed:i.effectiveSpeed,effectiveInclination:i.effectiveInclination,settledObservation:.init(observedAt:d,speedKilometresPerHour:3,inclinationPercent:0,provenance:"fr30zTreadmillDataCurrentEpoch"),endReason:"completed",intervalDistance:.observed(startMetres:130,endMetres:200,start:d,end:b))]
   }
   var m=WatchWireMessage(.manifest,summaryID:summary);m.schemaVersion=version;m.revision=1;m.workoutActivity="indoorWalking";m.workoutStart=start;m.workoutEnd=end;m.final=true;m.localOutcome="completed";m.intervals=intervals;m.distance = .init(state:"accepted",metres:zero ? 0 : 10,provenance:"fr30zCumulativeDistanceDelta")
   if rich {m.distance = .init(state:"accepted",metres:Decimal(string:"30.625")!,provenance:"fr30zCumulativeDistanceDelta")}
   if pausedCase {m.distance = .init(state:"accepted",metres:100,provenance:"fr30zCumulativeDistanceDelta")}
   if incomplete {m.final=false;m.workoutEnd=nil;m.localOutcome=nil;m.distance = .unavailable}
   let wire=try WatchWire.encode(m);try wire.write(to:root.appendingPathComponent("\(name).manifest.json"))
   await flow.receive(wire)
   var f=WatchWireMessage(.finalize,summaryID:summary);f.revision=1
   if incomplete {log("TEST: no final manifest/finalize; wait for actual prepare-end deadline");try await Task.sleep(for:.seconds(6));await flow.tick()}
   else {await flow.receive(try WatchWire.encode(f))}
   guard journal.value?.phase == .saved,let id=operations.savedID,let uuid=UUID(uuidString:id) else {throw ProbeError.failure("not saved: \(flow.display)")}
   log("request synthetic workout read permission")
   let store=HKHealthStore();try await store.requestAuthorization(toShare:[],read:[HKObjectType.workoutType()])
   let workout:HKWorkout = try await withCheckedThrowingContinuation { continuation in
    let completion = OneShotWorkout(continuation)
    let q=HKSampleQuery(sampleType:.workoutType(),predicate:HKQuery.predicateForObject(with:uuid),limit:1,sortDescriptors:nil) { _,samples,error in
     if let w=samples?.first as? HKWorkout {completion.finish(.success(w))} else {completion.finish(.failure(error ?? ProbeError.failure("saved UUID query empty")))}
    };store.execute(q)
    DispatchQueue.global().asyncAfter(deadline:.now()+15) { store.stop(q);completion.finish(.failure(ProbeError.failure("saved UUID query timed out after 15 seconds"))) }
   }
   let data=try NSKeyedArchiver.archivedData(withRootObject:workout,requiringSecureCoding:true)
   try data.write(to:root.appendingPathComponent("\(name).hkworkout"))
   var receipt:[String:Any] = ["name":name,"archive":"\(name).hkworkout","synthetic":true,"nativeSourceBundleIdentifier":workout.sourceRevision.source.bundleIdentifier,"summaryID":summary,"nativeUUID":workout.uuid.uuidString,"nativeWorkoutUUID":workout.uuid.uuidString,"activityCount":workout.workoutActivities.count,"start":workout.startDate.timeIntervalSince1970,"end":workout.endDate.timeIntervalSince1970,"duration":workout.duration,"expectedRecognition":rejected ? "invalid" : incomplete ? "supportedIncomplete" : "supportedComplete","expectedVersion":version,"expectedIntervalCount":intervals.count,"expectedActivityCount":intervals.count,"transportExclusion":"mirrorPrimary no-op; bytes delivered in-process","nativePauseReturnDates":operations.pauseDates.map(\.timeIntervalSince1970),"nativeResumeCallbackCompletedDates":operations.resumedAfterCallbacks.map(\.timeIntervalSince1970)]
   #if !LEGACY_WRITER
   if let evidence=operations.sampleEvidence {
    receipt["nativeCollectionStart"] = evidence.collectionStart?.timeIntervalSince1970
    receipt["nativeCollectionEnd"] = evidence.collectionEnd?.timeIntervalSince1970
    receipt["nativeEvents"] = evidence.events.map { ["kind":String(describing:$0.kind),"start":$0.start.timeIntervalSince1970,"end":$0.end.timeIntervalSince1970] as [String:Any] }
   }
   if let decision=operations.nativeDecision {receipt["nativeSampleIncluded"]=decision.included;receipt["nativeSampleReason"]=decision.reason?.rawValue}
   #endif
   try JSONSerialization.data(withJSONObject:receipt,options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent("\(name).receipt.json"))
   log("SUCCESS: saved/query/archive activities=\(workout.workoutActivities.count)")
  } catch {log("ERROR: \(String(reflecting:error))")}
 }
}
final class OneShotWorkout: @unchecked Sendable {
 private let lock=NSLock()
 private var continuation:CheckedContinuation<HKWorkout,Error>?
 init(_ continuation:CheckedContinuation<HKWorkout,Error>) {self.continuation=continuation}
 func finish(_ result:Result<HKWorkout,Error>) {lock.lock();let c=continuation;continuation=nil;lock.unlock();c?.resume(with:result)}
}
enum ProbeError: Error {case failure(String)}
@main struct ProbeApp: App {
 @StateObject var model=ProbeModel()
 var body:some Scene {WindowGroup {ScrollView {VStack {Text("Synthetic-only Health probe");Text(model.status);Button("Stop synthetic recording"){Task{await model.lifecycle?.forceStop()}}}}.task {await model.run()}}}
}

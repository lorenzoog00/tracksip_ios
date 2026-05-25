import SwiftUI
import StoreKit
import Combine
import UIKit
import UserNotifications
import SipTrackActivityKit

@MainActor
final class AppState: ObservableObject {

    // MARK: - Published state

    @Published var events: [NightEvent]      = []
    @Published var entries: [DrinkEntry]     = []
    @Published var waterEntries: [WaterEntry] = []
    @Published var foodEntries: [FoodEntry]  = []
    @Published var customDrinkTypes: [DrinkType] = []
    @Published var userProfile: UserProfile  = UserProfile()
    @Published var challenges: [Challenge]   = []

    @Published var activeWarnings: [DrinkWarning] = []
    @Published var undoEntry: DrinkEntry?    = nil
    @Published var undoWaterEntry: WaterEntry? = nil
    @Published var showWaterNudge: Bool      = false
    @Published var currentUserId: String?    = nil
    @Published var shouldShowAuth: Bool      = false
    @Published var syncFailed: Bool          = false
    @Published var generatingReportForEventId: String? = nil
    @Published var failedReportEventIds: Set<String> = []
    @Published var coachReports: [CoachReport] = []
    @Published var generatingCoachReportId: String? = nil
    @Published var failedCoachReportIds: Set<String> = []
    @Published var nightRecoveries: [NightRecovery] = []
    @Published var generatingRecoveryForEventId: String? = nil
    @Published var failedRecoveryEventIds: Set<String> = []

    /// Fires every 10 s while an event is active. All views that show live BAC
    /// read `_ = appState.bacTick` so they recompute in sync.
    @Published var bacTick: Date = Date()

    /// Set by ActiveEventView right after End Night so RootView can pop the
    /// active event and push SummaryView cleanly.
    @Published var pendingSummaryEventId: String? = nil

    /// Set by CreateEventView so RootView pushes the new event immediately.
    @Published var pendingEventRouteId: String? = nil

    let store: StoreManager

    private var undoTask: Task<Void, Never>?
    private var undoWaterTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var bacTimerTask: Task<Void, Never>?
    private var authCancellable: AnyCancellable?

    // MARK: - Computed

    var allDrinkTypes: [DrinkType] { DrinkType.mergedWith(custom: customDrinkTypes) }
    var isPro: Bool { store.isPro || userProfile.isPro }

    static let freeMonthlyReportLimit = 5

    private func currentMonthKey() -> String {
        let cal = Calendar.current
        let y = cal.component(.year, from: Date())
        let m = cal.component(.month, from: Date())
        return String(format: "%04d-%02d", y, m)
    }

    var freeAiReportsUsedThisMonth: Int {
        guard !isPro else { return 0 }
        let key = currentMonthKey()
        return userProfile.aiReportMonthKey == key ? userProfile.aiReportsUsedThisMonth : 0
    }

    var canGenerateNightReport: Bool {
        isPro || freeAiReportsUsedThisMonth < Self.freeMonthlyReportLimit
    }

    var activeEvent: NightEvent? {
        events.first { $0.isActive && $0.userId == currentUserId }
    }

    var latestWeeklyReport: CoachReport? {
        coachReports.filter { $0.type == .weekly }.max(by: { $0.createdAt < $1.createdAt })
    }

    var latestMonthlyReport: CoachReport? {
        coachReports.filter { $0.type == .monthly }.max(by: { $0.createdAt < $1.createdAt })
    }

    var visibleEvents: [NightEvent] {
        guard let uid = currentUserId else { return [] }
        let finished = events
            .filter { $0.endTime != nil && $0.userId == uid }
            .sorted { $0.startTime > $1.startTime }
        if isPro { return finished }
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date(timeIntervalSinceNow: -(30 * 24 * 3600))
        return finished.filter { $0.startTime >= cutoff }
    }

    // MARK: - Init

    init(store: StoreManager) {
        self.store = store
        currentUserId = FirebaseManager.shared.currentUserId()
        loadAll()
        if let active = activeEvent {
            WaterReminderManager.shared.schedule(intervalMinutes: userProfile.waterReminderIntervalMinutes)
            startBACRefreshTimer(for: active.id)
        }
        authCancellable = FirebaseManager.shared.$isSignedIn
            .receive(on: RunLoop.main)
            .sink { [weak self] isSignedIn in
                let wasSignedIn = self?.currentUserId != nil
                self?.currentUserId = FirebaseManager.shared.currentUserId()
                if wasSignedIn && !isSignedIn {
                    self?.resetProfile()
                } else if isSignedIn {
                    self?.refreshFromFirebase()
                }
            }
        refreshFromFirebase()
        checkAndGenerateAutoReports()
        syncPendingRecoveries()
        scheduleCoachReportReminders()
    }

    private func resetProfile() {
        DataStore.shared.clearAllData()
        events = []; entries = []; waterEntries = []; foodEntries = []
        customDrinkTypes = []; challenges = []; coachReports = []; nightRecoveries = []
        userProfile = UserProfile()
        shouldShowAuth = true
    }

    private func loadAll() {
        let ds = DataStore.shared
        events           = ds.loadEvents()
        entries          = ds.loadEntries()
        waterEntries     = ds.loadWaterEntries()
        foodEntries      = ds.loadFoodEntries()
        customDrinkTypes = ds.loadCustomDrinkTypes()
        userProfile      = ds.loadUserProfile()
        challenges       = ds.loadChallenges()
        coachReports     = ds.loadCoachReports()
        nightRecoveries  = ds.loadNightRecoveries()
        // First-launch locale seed — only runs once, before user sets a country.
        if userProfile.countryCode == nil, let detected = LegalBACLimits.detectFromLocale() {
            userProfile.countryCode = detected.countryCode
            userProfile.bacLimit = detected.limit(for: userProfile.driverType)
            DataStore.shared.saveUserProfile(userProfile)
        }
    }

    func refreshFromFirebase() {
        guard currentUserId != nil else { return }
        Task {
            let data = await FirebaseManager.shared.pullUserData()
            applyCloudData(data)
            checkAndGenerateAutoReports()
            checkAndGenerateRecoveries()
            syncPendingRecoveries()
        }
    }

    // MARK: - Events

    @discardableResult
    func createEvent(
        name: String?,
        drivingMode: Bool,
        bacLimit: Double?,
        targetBAC: Double? = nil,
        startTime: Date = Date(),
        stomachState: StomachState = .empty
    ) -> NightEvent {
        var event = DataStore.shared.createEvent(name: name, drivingMode: drivingMode, bacLimit: bacLimit, userId: currentUserId, startTime: startTime)
        event.stomachState = stomachState
        event.stomachStateTimestamp = startTime
        event.targetBAC = targetBAC
        DataStore.shared.updateEvent(event)
        events.append(event)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        push { try await FirebaseManager.shared.pushEvent(event) }
        WatchBridge.shared.pushState()
        startBACRefreshTimer(for: event.id)
        startLiveActivity(for: event)
        WaterReminderManager.shared.schedule(intervalMinutes: userProfile.waterReminderIntervalMinutes)
        return event
    }

    private func startBACRefreshTimer(for eventId: String) {
        bacTimerTask?.cancel()
        bacTimerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                bacTick = Date()           // single clock: all views re-render here
                updateLiveActivity(for: eventId)
            }
        }
    }

    private func startLiveActivity(for event: NightEvent) {
        print("🟡 startLiveActivity called for event: \(event.id)")
        if #available(iOS 16.2, *) {
            let ids = userProfile.liveActivityDrinkIds.isEmpty
                ? ["beer", "red-wine", "tequila", "gin-tonic"]
                : userProfile.liveActivityDrinkIds
            let quickDrinks = allDrinkTypes
                .filter { ids.contains($0.id) }
                .prefix(3)
                .map { SipTrackActivityAttributes.QuickDrink(id: $0.id, name: $0.name, symbol: $0.sfSymbol) }
            LiveActivityManager.shared.start(
                eventName: event.displayName,
                eventId: event.id,
                quickDrinks: Array(quickDrinks)
            )
        }
    }

    private func updateLiveActivity(for eventId: String) {
        if #available(iOS 16.2, *) {
            guard let event = events.first(where: { $0.id == eventId }) else { return }
            let bac = currentBAC(for: eventId)
            let stage = IntoxicationStage.stage(for: bac)
            let elapsed = Int(max(0, -event.startTime.timeIntervalSinceNow) / 60)

            var safeToDriveAt: Date? = nil
            if event.drivingMode {
                let limit = event.bacLimit ?? userProfile.resolvedBACLimit
                if bac > limit {
                    let hoursUntilSafe = (bac - limit) / 0.015
                    safeToDriveAt = Date().addingTimeInterval(hoursUntilSafe * 3600)
                }
            }

            LiveActivityManager.shared.update(
                bac: bac,
                drinkCount: totalDrinks(for: eventId),
                stageName: stage.name,
                stageColorHex: stage.colorHex,
                elapsedMinutes: elapsed,
                safeToDriveAt: safeToDriveAt
            )
        }
    }

    func endEvent(_ id: String) {
        bacTimerTask?.cancel()
        bacTimerTask = nil
        updateEvent(id: id) { $0.endTime = Date() }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if #available(iOS 16.2, *) { LiveActivityManager.shared.end() }
        WaterReminderManager.shared.cancel()
        WatchBridge.shared.pushState()
        generateAiReport(for: id)
        generateRecoveryBrief(for: id)
    }

    // MARK: - AI Report

    private func incrementAiReportUsage() {
        guard !isPro else { return }
        var profile = userProfile
        let key = currentMonthKey()
        if profile.aiReportMonthKey != key {
            profile.aiReportMonthKey = key
            profile.aiReportsUsedThisMonth = 1
        } else {
            profile.aiReportsUsedThisMonth += 1
        }
        updateUserProfile(profile)
    }

    func generateAiReport(for eventId: String) {
        guard canGenerateNightReport else { return }
        guard let event = events.first(where: { $0.id == eventId }),
              let endTime = event.endTime else { return }
        let eventEntries = entries.filter { $0.eventId == eventId }
        let eventWater = waterEntries.filter { $0.eventId == eventId }
        let eventFoodEntries = foodEntries.filter { $0.eventId == eventId }

        let timeline = BACCalculator.bacTimeline(
            entries: eventEntries,
            drinkTypes: allDrinkTypes,
            profile: userProfile,
            eventStart: event.startTime
        )
        let peakPoint = timeline.max(by: { $0.bac < $1.bac })
        let peakBAC = peakPoint?.bac ?? 0
        let peakBacTime: String = {
            guard let date = peakPoint?.date else { return "" }
            let f = DateFormatter(); f.timeStyle = .short
            return f.string(from: date)
        }()
        let durationMinutes = Int(event.duration / 60)
        let drinkData: [[String: Any]] = Dictionary(grouping: eventEntries) { $0.drinkTypeId }
            .compactMap { typeId, es -> [String: Any]? in
                guard let dt = allDrinkTypes.first(where: { $0.id == typeId }) else { return nil }
                return ["name": dt.name, "quantity": es.reduce(0) { $0 + $1.quantity }]
            }
        let drinkCount = eventEntries.reduce(0) { $0 + $1.quantity }

        // Pre-computed insights for AI prompt.
        // Note: custom drink types with unrecognised icons fall to "cocktails" via drinkCategory's default case.
        var drinkCategoryCounts: [String: Int] = [:]
        for entry in eventEntries {
            guard let dt = allDrinkTypes.first(where: { $0.id == entry.drinkTypeId }) else { continue }
            drinkCategoryCounts[dt.drinkCategory, default: 0] += entry.quantity
        }
        let dominantDrinkType: String = {
            guard !drinkCategoryCounts.isEmpty, drinkCount > 0 else { return "mixed" }
            guard let top = drinkCategoryCounts.max(by: { $0.value < $1.value }) else { return "mixed" }
            return Double(top.value) / Double(drinkCount) >= 0.6 ? top.key : "mixed"
        }()
        let nightOutcome: String = {
            if drinkCount == 0 { return "sober" }
            if let target = event.targetBAC { return peakBAC <= target ? "solid" : "heavy" }
            return peakBAC <= 0.06 ? "solid" : "heavy"
        }()

        let limit = 0.08
        let minutesAboveLimit = timeline.filter { $0.bac > limit }.count * 5
        let waterCount = eventWater.count
        let hydrationLevel = BACCalculator.hydrationLevel(waterEntries: eventWater, drinkCount: drinkCount)
        let cals = totalCalories(for: eventId)
        let lastDrinkTime = eventEntries.max(by: { $0.timestamp < $1.timestamp })?.timestamp ?? event.startTime
        let recoveryMinutes = Int(endTime.timeIntervalSince(lastDrinkTime) / 60)
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date(timeIntervalSinceNow: -(30 * 24 * 3600))
        let recentEvents = events.filter {
            $0.userId == currentUserId && $0.endTime != nil
            && $0.id != eventId && $0.startTime >= thirtyDaysAgo
        }
        let avgDrinksLast30Days: Double = recentEvents.isEmpty ? 0
            : Double(recentEvents.reduce(0) { $0 + totalDrinks(for: $1.id) }) / Double(recentEvents.count)
        let dayOfWeekFmt = DateFormatter(); dayOfWeekFmt.dateFormat = "EEEE"
        let dayOfWeek = dayOfWeekFmt.string(from: event.startTime)
        let currentYear = Calendar.current.component(.year, from: Date())

        var params: [String: Any] = [
            "eventId": eventId,
            "durationMinutes": durationMinutes,
            "drinks": drinkData,
            "peakBac": peakBAC,
            "peakBacTime": peakBacTime,
            "minutesAboveLimit": minutesAboveLimit,
            "waterCount": waterCount,
            "hydrationLevel": hydrationLevel.rawValue,
            "totalCalories": cals,
            "recoveryMinutes": recoveryMinutes,
            "userSex": userProfile.sex.rawValue,
            "userWeightKg": userProfile.weightKg,
            "avgDrinksLast30Days": avgDrinksLast30Days,
            "dayOfWeek": dayOfWeek,
            "stomachState": (event.stomachState ?? .empty).rawValue,
            "foodEntryCount": eventFoodEntries.count,
        ]
        if let name = event.name { params["eventName"] = name }
        if let birthYear = userProfile.birthYear { params["userAge"] = currentYear - birthYear }
        params["dominantDrinkType"] = dominantDrinkType
        params["nightOutcome"] = nightOutcome

        // Drinking pace — classified by drinks per hour, not sip duration
        let eventHours = max(0.01, (event.endTime ?? Date()).timeIntervalSince(event.startTime) / 3600)
        let dph        = Double(drinkCount) / eventHours
        let pace: String
        if dph > 2.0 { pace = "fast" } else if dph >= 1.0 { pace = "moderate" } else { pace = "slow" }
        params["drinksPerHour"] = round(dph * 10) / 10
        params["paceSummary"]   = pace

        let sipResults = drinkSipDurations(entries: eventEntries, drinkTypes: allDrinkTypes)
        if !sipResults.isEmpty {
            let totalSipMin = sipResults.reduce(0) { $0 + $1.sipMinutes }
            let avgSip      = Double(totalSipMin) / Double(sipResults.count)
            params["avgSipMinutes"] = Int(avgSip)
            if let f = sipResults.min(by: { $0.sipMinutes < $1.sipMinutes }) {
                params["fastestDrinkName"] = f.drinkType?.name ?? "Unknown"
            }
            if let s = sipResults.max(by: { $0.sipMinutes < $1.sipMinutes }) {
                params["slowestDrinkName"] = s.drinkType?.name ?? "Unknown"
            }
        }

        // Tonight's goal (targetBAC)
        if let target = event.targetBAC {
            params["targetBAC"] = target
            let overTarget = timeline.filter { $0.bac >= target }
            params["exceededTarget"]     = !overTarget.isEmpty
            params["minutesOverTarget"]  = overTarget.count * 5
        }

        let eventDisplayName = event.displayName
        generatingReportForEventId = eventId
        failedReportEventIds.remove(eventId)
        Task {
            defer { generatingReportForEventId = nil }
            do {
                try await FirebaseManager.shared.requestAiReport(eventId: eventId, data: params)
                var report: String?
                for _ in 0..<15 {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    report = await FirebaseManager.shared.fetchAiReport(eventId: eventId)
                    if report != nil { break }
                }
                guard let report else {
                    failedReportEventIds.insert(eventId)
                    return
                }
                if let idx = events.firstIndex(where: { $0.id == eventId }) {
                    events[idx].aiReport = report
                    DataStore.shared.updateEvent(events[idx])
                }
                incrementAiReportUsage()
                scheduleReportReadyNotification(eventName: eventDisplayName)
            } catch {
                failedReportEventIds.insert(eventId)
            }
        }
    }

    private func scheduleReportReadyNotification(eventName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Your night report is ready"
        content.body = "\(eventName) — tap to read your personalized health summary."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "siptrack.ai-report", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func scheduleCoachReportReminders() {
        let center = UNUserNotificationCenter.current()

        let weeklyContent = UNMutableNotificationContent()
        weeklyContent.title = "Weekly Report Ready"
        weeklyContent.body = "Your weekly health analysis is available in AI Coach."
        weeklyContent.sound = .default
        var weeklyComps = DateComponents()
        weeklyComps.weekday = 2
        weeklyComps.hour = 9
        weeklyComps.minute = 0
        let weeklyReq = UNNotificationRequest(
            identifier: "siptrack.coach-weekly-reminder",
            content: weeklyContent,
            trigger: UNCalendarNotificationTrigger(dateMatching: weeklyComps, repeats: true)
        )
        center.add(weeklyReq)

        let monthlyContent = UNMutableNotificationContent()
        monthlyContent.title = "Monthly Review Ready"
        monthlyContent.body = "Your monthly health review is available in AI Coach."
        monthlyContent.sound = .default
        var monthlyComps = DateComponents()
        monthlyComps.day = 1
        monthlyComps.hour = 9
        monthlyComps.minute = 30
        let monthlyReq = UNNotificationRequest(
            identifier: "siptrack.coach-monthly-reminder",
            content: monthlyContent,
            trigger: UNCalendarNotificationTrigger(dateMatching: monthlyComps, repeats: true)
        )
        center.add(monthlyReq)
    }

    private func scheduleCoachReportNotification(type: ReportType, periodLabel: String) {
        let content = UNMutableNotificationContent()
        switch type {
        case .weekly:
            content.title = "Weekly Report Ready"
            content.body = "\(periodLabel) — your AI health analysis is ready in Coach."
        case .monthly:
            content.title = "Monthly Review Ready"
            content.body = "\(periodLabel) — your monthly AI health review is ready."
        case .comparison:
            return
        }
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "siptrack.coach-\(UUID().uuidString)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Recovery Brief

    private func recoverySeverity(peakBAC: Double, hydration: BACCalculator.HydrationLevel) -> RecoverySeverity {
        if peakBAC >= 0.15 || (peakBAC >= 0.10 && hydration == .none) { return .rough }
        if peakBAC < 0.06 || (peakBAC < 0.08 && hydration == .great) { return .mild }
        return .moderate
    }

    func generateRecoveryBrief(for eventId: String) {
        guard currentUserId != nil else { return }
        guard !nightRecoveries.contains(where: { $0.id == eventId }) else { return }
        guard let event = events.first(where: { $0.id == eventId }),
              event.endTime != nil else { return }

        let evEntries = entries.filter { $0.eventId == eventId }
        guard !evEntries.isEmpty else { return }
        let evWater = waterEntries.filter { $0.eventId == eventId }

        let timeline = BACCalculator.bacTimeline(
            entries: evEntries, drinkTypes: allDrinkTypes,
            profile: userProfile, eventStart: event.startTime
        )
        let peakBAC = timeline.max(by: { $0.bac < $1.bac })?.bac ?? 0
        let drinkCount = evEntries.reduce(0) { $0 + $1.quantity }
        let hydration = BACCalculator.hydrationLevel(waterEntries: evWater, drinkCount: drinkCount)
        let severity = recoverySeverity(peakBAC: peakBAC, hydration: hydration)

        let drinkList = Dictionary(grouping: evEntries) { $0.drinkTypeId }
            .compactMap { typeId, es -> String? in
                guard let dt = allDrinkTypes.first(where: { $0.id == typeId }) else { return nil }
                return "\(es.reduce(0) { $0 + $1.quantity })x \(dt.name)"
            }.joined(separator: ", ")

        let placeholder = NightRecovery(id: eventId, severity: severity, report: nil, createdAt: Date())
        nightRecoveries.append(placeholder)
        DataStore.shared.saveNightRecoveries(nightRecoveries)

        scheduleRecoveryNotification(for: event)

        let currentYear = Calendar.current.component(.year, from: Date())
        var requestData: [String: Any] = [
            "userSex": userProfile.sex.rawValue,
            "userWeightKg": userProfile.weightKg,
            "drinkList": drinkList,
            "drinkCount": drinkCount,
            "peakBac": peakBAC,
            "waterCount": evWater.count,
            "hydrationLevel": hydration.rawValue,
            "severity": severity.rawValue,
        ]
        if let birthYear = userProfile.birthYear { requestData["userAge"] = currentYear - birthYear }

        Task {
            generatingRecoveryForEventId = eventId
            failedRecoveryEventIds.remove(eventId)
            defer { generatingRecoveryForEventId = nil }
            let payload: [String: Any] = [
                "status": "pending",
                "created_at": Date().timeIntervalSince1970 * 1000,
                "request_data": requestData
            ]
            do {
                try await FirebaseManager.shared.requestRecoveryBrief(eventId: eventId, data: payload)
                var report: String?
                for _ in 0..<15 {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    report = await FirebaseManager.shared.fetchRecoveryBrief(eventId: eventId)
                    if report != nil { break }
                }
                guard let report else {
                    failedRecoveryEventIds.insert(eventId)
                    return
                }
                if let idx = nightRecoveries.firstIndex(where: { $0.id == eventId }) {
                    nightRecoveries[idx].report = report
                    DataStore.shared.saveNightRecoveries(nightRecoveries)
                }
            } catch {
                failedRecoveryEventIds.insert(eventId)
            }
        }
    }

    func checkAndGenerateRecoveries() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let recent = events.filter {
            guard let end = $0.endTime else { return false }
            return end >= cutoff
        }
        for event in recent {
            if !nightRecoveries.contains(where: { $0.id == event.id }) {
                generateRecoveryBrief(for: event.id)
            }
        }
    }

    func syncPendingRecoveries() {
        let pending = nightRecoveries.filter { $0.report == nil }
        guard !pending.isEmpty else { return }
        Task {
            for r in pending {
                guard let report = await FirebaseManager.shared.fetchRecoveryBrief(
                    eventId: r.id
                ) else { continue }
                if let idx = nightRecoveries.firstIndex(where: { $0.id == r.id }) {
                    nightRecoveries[idx].report = report
                    DataStore.shared.saveNightRecoveries(nightRecoveries)
                }
            }
        }
    }

    private func scheduleRecoveryNotification(for event: NightEvent) {
        let cal = Calendar.current
        guard let tomorrow = cal.date(byAdding: .day, value: 1, to: event.startTime) else { return }
        var comps = cal.dateComponents([.year, .month, .day], from: tomorrow)
        comps.hour = 8; comps.minute = 0
        guard let fireDate = cal.date(from: comps), fireDate > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = "Recovery Brief Ready"
        content.body = "\(event.displayName) — your morning recovery guide is ready."
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let req = UNNotificationRequest(
            identifier: "siptrack.recovery-\(event.id)",
            content: content, trigger: trigger
        )
        UNUserNotificationCenter.current().add(req)
    }

    // MARK: - AI Coach

    func checkAndGenerateAutoReports() {
        guard currentUserId != nil else { return }
        let cal = Calendar(identifier: .iso8601)
        let now = Date()

        guard let prevWeekDate = cal.date(byAdding: .weekOfYear, value: -1, to: now) else { return }
        let weekId = weeklyReportId(for: prevWeekDate)
        if !coachReports.contains(where: { $0.id == weekId }) {
            guard let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: prevWeekDate)),
                  let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart) else { return }
            let hasNights = events.contains { $0.endTime != nil && $0.startTime >= weekStart && $0.startTime < weekEnd }
            if hasNights { generateWeeklyReport(for: prevWeekDate) }
        }

        guard let prevMonth = cal.date(byAdding: .month, value: -1, to: now) else { return }
        let y = cal.component(.year, from: prevMonth)
        let m = cal.component(.month, from: prevMonth)
        let monthId = "monthly-\(y)-\(String(format: "%02d", m))"
        if !coachReports.contains(where: { $0.id == monthId }) {
            let comps = DateComponents(year: y, month: m, day: 1)
            guard let monthStart = cal.date(from: comps),
                  let monthEnd = cal.date(byAdding: .month, value: 1, to: monthStart) else { return }
            let hasNights  = events.contains { $0.endTime != nil && $0.startTime >= monthStart && $0.startTime < monthEnd }
            if hasNights { generateMonthlyReport(year: y, month: m) }
        }
    }

    private func weeklyReportId(for date: Date) -> String {
        let cal = Calendar(identifier: .iso8601)
        let year = cal.component(.yearForWeekOfYear, from: date)
        let week = cal.component(.weekOfYear, from: date)
        return "weekly-\(year)-W\(String(format: "%02d", week))"
    }

    private func generateWeeklyReport(for refDate: Date = Date()) {
        guard currentUserId != nil else { return }
        let cal = Calendar(identifier: .iso8601)
        let now = Date()
        guard let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: refDate)),
              let weekEnd   = cal.date(byAdding: .day, value: 7, to: weekStart) else { return }
        let reportId  = weeklyReportId(for: refDate)

        guard !coachReports.contains(where: { $0.id == reportId }) else { return }

        let data = buildWeeklyData(from: weekStart, to: weekEnd)
        guard !data.isEmpty else { return }

        let fmt = DateFormatter(); fmt.dateStyle = .medium; fmt.timeStyle = .none
        let placeholder = CoachReport(
            id: reportId, type: .weekly,
            periodStart: weekStart, periodEnd: weekEnd,
            report: nil, createdAt: now
        )
        coachReports.append(placeholder)

        Task {
            generatingCoachReportId = reportId
            failedCoachReportIds.remove(reportId)
            defer { generatingCoachReportId = nil }
            var payload: [String: Any] = [
                "type": "weekly",
                "period_start": weekStart.timeIntervalSince1970 * 1000,
                "period_end":   weekEnd.timeIntervalSince1970 * 1000,
                "created_at":   now.timeIntervalSince1970 * 1000,
                "status": "pending",
                "request_data": data
            ]
            payload["week_start_label"] = fmt.string(from: weekStart)
            payload["week_end_label"]   = fmt.string(from: weekEnd)
            do {
                try await FirebaseManager.shared.requestCoachReport(reportId: reportId, data: payload)
                let report = await pollCoachReport(id: reportId)
                if let report, let idx = coachReports.firstIndex(where: { $0.id == reportId }) {
                    coachReports[idx].report = report
                    DataStore.shared.saveCoachReports(coachReports)
                    let label = payload["week_start_label"] as? String ?? "this week"
                    scheduleCoachReportNotification(type: .weekly, periodLabel: label)
                } else {
                    failedCoachReportIds.insert(reportId)
                }
            } catch {
                failedCoachReportIds.insert(reportId)
            }
        }
    }

    private func generateMonthlyReport(year: Int? = nil, month: Int? = nil) {
        guard currentUserId != nil else { return }
        let cal = Calendar(identifier: .iso8601)
        let now = Date()
        guard let prevMonth = cal.date(byAdding: .month, value: -1, to: now) else { return }
        let y = year  ?? cal.component(.year,  from: prevMonth)
        let m = month ?? cal.component(.month, from: prevMonth)
        let reportId = "monthly-\(y)-\(String(format: "%02d", m))"

        guard !coachReports.contains(where: { $0.id == reportId }) else { return }

        let comps = DateComponents(year: y, month: m, day: 1)
        guard let monthStart = cal.date(from: comps),
              let monthEnd   = cal.date(byAdding: .month, value: 1, to: monthStart) else { return }

        let data = buildMonthlyData(from: monthStart, to: monthEnd)
        guard !data.isEmpty else { return }

        let placeholder = CoachReport(
            id: reportId, type: .monthly,
            periodStart: monthStart, periodEnd: monthEnd,
            report: nil, createdAt: now
        )
        coachReports.append(placeholder)

        Task {
            generatingCoachReportId = reportId
            failedCoachReportIds.remove(reportId)
            defer { generatingCoachReportId = nil }
            let payload: [String: Any] = [
                "type": "monthly",
                "period_start": monthStart.timeIntervalSince1970 * 1000,
                "period_end":   monthEnd.timeIntervalSince1970 * 1000,
                "created_at":   now.timeIntervalSince1970 * 1000,
                "status": "pending",
                "request_data": data
            ]
            do {
                try await FirebaseManager.shared.requestCoachReport(reportId: reportId, data: payload)
                let report = await pollCoachReport(id: reportId)
                if let report, let idx = coachReports.firstIndex(where: { $0.id == reportId }) {
                    coachReports[idx].report = report
                    DataStore.shared.saveCoachReports(coachReports)
                    let fmt = DateFormatter(); fmt.dateFormat = "MMMM yyyy"
                    let label = fmt.string(from: monthStart)
                    scheduleCoachReportNotification(type: .monthly, periodLabel: label)
                } else {
                    failedCoachReportIds.insert(reportId)
                }
            } catch {
                failedCoachReportIds.insert(reportId)
            }
        }
    }

    func generateComparisonReport(eventA: NightEvent, eventB: NightEvent) {
        guard currentUserId != nil else { return }
        let now = Date()
        let reportId = "comparison-\(eventA.id)-\(eventB.id)"

        if coachReports.contains(where: { $0.id == reportId }) { return }

        let aData = buildEventSummaryData(event: eventA)
        let bData = buildEventSummaryData(event: eventB)
        guard !aData.isEmpty, !bData.isEmpty else { return }

        let currentYear = Calendar.current.component(.year, from: now)
        var userData: [String: Any] = [
            "userSex": userProfile.sex.rawValue,
            "userWeightKg": userProfile.weightKg,
        ]
        if let birthYear = userProfile.birthYear { userData["userAge"] = currentYear - birthYear }

        let placeholder = CoachReport(
            id: reportId, type: .comparison,
            periodStart: min(eventA.startTime, eventB.startTime),
            periodEnd: max(eventA.endTime ?? eventA.startTime, eventB.endTime ?? eventB.startTime),
            report: nil, createdAt: now,
            eventAId: eventA.id, eventBId: eventB.id
        )
        coachReports.append(placeholder)

        Task {
            generatingCoachReportId = reportId
            failedCoachReportIds.remove(reportId)
            defer { generatingCoachReportId = nil }
            var requestData = userData
            requestData["eventA"] = aData
            requestData["eventB"] = bData
            let payload: [String: Any] = [
                "type": "comparison",
                "period_start": placeholder.periodStart.timeIntervalSince1970 * 1000,
                "period_end":   placeholder.periodEnd.timeIntervalSince1970 * 1000,
                "created_at":   now.timeIntervalSince1970 * 1000,
                "event_a_id": eventA.id,
                "event_b_id": eventB.id,
                "status": "pending",
                "request_data": requestData
            ]
            do {
                try await FirebaseManager.shared.requestCoachReport(reportId: reportId, data: payload)
                let report = await pollCoachReport(id: reportId)
                if let report, let idx = coachReports.firstIndex(where: { $0.id == reportId }) {
                    coachReports[idx].report = report
                    DataStore.shared.saveCoachReports(coachReports)
                } else {
                    failedCoachReportIds.insert(reportId)
                }
            } catch {
                failedCoachReportIds.insert(reportId)
            }
        }
    }

    func retryNightReport(eventId: String) {
        failedReportEventIds.remove(eventId)
        generateAiReport(for: eventId)
    }

    func retryRecoveryBrief(eventId: String) {
        failedRecoveryEventIds.remove(eventId)
        generateRecoveryBrief(for: eventId)
    }

    func retryCoachReport(id: String) {
        guard let report = coachReports.first(where: { $0.id == id }) else { return }
        coachReports.removeAll { $0.id == id }
        failedCoachReportIds.remove(id)
        switch report.type {
        case .weekly:
            generateWeeklyReport(for: report.periodStart)
        case .monthly:
            let cal = Calendar(identifier: .iso8601)
            let y = cal.component(.year,  from: report.periodStart)
            let m = cal.component(.month, from: report.periodStart)
            generateMonthlyReport(year: y, month: m)
        case .comparison:
            guard let aId = report.eventAId, let bId = report.eventBId,
                  let eventA = events.first(where: { $0.id == aId }),
                  let eventB = events.first(where: { $0.id == bId }) else { return }
            generateComparisonReport(eventA: eventA, eventB: eventB)
        }
    }

    private func pollCoachReport(id: String) async -> String? {
        for _ in 0..<15 {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if let report = await FirebaseManager.shared.fetchCoachReport(reportId: id) {
                return report
            }
        }
        print("❌ Coach report timeout: \(id)")
        return nil
    }

    private func buildWeeklyData(from weekStart: Date, to weekEnd: Date) -> [String: Any] {
        let cal = Calendar(identifier: .iso8601)
        let now = Date()
        let weekNights = events.filter {
            $0.endTime != nil && $0.userId == currentUserId
            && $0.startTime >= weekStart && $0.startTime < weekEnd
        }
        guard !weekNights.isEmpty else { return [:] }

        var weekTotalDrinks = 0; var totalCals = 0.0; var totalWater = 0
        var peakBac = 0.0; var peakBacNight = ""
        var bacValues: [Double] = []
        var bestNight = ""; var worstNight = ""; var bestCount = Int.max; var worstCount = 0
        var drivingNights = 0; var drivingExceeded = 0
        var bestHydrationNight = ""; var bestHydrationCount = 0 // one WaterEntry == one logged glass
        var bestBACNight = ""; var bestBACValue = Double.infinity

        for event in weekNights {
            let evEntries = entries.filter { $0.eventId == event.id }
            let evWater   = waterEntries.filter { $0.eventId == event.id }
            let drinkCount = evEntries.reduce(0) { $0 + $1.quantity }
            weekTotalDrinks += drinkCount
            totalCals   += totalCalories(for: event.id)
            totalWater  += evWater.count

            let timeline = BACCalculator.bacTimeline(
                entries: evEntries,
                drinkTypes: allDrinkTypes,
                profile: userProfile,
                eventStart: event.startTime
            )
            let nightPeak = timeline.max(by: { $0.bac < $1.bac })?.bac ?? 0
            bacValues.append(nightPeak)
            if nightPeak > peakBac { peakBac = nightPeak; peakBacNight = event.displayName }

            if drinkCount < bestCount  { bestCount = drinkCount;  bestNight  = event.displayName }
            if drinkCount > worstCount { worstCount = drinkCount; worstNight = event.displayName }

            if evWater.count > bestHydrationCount {
                bestHydrationCount = evWater.count
                bestHydrationNight = event.displayName
            }
            if nightPeak > 0 && nightPeak < bestBACValue {
                bestBACValue = nightPeak
                bestBACNight = event.displayName
            }

            if event.drivingMode {
                drivingNights += 1
                if nightPeak > (event.bacLimit ?? 0.08) { drivingExceeded += 1 }
            }
        }

        let bestBehaviorType: String
        let bestBehaviorNight: String
        let bestBehaviorDetail: String
        if bestHydrationCount >= 2 {
            bestBehaviorType = "hydration"
            bestBehaviorNight = bestHydrationNight
            bestBehaviorDetail = "\(bestHydrationCount) glasses of water"
        } else if !bestBACNight.isEmpty {
            bestBehaviorType = "pace"
            bestBehaviorNight = bestBACNight
            bestBehaviorDetail = String(format: "%.3f peak BAC", bestBACValue)
        } else {
            bestBehaviorType = "none"
            bestBehaviorNight = ""
            bestBehaviorDetail = ""
        }

        let avgBac = bacValues.isEmpty ? 0.0 : bacValues.reduce(0, +) / Double(bacValues.count)
        let thirtyDaysAgo = cal.date(byAdding: .day, value: -30, to: now) ?? Date(timeIntervalSinceNow: -(30 * 24 * 3600))
        let recentEvents = events.filter {
            $0.userId == currentUserId && $0.endTime != nil && $0.startTime >= thirtyDaysAgo
        }
        let avg30 = recentEvents.isEmpty ? 0.0
            : Double(recentEvents.reduce(0) { $0 + totalDrinks(for: $1.id) }) / Double(recentEvents.count)

        let dateFmt = DateFormatter(); dateFmt.dateFormat = "MMM d"
        let currentYear = cal.component(.year, from: now)

        let weekEntries = weekNights.flatMap { event in entries.filter { $0.eventId == event.id } }
        var drinkByType: [String: Int] = [:]
        for entry in weekEntries {
            let name = allDrinkTypes.first { $0.id == entry.drinkTypeId }?.name ?? "Other"
            drinkByType[name, default: 0] += entry.quantity
        }
        let drinkBreakdown = drinkByType.sorted { $0.value > $1.value }.map { "\($0.value)x \($0.key)" }.joined(separator: ", ")

        var d: [String: Any] = [
            "userSex": userProfile.sex.rawValue,
            "userWeightKg": userProfile.weightKg,
            "weekStart": dateFmt.string(from: weekStart),
            "weekEnd":   dateFmt.string(from: cal.date(byAdding: .day, value: -1, to: weekEnd) ?? weekEnd),
            "nightCount": weekNights.count,
            "totalDrinks": weekTotalDrinks,
            "totalStdDrinks": weekTotalDrinks,
            "totalCalories": totalCals,
            "peakBac": peakBac,
            "peakBacNight": peakBacNight,
            "avgBacPerNight": avgBac,
            "totalWater": totalWater,
            "avg30DayDrinksPerNight": avg30,
            "bestNight": bestNight,
            "worstNight": worstNight,
            "bestBehaviorType": bestBehaviorType,
            "bestBehaviorNight": bestBehaviorNight,
            "bestBehaviorDetail": bestBehaviorDetail,
            "drinkBreakdown": drinkBreakdown,
            "drivingNights": drivingNights,
            "drivingExceededBACLimit": drivingExceeded,
        ]
        if let birthYear = userProfile.birthYear { d["userAge"] = currentYear - birthYear }
        if let h = userProfile.heightCm {
            d["userHeightCm"] = h
            d["userBMI"] = String(format: "%.1f", userProfile.weightKg / ((h / 100) * (h / 100)))
        }
        return d
    }

    private func buildMonthlyData(from monthStart: Date, to monthEnd: Date) -> [String: Any] {
        let cal = Calendar.current
        let monthNights = events.filter {
            $0.endTime != nil && $0.userId == currentUserId
            && $0.startTime >= monthStart && $0.startTime < monthEnd
        }
        guard !monthNights.isEmpty else { return [:] }

        var monthTotalDrinks = 0; var totalCals = 0.0; var totalWater = 0
        var peakBac = 0.0; var peakBacNight = ""
        var bacValues: [Double] = []
        var nightDates = Set<Int>()
        var drivingNights = 0; var drivingExceeded = 0
        var bestMonthBACNight = ""; var bestMonthBACValue = Double.infinity
        var frontLoadedNights = 0; var lateDrinkNights = 0; var mixingNights = 0

        for event in monthNights {
            let evEntries = entries.filter { $0.eventId == event.id }
            let evWater   = waterEntries.filter { $0.eventId == event.id }
            let drinkCount = evEntries.reduce(0) { $0 + $1.quantity }
            monthTotalDrinks += drinkCount
            totalCals   += totalCalories(for: event.id)
            totalWater  += evWater.count
            nightDates.insert(cal.ordinality(of: .day, in: .era, for: event.startTime) ?? 0)

            let timeline = BACCalculator.bacTimeline(
                entries: evEntries,
                drinkTypes: allDrinkTypes,
                profile: userProfile,
                eventStart: event.startTime
            )
            let nightPeak = timeline.max(by: { $0.bac < $1.bac })?.bac ?? 0
            bacValues.append(nightPeak)
            if nightPeak > peakBac { peakBac = nightPeak; peakBacNight = event.displayName }

            // Best night (lowest non-zero peak BAC)
            if nightPeak > 0 && nightPeak < bestMonthBACValue {
                bestMonthBACValue = nightPeak
                bestMonthBACNight = event.displayName
            }

            // Front-loading detection (>60% of drinks in first half of night)
            if let evEnd = event.endTime {
                let duration = evEnd.timeIntervalSince(event.startTime)
                if duration > 0 {
                    let midPoint = event.startTime.addingTimeInterval(duration / 2)
                    let firstHalf = evEntries.filter { $0.timestamp <= midPoint }
                        .reduce(0) { $0 + $1.quantity }
                    if drinkCount > 0 && Double(firstHalf) / Double(drinkCount) > 0.6 {
                        frontLoadedNights += 1
                    }
                }
            }

            // Late drinker detection (last drink between midnight and 5am)
            if let lastEntry = evEntries.max(by: { $0.timestamp < $1.timestamp }) {
                let hour = Calendar.current.component(.hour, from: lastEntry.timestamp)
                if hour < 5 { lateDrinkNights += 1 }
            }

            // Mixing detection (beer/wine AND spirits/agave in same night)
            var hasBeerWine = false; var hasSpirits = false
            for entry in evEntries {
                if let dt = allDrinkTypes.first(where: { $0.id == entry.drinkTypeId }) {
                    let cat = dt.drinkCategory
                    if cat == "beer" || cat == "wine" { hasBeerWine = true }
                    if cat == "spirits" || cat == "agave" { hasSpirits = true }
                }
            }
            if hasBeerWine && hasSpirits { mixingNights += 1 }

            if event.drivingMode {
                drivingNights += 1
                if nightPeak > (event.bacLimit ?? 0.08) { drivingExceeded += 1 }
            }
        }

        let nightCountM = monthNights.count
        let signatureMove: String
        if frontLoadedNights > nightCountM / 2 { signatureMove = "front_loads" }
        else if lateDrinkNights > nightCountM / 2 { signatureMove = "late_drinker" }
        else if mixingNights > nightCountM / 2 { signatureMove = "mixes_drinks" }
        else { signatureMove = "none" }

        let daysInMonth = cal.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        let soberDays = daysInMonth - nightDates.count
        let avgBac = bacValues.isEmpty ? 0.0 : bacValues.reduce(0, +) / Double(bacValues.count)

        var weekBreakdowns: [[String: Any]] = []
        var weekStart = monthStart
        while weekStart < monthEnd {
            let weekEnd = min(cal.date(byAdding: .day, value: 7, to: weekStart) ?? monthEnd, monthEnd)
            let wNights = monthNights.filter { $0.startTime >= weekStart && $0.startTime < weekEnd }
            let wDrinks = wNights.reduce(0) { $0 + totalDrinks(for: $1.id) }
            let wPeakBac = wNights.reduce(0.0) { (acc, event) -> Double in
                let evEntries = entries.filter { $0.eventId == event.id }
                let timeline = BACCalculator.bacTimeline(
                    entries: evEntries, drinkTypes: allDrinkTypes,
                    profile: userProfile, eventStart: event.startTime
                )
                return max(acc, timeline.max(by: { $0.bac < $1.bac })?.bac ?? 0)
            }
            weekBreakdowns.append(["nights": wNights.count, "drinks": wDrinks, "peakBac": wPeakBac])
            weekStart = weekEnd
        }

        let prevMonthStart = cal.date(byAdding: .month, value: -1, to: monthStart) ?? monthStart
        let prevMonthNightCount = events.filter {
            $0.endTime != nil && $0.userId == currentUserId
            && $0.startTime >= prevMonthStart && $0.startTime < monthStart
        }.count

        let monthFmt = DateFormatter(); monthFmt.dateFormat = "MMMM"
        let yearFmt  = DateFormatter(); yearFmt.dateFormat  = "yyyy"
        let currentYear = cal.component(.year, from: Date())

        let monthEntries = monthNights.flatMap { event in entries.filter { $0.eventId == event.id } }
        var drinkByType: [String: Int] = [:]
        for entry in monthEntries {
            let name = allDrinkTypes.first { $0.id == entry.drinkTypeId }?.name ?? "Other"
            drinkByType[name, default: 0] += entry.quantity
        }
        let drinkBreakdown = drinkByType.sorted { $0.value > $1.value }.map { "\($0.value)x \($0.key)" }.joined(separator: ", ")

        var d: [String: Any] = [
            "userSex": userProfile.sex.rawValue,
            "userWeightKg": userProfile.weightKg,
            "monthName": monthFmt.string(from: monthStart),
            "year": yearFmt.string(from: monthStart),
            "nightCount": monthNights.count,
            "totalDrinks": monthTotalDrinks,
            "totalStdDrinks": monthTotalDrinks,
            "totalCalories": totalCals,
            "peakBac": peakBac,
            "peakBacNight": peakBacNight,
            "avgBacPerNight": avgBac,
            "totalWater": totalWater,
            "soberDays": soberDays,
            "prevMonthNightCount": prevMonthNightCount,
            "weekBreakdowns": weekBreakdowns,
            "drinkBreakdown": drinkBreakdown,
            "signatureMove": signatureMove,
            "bestMonthNight": bestMonthBACNight,
            "drivingNights": drivingNights,
            "drivingExceededBACLimit": drivingExceeded,
        ]
        if let birthYear = userProfile.birthYear { d["userAge"] = currentYear - birthYear }
        if let h = userProfile.heightCm {
            d["userHeightCm"] = h
            d["userBMI"] = String(format: "%.1f", userProfile.weightKg / ((h / 100) * (h / 100)))
        }
        return d
    }

    private func buildEventSummaryData(event: NightEvent) -> [String: Any] {
        guard let endTime = event.endTime else { return [:] }
        let evEntries = entries.filter { $0.eventId == event.id }
        guard !evEntries.isEmpty else { return [:] }
        let evWater = waterEntries.filter { $0.eventId == event.id }

        let timeline = BACCalculator.bacTimeline(
            entries: evEntries, drinkTypes: allDrinkTypes,
            profile: userProfile, eventStart: event.startTime
        )
        let peakPoint  = timeline.max(by: { $0.bac < $1.bac })
        let peakBAC    = peakPoint?.bac ?? 0
        let peakBacTime: String = {
            guard let date = peakPoint?.date else { return "" }
            let f = DateFormatter(); f.timeStyle = .short
            return f.string(from: date)
        }()
        let durationMinutes = Int(event.duration / 60)
        let drinkCount = evEntries.reduce(0) { $0 + $1.quantity }
        let drinkList = Dictionary(grouping: evEntries) { $0.drinkTypeId }
            .compactMap { typeId, es -> String? in
                guard let dt = allDrinkTypes.first(where: { $0.id == typeId }) else { return nil }
                return "\(es.reduce(0) { $0 + $1.quantity })x \(dt.name)"
            }.joined(separator: ", ")
        let drinksPerHour = durationMinutes > 0
            ? String(format: "%.1f", Double(drinkCount) / (Double(durationMinutes) / 60))
            : "0"
        let minutesAboveLimit = timeline.filter { $0.bac > 0.08 }.count * 5
        let waterCount = evWater.count
        let hydrationLevel = BACCalculator.hydrationLevel(waterEntries: evWater, drinkCount: drinkCount)
        let cals = totalCalories(for: event.id)
        let lastDrinkTime = evEntries.max(by: { $0.timestamp < $1.timestamp })?.timestamp ?? event.startTime
        let recoveryMinutes = Int(endTime.timeIntervalSince(lastDrinkTime) / 60)

        var result: [String: Any] = [
            "name": event.displayName,
            "durationMinutes": durationMinutes,
            "drinkList": drinkList,
            "drinksPerHour": drinksPerHour,
            "peakBac": peakBAC,
            "peakBacTime": peakBacTime,
            "minutesAboveLimit": minutesAboveLimit,
            "waterCount": waterCount,
            "hydrationLevel": hydrationLevel.rawValue,
            "totalCalories": cals,
            "recoveryMinutes": recoveryMinutes,
        ]
        if event.drivingMode {
            result["drivingMode"] = true
            result["drivedAboveLimit"] = peakBAC > (event.bacLimit ?? 0.08)
        }
        return result
    }

    func deleteCoachReport(id: String) {
        coachReports.removeAll { $0.id == id }
        DataStore.shared.saveCoachReports(coachReports)
        push { try await FirebaseManager.shared.deleteCoachReport(reportId: id) }
    }

    func cancelCoachReport(id: String) {
        coachReports.removeAll { $0.id == id }
        DataStore.shared.saveCoachReports(coachReports)
        if generatingCoachReportId == id { generatingCoachReportId = nil }
    }

    #if DEBUG
    func generateTestWeeklyReport() {
        let cal = Calendar(identifier: .iso8601)
        generateWeeklyReport(for: cal.date(byAdding: .day, value: -1, to: Date()) ?? Date())
    }

    func generateTestMonthlyReport() {
        let cal = Calendar.current
        let now = Date()
        let y = cal.component(.year, from: now)
        let m = cal.component(.month, from: now)
        generateMonthlyReport(year: y, month: m)
    }
    #endif

    func updateEventNotes(id: String, notes: String) {
        updateEvent(id: id) { $0.notes = notes }
    }

    func deleteEvent(_ id: String) {
        DataStore.shared.deleteEvent(id)
        events.removeAll { $0.id == id }
        entries.removeAll { $0.eventId == id }
        waterEntries.removeAll { $0.eventId == id }
        foodEntries.removeAll { $0.eventId == id }
        push { try await FirebaseManager.shared.deleteEvent(id) }
    }

    private func updateEvent(id: String, mutate: (inout NightEvent) -> Void) {
        guard let idx = events.firstIndex(where: { $0.id == id }) else { return }
        mutate(&events[idx])
        DataStore.shared.updateEvent(events[idx])
        let updated = events[idx]
        push { try await FirebaseManager.shared.pushEvent(updated) }
    }

    // MARK: - Entries

    func addDrink(
        eventId: String,
        drinkTypeId: String,
        quantity: Int = 1,
        comment: String? = nil,
        volumeOverride: Double? = nil,
        abvOverride: Double? = nil
    ) {
        let entry = DrinkEntry(
            id: generateId(),
            eventId: eventId,
            drinkTypeId: drinkTypeId,
            timestamp: Date(),
            quantity: quantity,
            comment: comment,
            volumeOverrideMl: volumeOverride,
            abvOverride: abvOverride
        )
        DataStore.shared.addEntry(entry)
        entries.append(entry)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        scheduleUndo(entry)
        checkWarnings(after: entry, eventId: eventId)
        updateLiveActivity(for: eventId)
        push { try await FirebaseManager.shared.pushEntry(entry) }
        WatchBridge.shared.pushState()
    }

    func updateEntry(_ entry: DrinkEntry) {
        DataStore.shared.updateEntry(entry)
        if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[idx] = entry
        }
        push { try await FirebaseManager.shared.pushEntry(entry) }
    }

    func deleteEntry(_ id: String) {
        DataStore.shared.deleteEntry(id)
        entries.removeAll { $0.id == id }
        push { try await FirebaseManager.shared.deleteEntry(id) }
    }

    func undoLastEntry() {
        undoTask?.cancel()
        undoTask = nil
        if let e = undoEntry {
            deleteEntry(e.id)
            undoEntry = nil
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func scheduleUndo(_ entry: DrinkEntry) {
        undoTask?.cancel()
        undoEntry = entry
        undoTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            undoEntry = nil
        }
    }

    // MARK: - Water

    func addWater(eventId: String, volumeMl: Double = 250) {
        let entry = WaterEntry(id: generateId(), eventId: eventId, timestamp: Date(), volumeMl: volumeMl)
        DataStore.shared.addWaterEntry(entry)
        waterEntries.append(entry)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        scheduleUndoWater(entry)
        if activeEvent?.id == eventId {
            WaterReminderManager.shared.schedule(intervalMinutes: userProfile.waterReminderIntervalMinutes)
        }
    }

    func undoLastWaterEntry() {
        undoWaterTask?.cancel()
        undoWaterTask = nil
        if let e = undoWaterEntry {
            deleteWaterEntry(e.id)
            undoWaterEntry = nil
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func scheduleUndoWater(_ entry: WaterEntry) {
        undoWaterTask?.cancel()
        undoWaterEntry = entry
        undoWaterTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            undoWaterEntry = nil
        }
    }

    func deleteWaterEntry(_ id: String) {
        DataStore.shared.deleteWaterEntry(id)
        waterEntries.removeAll { $0.id == id }
    }

    // MARK: - Food

    func addFoodEntry(eventId: String, type: StomachState) {
        let entry = FoodEntry(id: generateId(), eventId: eventId, type: type, timestamp: Date())
        DataStore.shared.addFoodEntry(entry)
        foodEntries.append(entry)
    }

    func deleteFoodEntry(_ id: String) {
        DataStore.shared.deleteFoodEntry(id)
        foodEntries.removeAll { $0.id == id }
    }

    func foodList(for eventId: String) -> [FoodEntry] {
        foodEntries.filter { $0.eventId == eventId }
    }

    // MARK: - Drink Types

    func saveDrinkType(_ type: DrinkType) {
        var types = customDrinkTypes
        if let idx = types.firstIndex(where: { $0.id == type.id }) {
            types[idx] = type
        } else {
            types.append(type)
        }
        customDrinkTypes = types
        DataStore.shared.saveCustomDrinkTypes(types)
        push { try await FirebaseManager.shared.pushDrinkType(type) }
    }

    func deleteDrinkType(_ id: String) {
        customDrinkTypes.removeAll { $0.id == id }
        DataStore.shared.saveCustomDrinkTypes(customDrinkTypes)
        push { try await FirebaseManager.shared.deleteDrinkType(id) }
    }

    // MARK: - Profile

    func updateUserProfile(_ profile: UserProfile) {
        userProfile = profile
        DataStore.shared.saveUserProfile(profile)
        push { try await FirebaseManager.shared.pushProfile(profile) }
        if activeEvent != nil {
            WaterReminderManager.shared.schedule(intervalMinutes: profile.waterReminderIntervalMinutes)
        }
    }

    // MARK: - Country detection
    //
    // Detection runs on every cold start (post-onboarding). The location is
    // taken once, reverse-geocoded, then discarded. The sheet only surfaces
    // when the detected country differs from BOTH the stored country and the
    // last country the user explicitly dismissed — so travellers get prompted
    // each time they cross a border, but repeat sessions in the same place
    // don't nag.

    var shouldAttemptCountryDetection: Bool {
        let p = userProfile
        guard p.onboardingComplete else { return false }
        guard currentUserId != nil else { return false }
        if p.countryDetectionDisabled { return false }
        return true
    }

    // Whether to actually present the sheet for this detection result. Hides
    // when detected == stored country, or detected == last-dismissed country.
    func shouldPromptForDetectedCountry(_ code: String) -> Bool {
        let p = userProfile
        if p.countryDetectionDisabled { return false }
        if code == p.countryCode { return false }
        if let dismissed = p.countryDetectionLastDismissedCode, code == dismissed {
            return false
        }
        return true
    }

    func applyDetectedCountry(_ country: LegalBACLimit) {
        var p = userProfile
        p.countryCode = country.countryCode
        p.bacLimit = country.limit(for: p.driverType)
        p.countryDetectionLastDismissedCode = nil
        updateUserProfile(p)
    }

    // User tapped "Keep mine" / "Got it" — remember the detected country so
    // we don't re-prompt for the same one. Next time the detector reports a
    // *different* country, the sheet shows again.
    func dismissDetectedCountry(_ code: String) {
        var p = userProfile
        p.countryDetectionLastDismissedCode = code
        updateUserProfile(p)
    }

    func disableCountryDetection() {
        var p = userProfile
        p.countryDetectionDisabled = true
        updateUserProfile(p)
    }

    // MARK: - Challenges

    func addChallenge(_ challenge: Challenge) {
        challenges.append(challenge)
        DataStore.shared.saveChallenges(challenges)
        push { try await FirebaseManager.shared.pushChallenge(challenge) }
    }

    func updateChallenge(_ challenge: Challenge) {
        if let idx = challenges.firstIndex(where: { $0.id == challenge.id }) {
            challenges[idx] = challenge
        }
        DataStore.shared.saveChallenges(challenges)
        push { try await FirebaseManager.shared.pushChallenge(challenge) }
    }

    func deleteChallenge(_ id: String) {
        challenges.removeAll { $0.id == id }
        DataStore.shared.saveChallenges(challenges)
        push { try await FirebaseManager.shared.deleteChallenge(id) }
    }

    // MARK: - Warnings

    private func checkWarnings(after entry: DrinkEntry, eventId: String) {
        guard userProfile.notifications.enabled else { return }
        guard let event = events.first(where: { $0.id == eventId }) else { return }

        let eventEntries = entries.filter { $0.eventId == eventId }
        let eventWater   = waterEntries.filter { $0.eventId == eventId }
        let bac = BACCalculator.currentBAC(
            entries: eventEntries,
            waterEntries: eventWater,
            drinkTypes: allDrinkTypes,
            profile: userProfile,
            eventStart: event.startTime
        )
        let prevEntries = eventEntries.dropLast()
        let prevBAC = BACCalculator.currentBAC(
            entries: Array(prevEntries),
            waterEntries: eventWater,
            drinkTypes: allDrinkTypes,
            profile: userProfile,
            eventStart: event.startTime
        )

        let calories = eventEntries.reduce(0.0) { sum, e in
            let dt = allDrinkTypes.first { $0.id == e.drinkTypeId }
            return sum + (dt?.caloriesPerServing ?? 0) * Double(e.quantity)
        }

        let ctx = WarningContext(
            currentBAC: bac,
            previousBAC: prevBAC,
            drivingMode: event.drivingMode,
            bacLimit: event.bacLimit ?? userProfile.resolvedBACLimit,
            drinksLastHour: BACCalculator.drinksInLastHour(entries: eventEntries),
            totalCalories: calories,
            previousStage: IntoxicationStage.stage(for: prevBAC),
            currentStage: IntoxicationStage.stage(for: bac),
            prefs: userProfile.notifications,
            eliminationRate: BACCalculator.eliminationRate(profile: userProfile)
        )
        let warnings = buildWarnings(context: ctx)
        if !warnings.isEmpty {
            activeWarnings = warnings
        }

        let hydration = BACCalculator.hydrationLevel(waterEntries: eventWater, drinkCount: eventEntries.count)
        if hydration == .behind && userProfile.waterSuggestions {
            showWaterNudge = true
        }
    }

    func dismissWarnings() { activeWarnings = [] }
    func dismissWaterNudge() { showWaterNudge = false }

    // MARK: - Subscription sync

    func syncSubscriptionFromStore() {
        // Only upgrade the profile when StoreKit confirms pro. Never downgrade from a
        // StoreKit timeout — userProfile.isPro acts as the persistent cache so pro status
        // survives cold launches where currentEntitlements is slow.
        guard store.isPro else { return }
        var profile = userProfile
        let wasPro = profile.isPro
        profile.subscriptionTier = .pro
        if let period = store.activePeriod {
            profile.subscriptionPeriod = period
        }
        if !wasPro {
            profile.subscriptionStartedAt = Date()
        }
        updateUserProfile(profile)
    }

    // MARK: - Push helper

    private func push(_ operation: @escaping () async throws -> Void) {
        Task {
            let ok = await FirebaseManager.shared.attempt(operation)
            if !ok { syncFailed = true }
        }
    }

    func retrySync() {
        syncFailed = false
        Task {
            let data = await FirebaseManager.shared.pullUserData()
            applyCloudData(data)
            var failed = false
            let fb = FirebaseManager.shared
            for event in events        { if await !fb.attempt({ try await fb.pushEvent(event) })      { failed = true } }
            for entry in entries       { if await !fb.attempt({ try await fb.pushEntry(entry) })      { failed = true } }
            for dt in customDrinkTypes { if await !fb.attempt({ try await fb.pushDrinkType(dt) })    { failed = true } }
            for ch in challenges       { if await !fb.attempt({ try await fb.pushChallenge(ch) })    { failed = true } }
            let profile = userProfile
            if await !fb.attempt({ try await fb.pushProfile(profile) }) { failed = true }
            if failed { syncFailed = true }
        }
    }

    // MARK: - Cloud sync

    // Called after sign-in: merges cloud data into local storage without wiping local records.
    func applyCloudData(_ data: FirebaseManager.PulledData) {
        let localEventIds = Set(events.map { $0.id })
        let newEvents = data.events.filter { !localEventIds.contains($0.id) }
        if !newEvents.isEmpty {
            events.append(contentsOf: newEvents)
            DataStore.shared.saveEvents(events)
        }

        let localEntryIds = Set(entries.map { $0.id })
        let newEntries = data.entries.filter { !localEntryIds.contains($0.id) }
        if !newEntries.isEmpty {
            entries.append(contentsOf: newEntries)
            DataStore.shared.saveEntries(entries)
        }

        // Full replace: presets first so user-specific entries override them in mergedWith
        let cloudTypes = data.drinkTypes.sorted { $0.isPreset && !$1.isPreset }
        if !cloudTypes.isEmpty {
            customDrinkTypes = cloudTypes
            DataStore.shared.saveCustomDrinkTypes(customDrinkTypes)
        }

        let localChallengeIds = Set(challenges.map { $0.id })
        let newChallenges = data.challenges.filter { !localChallengeIds.contains($0.id) }
        if !newChallenges.isEmpty {
            challenges.append(contentsOf: newChallenges)
            DataStore.shared.saveChallenges(challenges)
        }

        if let cloud = data.profile {
            // Never downgrade onboardingComplete — the local write may not have
            // reached Firebase yet when this pull was issued.
            var merged = cloud
            if userProfile.onboardingComplete { merged.onboardingComplete = true }
            updateUserProfile(merged)
        } else {
            push { try await FirebaseManager.shared.pushProfile(self.userProfile) }
        }

        let localCoachIds = Set(coachReports.map { $0.id })
        let newCoach = data.coachReports.filter { !localCoachIds.contains($0.id) }
        if !newCoach.isEmpty {
            coachReports.append(contentsOf: newCoach)
            DataStore.shared.saveCoachReports(coachReports)
        }
        for cloud in data.coachReports {
            if let report = cloud.report,
               let idx = coachReports.firstIndex(where: { $0.id == cloud.id }),
               coachReports[idx].report == nil {
                coachReports[idx].report = report
                DataStore.shared.saveCoachReports(coachReports)
            }
        }
    }

    // MARK: - BAC helpers (for active event view)

    /// BAC that would result from logging `drinkTypeId` right now into `eventId`.
    func projectedBAC(forEventId eventId: String, addingDrinkTypeId dtId: String) -> Double {
        guard let event = events.first(where: { $0.id == eventId }) else { return 0 }
        let existing    = entries.filter { $0.eventId == eventId }
        let eventWater  = waterEntries.filter { $0.eventId == eventId }
        let eventFood   = foodEntries.filter { $0.eventId == eventId }
        let hypothetical = DrinkEntry(
            id: "__projected__",
            eventId: eventId,
            drinkTypeId: dtId,
            timestamp: Date(),
            quantity: 1,
            comment: nil,
            volumeOverrideMl: nil,
            abvOverride: nil
        )
        let r    = BACCalculator.profileR(profile: userProfile)
        let beta = BACCalculator.eliminationRate(profile: userProfile)
        return BACCalculator.currentBAC(
            entries: existing + [hypothetical],
            waterEntries: eventWater,
            drinkTypes: allDrinkTypes,
            profile: userProfile,
            eventStart: event.startTime,
            stomachState: event.stomachState ?? .empty,
            stomachStateTimestamp: event.stomachStateTimestamp ?? event.startTime,
            foodEntries: eventFood
        )
    }

    func currentBAC(for eventId: String) -> Double {
        guard let event = events.first(where: { $0.id == eventId }) else { return 0 }
        let eventEntries = entries.filter { $0.eventId == eventId }
        let eventWater   = waterEntries.filter { $0.eventId == eventId }
        let eventFood    = foodEntries.filter { $0.eventId == eventId }
        return BACCalculator.currentBAC(
            entries: eventEntries,
            waterEntries: eventWater,
            drinkTypes: allDrinkTypes,
            profile: userProfile,
            eventStart: event.startTime,
            stomachState: event.stomachState ?? .empty,
            stomachStateTimestamp: event.stomachStateTimestamp ?? event.startTime,
            foodEntries: eventFood
        )
    }

    func totalDrinks(for eventId: String) -> Int {
        entries.filter { $0.eventId == eventId }.reduce(0) { $0 + $1.quantity }
    }

    func totalCalories(for eventId: String) -> Double {
        entries.filter { $0.eventId == eventId }.reduce(0.0) { sum, e in
            let dt = allDrinkTypes.first { $0.id == e.drinkTypeId }
            return sum + (dt?.caloriesPerServing ?? 0) * Double(e.quantity)
        }
    }
}

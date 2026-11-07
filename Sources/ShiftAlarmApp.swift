import SwiftUI
import UserNotifications

@main
struct ShiftAlarmApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var anchor = Self.defaultAnchor
    @State private var rangeStart = Calendar.current.startOfDay(for: Date())
    @State private var rangeEnd = Calendar.current.date(
        byAdding: .day, value: 30, to: Calendar.current.startOfDay(for: Date())
    ) ?? Date()
    @State private var status = ""

    private static var defaultAnchor: Date {
        let year = Calendar.current.component(.year, from: Date())
        return Calendar.current.date(from: DateComponents(year: year, month: 11, day: 8)) ?? Date()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("排班规则") {
                    Text("白班 4 天 → 休息 2 天 → 夜班 4 天 → 休息 2 天")
                    Text("白班 08:00–20:00；夜班 20:00–次日 08:00")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    DatePicker("白班第一天", selection: $anchor, displayedComponents: .date)
                }

                Section("选择日期范围") {
                    DatePicker("开始日期", selection: $rangeStart, displayedComponents: .date)
                    DatePicker("结束日期", selection: $rangeEnd, in: rangeStart..., displayedComponents: .date)
                }

                Section {
                    Button("安排班次切换提醒") {
                        scheduleNotifications()
                    }
                    Text("只在班次切换前一天 20:00 提醒。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if !status.isEmpty {
                        Text(status)
                            .font(.footnote)
                    }
                }

                Section("排班预览") {
                    ForEach(schedulePreview(), id: \.date) { item in
                        HStack {
                            Text(item.date.formatted(date: .abbreviated, time: .omitted))
                            Spacer()
                            Text(item.shift)
                                .foregroundStyle(item.shift == "休息" ? .secondary : .primary)
                        }
                    }
                }
            }
            .navigationTitle("倒班闹钟")
        }
    }

    private func shift(for date: Date) -> String {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        let anchorDay = calendar.startOfDay(for: anchor)
        let difference = calendar.dateComponents([.day], from: anchorDay, to: day).day ?? 0
        let index = ((difference % 12) + 12) % 12

        switch index {
        case 0...3: return "白班"
        case 4...5: return "休息"
        case 6...9: return "夜班"
        default: return "休息"
        }
    }

    private func schedulePreview() -> [(date: Date, shift: String)] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: rangeStart)
        let end = calendar.startOfDay(for: rangeEnd)
        guard end >= start else { return [] }

        var result: [(Date, String)] = []
        var date = start
        while date <= end && result.count < 100 {
            result.append((date, shift(for: date)))
            guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
        }
        return result
    }

    private func scheduleNotifications() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            DispatchQueue.main.async {
                if let error {
                    status = "通知权限出错：\(error.localizedDescription)"
                    return
                }
                guard granted else {
                    status = "未获得通知权限。请到“设置 → 通知 → 倒班闹钟”允许通知。"
                    return
                }

                center.removeAllPendingNotificationRequests()

                let calendar = Calendar.current
                let start = calendar.startOfDay(for: rangeStart)
                let end = calendar.startOfDay(for: rangeEnd)
                let today = calendar.startOfDay(for: Date())
                var date = start
                var count = 0

                while date <= end && count < 60 {
                    // date 是即将开始新班次的日期；前一天 20:00 提醒。
                    let previousDay = calendar.date(byAdding: .day, value: -1, to: date)!
                    let previousShift = shift(for: previousDay)
                    let newShift = shift(for: date)

                    if (newShift == "白班" || newShift == "夜班"),
                       previousShift != newShift,
                       previousDay >= today,
                       let fireDate = calendar.date(
                           bySettingHour: 20, minute: 0, second: 0, of: previousDay
                       ),
                       fireDate > Date() {
                        let content = UNMutableNotificationContent()
                        content.title = "倒班提醒"
                        content.body = "明天开始\(newShift)"
                        content.sound = .default

                        let components = calendar.dateComponents(
                            [.year, .month, .day, .hour, .minute], from: fireDate
                        )
                        let trigger = UNCalendarNotificationTrigger(
                            dateMatching: components, repeats: false
                        )
                        let request = UNNotificationRequest(
                            identifier: "shift-\(date.timeIntervalSince1970)",
                            content: content,
                            trigger: trigger
                        )
                        center.add(request)
                        count += 1
                    }

                    guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { break }
                    date = next
                }

                status = "已安排 \(count) 条提醒。请保持通知权限开启。"
            }
        }
    }
}

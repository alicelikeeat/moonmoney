import AppIntents
import SwiftUI
import WidgetKit

@main
struct MoonMoneyWidgetsBundle: WidgetBundle {
    var body: some Widget {
        SummaryWidget()
        QuickAddControl()
        AIEntryControl()
    }
}

/// Control Center / Lock Screen / Action Button: open the entry sheet.
struct QuickAddControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.moonmoney.app.control.add") {
            ControlWidgetButton(action: OpenEntryIntent()) {
                Label("记一笔", systemImage: "plus.circle.fill")
            }
        }
        .displayName("记一笔")
        .description("打开 MoonMoney 快速记账。")
    }
}

/// Control Center / Action Button: open AI one-sentence entry.
struct AIEntryControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.moonmoney.app.control.ai") {
            ControlWidgetButton(action: OpenAIEntryIntent()) {
                Label("AI 记账", systemImage: "sparkles")
            }
        }
        .displayName("AI 记账")
        .description("一句话记账。")
    }
}

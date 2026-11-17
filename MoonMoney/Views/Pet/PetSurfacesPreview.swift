import SwiftData
import SwiftUI
import WidgetKit

/// Renders the real widget and Live Activity views inside the app so the simulator
/// screenshot run can capture them. Not linked from the normal UI.
struct PetSurfacesPreview: View {
    @Environment(\.modelContext) private var context
    @State private var snapshot = PetSnapshot.placeholder

    var body: some View {
        let state = BookkeepingAttributes.ContentState(snapshot)
        let ends = PetSnapshotLogic.endOfDay(for: .now, calendar: .current)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("主屏小组件")
                    .font(Font.skin(.headline))
                HStack(alignment: .top, spacing: 12) {
                    PetWidgetView(snapshot: snapshot, family: .systemSmall)
                        .frame(width: 158, height: 158)
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                    PetWidgetView(snapshot: snapshot, family: .systemMedium)
                        .frame(height: 158)
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                }
                Text("锁屏实时活动")
                    .font(Font.skin(.headline))
                PetSessionBanner(state: state, endsAt: ends, stale: false)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
                Text("灵动岛")
                    .font(Font.skin(.headline))
                HStack(spacing: 16) {
                    HStack(spacing: 8) {
                        PetPixel(species: snapshot.species, stage: snapshot.stage, expression: snapshot.expression)
                            .frame(width: 28, height: 28)
                        Text(Money.compact(snapshot.todayExpense))
                            .font(.caption.monospacedDigit().weight(.semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.black, in: Capsule())
                    .foregroundStyle(.white)
                    Text("紧凑")
                        .font(Font.skin(.caption))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
        .background { AmbientBackground(tint: .orange) }
        .navigationTitle("宠物的系统界面")
        .onAppear { snapshot = PetSnapshotLogic.capture(context: context) }
    }
}
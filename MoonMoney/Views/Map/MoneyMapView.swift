import MapKit
import RealityKit
import SwiftData
import SwiftUI
import UIKit

/// 资金三维地图：a 3D "money city" (categories × months) and a 3D place map.
struct MoneyMapView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case city = "资金城市"
        case places = "消费地图"
        var id: String { rawValue }
    }

    @Environment(AppSettings.self) private var settings
    @State private var mode: Mode

    init(initialMode: Mode = .city) {
        _mode = State(initialValue: initialMode)
    }

    var body: some View {
        Group {
            switch mode {
            case .city: MoneyCityView(ledgerID: settings.currentLedgerID)
            case .places: SpendingPlacesView(ledgerID: settings.currentLedgerID)
            }
        }
        .id("\(mode.rawValue)-\(settings.currentLedgerID?.uuidString ?? "")")
        .navigationTitle("资金三维地图")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("视图", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
        }
        .toolbar(.hidden, for: .tabBar)
    }
}

// MARK: - 3D money city

private struct CityCell: Identifiable, Hashable {
    var id: String { "\(row)-\(column)" }
    let row: Int
    let column: Int
    let category: String
    let month: Date
    let cents: Int
    let colorHex: String
}

private struct MoneyCityView: View {
    @Query private var records: [Record]
    @State private var selected: CityCell?
    private let months: [Date]

    init(ledgerID: UUID?) {
        let cal = Calendar.current
        let thisMonth = cal.dateInterval(of: .month, for: .now)?.start ?? .now
        let first = cal.date(byAdding: .month, value: -5, to: thisMonth) ?? thisMonth
        months = (0..<6).compactMap { cal.date(byAdding: .month, value: $0, to: first) }
        _records = Query(filter: #Predicate<Record> {
            $0.date >= first && $0.ledgerID == ledgerID && $0.kindRaw == 0
        })
    }

    var body: some View {
        let cells = buildCells()
        let total = cells.reduce(0) { $0 + $1.cents }
        let signature = cells.map { "\($0.id):\($0.cents)" }.joined(separator: ",")

        ZStack(alignment: .bottom) {
            if cells.isEmpty {
                ContentUnavailableView("近 6 个月没有支出", systemImage: "building.2",
                                       description: Text("记几笔账后，这里会长出一座属于你的资金城市。"))
            } else {
                CityScene(cells: cells, months: months, selected: $selected)
                    .id(signature)
                    .ignoresSafeArea(edges: .bottom)
                    .accessibilityElement()
                    .accessibilityLabel("资金城市三维图，近 6 个月共支出 \(Money.format(total))")

                infoCard(cells: cells, total: total)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
        .background { AmbientBackground(tint: .indigo) }
    }

    @ViewBuilder
    private func infoCard(cells: [CityCell], total: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let selected {
                HStack {
                    Circle().fill(Color(hex: selected.colorHex)).frame(width: 10, height: 10)
                    Text("\(selected.category) · \(selected.month.zh("yMMM"))").font(Font.skin(.headline))
                    Spacer()
                    Button {
                        withAnimation(.smooth) { self.selected = nil }
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.inCard(circle: true))
                    .accessibilityLabel("关闭")
                }
                Text(Money.format(selected.cents))
                    .font(Font.skin(.title2).bold().monospacedDigit())
                let monthTotal = cells.filter { $0.column == selected.column }.reduce(0) { $0 + $1.cents }
                Text("占当月支出 \(InsightEngine.percent(Double(selected.cents) / Double(max(monthTotal, 1))))")
                    .font(Font.skin(.caption))
                    .foregroundStyle(.secondary)
            } else {
                Text("近 6 个月 · \(Money.format(total))").font(Font.skin(.headline))
                Text("每栋楼是一个分类在一个月里的支出，越高花得越多。拖动旋转，双指缩放，点按楼体查看金额。")
                    .font(Font.skin(.caption))
                    .foregroundStyle(.secondary)
                legend(cells)
            }
        }
        .glassCard(cornerRadius: 24, padding: 16)
    }

    private func legend(_ cells: [CityCell]) -> some View {
        let rows = Dictionary(grouping: cells, by: \.row).sorted { $0.key < $1.key }
        return ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(rows, id: \.key) { _, items in
                    if let first = items.first {
                        HStack(spacing: 4) {
                            Circle().fill(Color(hex: first.colorHex)).frame(width: 8, height: 8)
                            Text(first.category).font(Font.skin(.caption2))
                        }
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    /// Top 6 categories × last 6 months.
    private func buildCells() -> [CityCell] {
        let counted = Stats.counted(records)
        let byCategory = Dictionary(grouping: counted) { $0.category?.uuid }
        let top = byCategory
            .map { (key: $0.key, total: $0.value.reduce(0) { $0 + $1.baseAmountCents }, sample: $0.value.first) }
            .sorted { $0.total > $1.total }
            .prefix(6)
        let cal = Calendar.current
        var cells: [CityCell] = []
        for (row, entry) in top.enumerated() {
            let items = byCategory[entry.key] ?? []
            for (column, month) in months.enumerated() {
                let cents = items.filter { cal.isDate($0.date, equalTo: month, toGranularity: .month) }
                    .reduce(0) { $0 + $1.baseAmountCents }
                cells.append(CityCell(row: row, column: column,
                                      category: entry.sample?.category?.name ?? "未分类",
                                      month: month, cents: cents,
                                      colorHex: entry.sample?.category?.colorHex ?? "#8E8E93"))
            }
        }
        return cells
    }
}

/// RealityKit scene: one glossy tower per cell on a glass-like base plate.
private struct CityScene: View {
    let cells: [CityCell]
    let months: [Date]
    @Binding var selected: CityCell?

    private let spacing: Float = 0.14
    private let footprint: Float = 0.09
    private let maxHeight: Float = 0.6

    var body: some View {
        RealityView { content in
            content.camera = .virtual
            let root = Entity()
            root.name = "city"
            build(into: root)
            content.add(root)
        }
        .realityViewCameraControls(.orbit)
        .gesture(
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    let name = value.entity.name
                    if let cell = cells.first(where: { $0.id == name }) {
                        withAnimation(.smooth) { selected = cell }
                        Haptics.tap()
                    }
                }
        )
    }

    private func build(into root: Entity) {
        let maxCents = Float(cells.map(\.cents).max() ?? 1)
        let rows = (cells.map(\.row).max() ?? 0) + 1
        let columns = months.count
        let width = Float(columns) * spacing
        let depth = Float(rows) * spacing
        let originX = -width / 2 + spacing / 2
        let originZ = -depth / 2 + spacing / 2

        // Base plate
        let plate = ModelEntity(
            mesh: .generateBox(width: width + 0.08, height: 0.012, depth: depth + 0.08, cornerRadius: 0.006),
            materials: [SimpleMaterial(color: UIColor.white.withAlphaComponent(0.55), roughness: 0.2, isMetallic: false)]
        )
        plate.position = [0, -0.006, 0]
        root.addChild(plate)

        // Towers
        for cell in cells {
            let ratio = maxCents > 0 ? Float(cell.cents) / maxCents : 0
            let height = max(0.004, ratio * maxHeight)
            let color = UIColor(Color(hex: cell.colorHex))
            let tower = ModelEntity(
                mesh: .generateBox(width: footprint, height: height, depth: footprint, cornerRadius: min(0.012, height / 2)),
                materials: [SimpleMaterial(color: color, roughness: 0.25, isMetallic: true)]
            )
            tower.name = cell.id
            tower.position = [originX + Float(cell.column) * spacing, height / 2, originZ + Float(cell.row) * spacing]
            tower.components.set(InputTargetComponent())
            tower.components.set(CollisionComponent(shapes: [.generateBox(width: footprint, height: max(height, 0.03), depth: footprint)]))
            root.addChild(tower)
        }

        // Month labels along the front edge
        for (column, month) in months.enumerated() {
            let label = ModelEntity(
                mesh: .generateText(month.zh("M"), extrusionDepth: 0.002, font: .systemFont(ofSize: 0.035, weight: .semibold)),
                materials: [UnlitMaterial(color: .label)]
            )
            let bounds = label.visualBounds(relativeTo: nil)
            label.position = [originX + Float(column) * spacing - bounds.extents.x / 2, 0.001, depth / 2 + 0.05]
            label.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
            root.addChild(label)
        }

        // Lighting
        let sun = DirectionalLight()
        sun.light.intensity = 4_000
        sun.look(at: .zero, from: [0.6, 1.2, 0.9], relativeTo: nil)
        root.addChild(sun)
        let fill = PointLight()
        fill.light.intensity = 6_000
        fill.position = [-0.6, 0.8, -0.4]
        root.addChild(fill)

        // Tilt the city toward the camera for a 3D overview
        root.orientation = simd_quatf(angle: .pi / 7, axis: [1, 0, 0]) * simd_quatf(angle: -.pi / 9, axis: [0, 1, 0])
        root.position = [0, -0.15, -0.2]
    }
}

// MARK: - 3D spending places

private struct PlaceCluster: Identifiable {
    let id: String
    let name: String
    let coordinate: CLLocationCoordinate2D
    let cents: Int
    let records: [Record]
}

private struct SpendingPlacesView: View {
    enum Range: String, CaseIterable, Identifiable {
        case month = "本月", quarter = "近 3 个月", year = "近一年", all = "全部"
        var id: String { rawValue }
        var start: Date {
            let cal = Calendar.current
            switch self {
            case .month: return Periods.month(containing: .now).start
            case .quarter: return cal.date(byAdding: .month, value: -3, to: .now) ?? .distantPast
            case .year: return cal.date(byAdding: .year, value: -1, to: .now) ?? .distantPast
            case .all: return .distantPast
            }
        }
    }

    @Environment(AppSettings.self) private var settings
    @Query private var records: [Record]
    @State private var range: Range = .quarter
    @State private var position: MapCameraPosition = .automatic
    @State private var selected: PlaceCluster?

    init(ledgerID: UUID?) {
        _records = Query(filter: #Predicate<Record> {
            $0.ledgerID == ledgerID && $0.kindRaw == 0 && $0.latitude != nil
        }, sort: \Record.date, order: .reverse)
    }

    var body: some View {
        @Bindable var settings = settings
        let clusters = buildClusters()
        let maxCents = clusters.map(\.cents).max() ?? 1

        ZStack(alignment: .bottom) {
            if clusters.isEmpty {
                VStack(spacing: 16) {
                    ContentUnavailableView("还没有带位置的账单", systemImage: "map",
                                           description: Text("打开下方开关，记账时会自动附上消费地点；也可以在记账面板点「位置」。"))
                    Toggle("记账时记录位置", isOn: $settings.recordLocation)
                        .padding(.horizontal, 32)
                }
            } else {
                Map(position: $position) {
                    ForEach(clusters) { cluster in
                        Annotation(cluster.name, coordinate: cluster.coordinate, anchor: .bottom) {
                            PlaceBubble(cluster: cluster, scale: sqrt(Double(cluster.cents) / Double(max(maxCents, 1))),
                                        isSelected: selected?.id == cluster.id)
                                .onTapGesture {
                                    withAnimation(.smooth) { selected = cluster }
                                    Haptics.tap()
                                }
                        }
                    }
                }
                .mapStyle(.standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll))
                .mapControls {
                    MapCompass()
                    MapPitchToggle()
                    MapScaleView()
                }
                .onAppear { position = .camera(camera(for: clusters)) }
                .onChange(of: range) { position = .camera(camera(for: buildClusters())) }

                VStack(spacing: 10) {
                    Picker("范围", selection: $range) {
                        ForEach(Range.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if let selected {
                        placeCard(selected)
                    } else {
                        Text("\(clusters.count) 个地点 · \(Money.format(clusters.reduce(0) { $0 + $1.cents }))")
                            .font(Font.skin(.subheadline).weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .glassCard(cornerRadius: 24, padding: 14)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .background { AmbientBackground(tint: .blue) }
    }

    private func placeCard(_ cluster: PlaceCluster) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(cluster.name, systemImage: "mappin.circle.fill").font(Font.skin(.headline))
                Spacer()
                Text(Money.format(cluster.cents)).font(Font.skin(.headline).monospacedDigit())
                Button {
                    withAnimation(.smooth) { selected = nil }
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.inCard(circle: true))
                .accessibilityLabel("关闭")
            }
            ForEach(cluster.records.prefix(3)) { record in
                HStack {
                    Text(record.displayTitle).font(Font.skin(.caption))
                    Text(record.date.zh("MMMd")).font(Font.skin(.caption2)).foregroundStyle(.secondary)
                    Spacer()
                    Text(Money.format(record.baseAmountCents)).font(Font.skin(.caption).monospacedDigit())
                }
            }
            if cluster.records.count > 3 {
                Text("共 \(cluster.records.count) 笔").font(Font.skin(.caption2)).foregroundStyle(.secondary)
            }
        }
    }

    /// Groups records by place name, or by a ~500 m grid when unnamed,
    /// so nearby spending forms one readable pillar.
    private func buildClusters() -> [PlaceCluster] {
        let start = range.start
        let located = Stats.counted(records).filter { $0.date >= start && $0.hasLocation }
        let groups = Dictionary(grouping: located) { record -> String in
            if !record.placeName.isEmpty { return "name:\(record.placeName)" }
            let lat = ((record.latitude ?? 0) * 200).rounded()
            let lon = ((record.longitude ?? 0) * 200).rounded()
            return "grid:\(lat),\(lon)"
        }
        return groups.map { key, items in
            let lat = items.compactMap(\.latitude).reduce(0, +) / Double(items.count)
            let lon = items.compactMap(\.longitude).reduce(0, +) / Double(items.count)
            let names = Dictionary(grouping: items.map(\.placeName).filter { !$0.isEmpty }, by: { $0 })
            let name = names.max { $0.value.count < $1.value.count }?.key ?? "未命名地点"
            return PlaceCluster(id: key, name: name, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                                cents: items.reduce(0) { $0 + $1.baseAmountCents },
                                records: items.sorted { $0.baseAmountCents > $1.baseAmountCents })
        }
        .sorted { $0.cents > $1.cents }
    }

    /// A tilted 3D camera framing every cluster.
    private func camera(for clusters: [PlaceCluster]) -> MapCamera {
        let lats = clusters.map(\.coordinate.latitude)
        let lons = clusters.map(\.coordinate.longitude)
        let center = CLLocationCoordinate2D(
            latitude: ((lats.min() ?? 31.23) + (lats.max() ?? 31.23)) / 2,
            longitude: ((lons.min() ?? 121.47) + (lons.max() ?? 121.47)) / 2
        )
        let span = max((lats.max() ?? 0) - (lats.min() ?? 0), (lons.max() ?? 0) - (lons.min() ?? 0))
        let distance = max(2_500, span * 111_000 * 2.6)
        return MapCamera(centerCoordinate: center, distance: distance, heading: 25, pitch: 60)
    }
}

/// A glass pillar whose height and width scale with the amount spent there.
private struct PlaceBubble: View {
    let cluster: PlaceCluster
    let scale: Double
    let isSelected: Bool

    var body: some View {
        let height = 18 + 70 * scale
        VStack(spacing: 2) {
            Text(Money.compact(cluster.cents))
                .font(Font.skin(.caption2).weight(.bold).monospacedDigit())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .glassEffect(.regular.tint(isSelected ? Color.accentColor.opacity(0.4) : nil), in: .capsule)
            RoundedRectangle(cornerRadius: 5)
                .fill(LinearGradient(colors: [Color.expense, Color.orange.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                .frame(width: 10 + 10 * scale, height: height)
                .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
        }
        .scaleEffect(isSelected ? 1.15 : 1, anchor: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(cluster.name)，\(Money.format(cluster.cents))")
    }
}

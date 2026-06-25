import SwiftUI

/// Real-time weight vs time line chart with axes, grid, and labels.
struct WeightGraphView: View {
    let data: [(elapsed: Double, weight: Double)]
    let displayUnit: WeightUnit

    private let yTickCount = 4
    private let xTickCount = 4

    var body: some View {
        VStack(spacing: 0) {
            // Title
            HStack {
                Text("Weight")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                Text("(\(displayUnit.symbol))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("Time (s)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 4)

            GeometryReader { geometry in
                let w = geometry.size.width
                let h = geometry.size.height
                let yAxisWidth: CGFloat = 42
                let xAxisHeight: CGFloat = 18
                let plotLeft = yAxisWidth
                let plotTop: CGFloat = 0
                let plotWidth = w - plotLeft
                let plotHeight = h - xAxisHeight
                let maxT = effectiveMaxTime
                let maxW = effectiveMaxWeight
                let rangeW = max(0.1, maxW)

                ZStack(alignment: .topLeading) {
                    // Grid lines
                    ForEach(0..<yTickCount, id: \.self) { i in
                        let y = plotTop + plotHeight * CGFloat(i) / CGFloat(yTickCount - 1)
                        Path { path in
                            path.move(to: CGPoint(x: plotLeft, y: y))
                            path.addLine(to: CGPoint(x: plotLeft + plotWidth, y: y))
                        }
                        .stroke(.secondary.opacity(0.15), lineWidth: 0.5)
                    }

                    // Y-axis labels
                    ForEach(0..<yTickCount, id: \.self) { i in
                        let value = maxW * Double(yTickCount - 1 - i) / Double(yTickCount - 1)
                        let y = plotTop + plotHeight * CGFloat(i) / CGFloat(yTickCount - 1)
                        Text(displayUnit.format(value))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .position(x: yAxisWidth / 2, y: y)
                    }

                    // X-axis labels
                    ForEach(0..<xTickCount, id: \.self) { i in
                        let value = maxT * Double(i) / Double(xTickCount - 1)
                        let x = plotLeft + plotWidth * CGFloat(i) / CGFloat(xTickCount - 1)
                        Text(formatTime(value))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .position(x: x, y: plotTop + plotHeight + xAxisHeight / 2)
                    }

                    // Data line
                    Path { path in
                        guard data.count > 1 else { return }
                        for (i, point) in data.enumerated() {
                            let x = plotLeft + plotWidth * (maxT > 0 ? point.elapsed / maxT : 0)
                            let y = plotTop + plotHeight * (1 - point.weight / rangeW)
                            let pt = CGPoint(x: x, y: y)
                            if i == 0 { path.move(to: pt) }
                            else { path.addLine(to: pt) }
                        }
                    }
                    .stroke(.orange, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                    // Axis lines
                    Path { path in
                        path.move(to: CGPoint(x: plotLeft, y: plotTop + plotHeight))
                        path.addLine(to: CGPoint(x: plotLeft + plotWidth, y: plotTop + plotHeight))
                    }
                    .stroke(.secondary.opacity(0.5), lineWidth: 0.5)

                    Path { path in
                        path.move(to: CGPoint(x: plotLeft, y: plotTop))
                        path.addLine(to: CGPoint(x: plotLeft, y: plotTop + plotHeight))
                    }
                    .stroke(.secondary.opacity(0.5), lineWidth: 0.5)
                }
            }
        }
        .padding(4)
        .background(.ultraThinMaterial.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var effectiveMaxTime: Double {
        let raw = data.last?.elapsed ?? 0
        // Snap to next 30s ceiling, minimum 30s
        return max(ceil(raw / 30) * 30, 30)
    }

    private var effectiveMaxWeight: Double {
        let dataMax = data.map(\.weight).max() ?? 0
        // Snap to next nice round number
        let ceil10 = ceil(dataMax / 10) * 10
        let ceil50 = ceil(dataMax / 50) * 50
        let ceil100 = ceil(dataMax / 100) * 100
        if dataMax < 20 { return max(ceil10, 10) }
        if dataMax < 100 { return ceil50 }
        return ceil100
    }

    private func formatTime(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return "\(m):\(String(format: "%02d", s))"
    }
}

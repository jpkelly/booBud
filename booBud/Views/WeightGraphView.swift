import SwiftUI

/// Real-time weight + flow rate vs time line chart with dual Y-axes, grid, and labels.
struct WeightGraphView: View {
    let data: [(elapsed: Double, weight: Double)]
    let flowData: [(elapsed: Double, flowRate: Double)]
    let displayUnit: WeightUnit
    let flowAutoRange: Bool
    let flowMax: Double
    let underlayWeight: [(elapsed: Double, weight: Double)]
    let underlayFlow: [(elapsed: Double, flowRate: Double)]

    private let yTickCount = 4
    private let xTickCount = 4

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                let w = geometry.size.width
                let h = geometry.size.height
                let leftAxisWidth: CGFloat = 34
                let rightAxisWidth: CGFloat = 34
                let xAxisHeight: CGFloat = 18
                let plotLeft = leftAxisWidth
                let plotTop: CGFloat = 0
                let plotWidth = w - plotLeft - rightAxisWidth
                let plotHeight = h - xAxisHeight
                let maxT = effectiveMaxTime
                let maxW = effectiveMaxWeight
                let rangeW = max(0.1, maxW)
                let maxF = effectiveMaxFlow
                let rangeF = max(0.1, maxF)

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

                    // Left Y-axis labels (Weight)
                    ForEach(0..<yTickCount, id: \.self) { i in
                        let value = maxW * Double(yTickCount - 1 - i) / Double(yTickCount - 1)
                        let y = plotTop + plotHeight * CGFloat(i) / CGFloat(yTickCount - 1)
                        Text(displayUnit.format(value))
                            .font(.system(size: 9))
                            .foregroundStyle(.orange.opacity(0.8))
                            .position(x: leftAxisWidth / 2, y: y)
                    }

                    // Right Y-axis labels (Flow rate)
                    ForEach(0..<yTickCount, id: \.self) { i in
                        let value = maxF * Double(yTickCount - 1 - i) / Double(yTickCount - 1)
                        let y = plotTop + plotHeight * CGFloat(i) / CGFloat(yTickCount - 1)
                        Text(String(format: "%.1f", value))
                            .font(.system(size: 9))
                            .foregroundStyle(.cyan.opacity(0.8))
                            .position(x: plotLeft + plotWidth + rightAxisWidth / 2, y: y)
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

                    // Underlay flow rate line (dimmed, dashed, behind live)
                    if !underlayFlow.isEmpty {
                        Path { path in
                            for (i, point) in underlayFlow.enumerated() {
                                let x = plotLeft + plotWidth * (maxT > 0 ? point.elapsed / maxT : 0)
                                let y = plotTop + plotHeight * (1 - point.flowRate / rangeF)
                                let pt = CGPoint(x: x, y: y)
                                if i == 0 { path.move(to: pt) }
                                else { path.addLine(to: pt) }
                            }
                        }
                        .stroke(.cyan.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round, dash: [6, 3]))
                    }

                    // Flow rate line (drawn first, behind weight)
                    Path { path in
                        guard flowData.count > 1 else { return }
                        for (i, point) in flowData.enumerated() {
                            let x = plotLeft + plotWidth * (maxT > 0 ? point.elapsed / maxT : 0)
                            let y = plotTop + plotHeight * (1 - point.flowRate / rangeF)
                            let pt = CGPoint(x: x, y: y)
                            if i == 0 { path.move(to: pt) }
                            else { path.addLine(to: pt) }
                        }
                    }
                    .stroke(.cyan, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

                    // Underlay weight line (dimmed, dashed, behind live)
                    if !underlayWeight.isEmpty {
                        Path { path in
                            for (i, point) in underlayWeight.enumerated() {
                                let x = plotLeft + plotWidth * (maxT > 0 ? point.elapsed / maxT : 0)
                                let y = plotTop + plotHeight * (1 - point.weight / rangeW)
                                let pt = CGPoint(x: x, y: y)
                                if i == 0 { path.move(to: pt) }
                                else { path.addLine(to: pt) }
                            }
                        }
                        .stroke(.orange.opacity(0.25), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [6, 3]))
                    }

                    // Weight line
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

                    // Right axis line
                    Path { path in
                        path.move(to: CGPoint(x: plotLeft + plotWidth, y: plotTop))
                        path.addLine(to: CGPoint(x: plotLeft + plotWidth, y: plotTop + plotHeight))
                    }
                    .stroke(.secondary.opacity(0.5), lineWidth: 0.5)
                }
            }

            // Legend
            HStack(spacing: 12) {
                Spacer()
                legendDot(color: .orange, label: "Weight")
                legendDot(color: .cyan, label: "Flow (g/s)")
                Spacer()
            }
            .padding(.bottom, 4)
        }
        .padding(4)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Helpers

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }

    private var effectiveMaxTime: Double {
        let liveMax = data.last?.elapsed ?? 0
        let underlayMax = underlayWeight.last?.elapsed ?? 0
        return max(max(liveMax, underlayMax), 30)
    }

    private var effectiveMaxWeight: Double {
        let dataMax = max(data.map(\.weight).max() ?? 0,
                          underlayWeight.map(\.weight).max() ?? 0)
        let ceil10 = ceil(dataMax / 10) * 10
        let ceil50 = ceil(dataMax / 50) * 50
        let ceil100 = ceil(dataMax / 100) * 100
        if dataMax < 20 { return max(ceil10, 50) }
        if dataMax < 100 { return ceil50 }
        return ceil100
    }

    private var effectiveMaxFlow: Double {
        guard flowAutoRange else { return flowMax }
        let flowMax = flowData.map(\.flowRate).max() ?? 0
        let flowMin = flowData.map(\.flowRate).min() ?? 0
        let absMax = max(abs(flowMax), abs(flowMin))
        if absMax < 1 { return 1 }
        if absMax < 5 { return ceil(absMax) }
        if absMax < 10 { return ceil(absMax / 2) * 2 }
        return ceil(absMax / 5) * 5
    }

    private func formatTime(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return "\(m):\(String(format: "%02d", s))"
    }
}

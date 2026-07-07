import SwiftUI

/// Compact mini line chart for a saved brew — weight progression with optional
/// flow rate overlay. Uses a fixed 16:9 aspect ratio so it echoes the main page
/// graph proportion instead of stretching to fill width.
struct BrewThumbnailView: View {
    let weightPoints: [GraphPoint]
    let flowPoints: [GraphPoint]

    /// Aspect ratio of the plot area (default 16:9 — matches the feel of the
    /// main graph on the home screen).
    var aspectRatio: CGFloat = 16.0 / 9.0

    private let plotInset: CGFloat = 6
    private let guideLineCount = 3

    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height

            let maxT = maxTime
            let maxW = maxWeight
            let maxF = maxFlow

            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(hex: "1A1411").opacity(0.6))

                // Subtle border so the thumbnail reads as a chart card
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.secondary.opacity(0.15), lineWidth: 0.5)

                // Faint horizontal guide lines
                ForEach(0..<guideLineCount, id: \.self) { i in
                    let y = plotInset + (h - plotInset * 2) * CGFloat(i) / CGFloat(guideLineCount - 1)
                    Path { path in
                        path.move(to: CGPoint(x: plotInset, y: y))
                        path.addLine(to: CGPoint(x: w - plotInset, y: y))
                    }
                    .stroke(.secondary.opacity(0.12), lineWidth: 0.5)
                }

                // Flow rate line (behind weight, lower opacity)
                if flowPoints.count > 1, maxF > 0 {
                    Path { path in
                        for (i, pt) in flowPoints.enumerated() {
                            let rx = (maxT > 0 ? pt.elapsed / maxT : 0)
                                .clamped(to: 0...1)
                            let ry = (maxF > 0 ? pt.value / maxF : 0)
                                .clamped(to: 0...1)
                            let x = plotInset + (w - plotInset * 2) * CGFloat(rx)
                            let y = plotInset + (h - plotInset * 2) * CGFloat(1 - ry)
                            let cgPt = CGPoint(x: x, y: y)
                            if i == 0 { path.move(to: cgPt) }
                            else { path.addLine(to: cgPt) }
                        }
                    }
                    .stroke(.cyan.opacity(0.3), style: StrokeStyle(
                        lineWidth: 1,
                        lineCap: .round,
                        lineJoin: .round
                    ))
                }

                // Weight line (on top)
                if weightPoints.count > 1 {
                    Path { path in
                        for (i, pt) in weightPoints.enumerated() {
                            let rx = (maxT > 0 ? pt.elapsed / maxT : 0)
                                .clamped(to: 0...1)
                            let ry = (maxW > 0 ? pt.value / maxW : 0)
                                .clamped(to: 0...1)
                            let x = plotInset + (w - plotInset * 2) * CGFloat(rx)
                            let y = plotInset + (h - plotInset * 2) * CGFloat(1 - ry)
                            let cgPt = CGPoint(x: x, y: y)
                            if i == 0 { path.move(to: cgPt) }
                            else { path.addLine(to: cgPt) }
                        }
                    }
                    .stroke(.orange, style: StrokeStyle(
                        lineWidth: 1.5,
                        lineCap: .round,
                        lineJoin: .round
                    ))
                } else if let single = weightPoints.first {
                    let rx = (maxT > 0 ? single.elapsed / maxT : 0)
                        .clamped(to: 0...1)
                    let ry = (maxW > 0 ? single.value / maxW : 0)
                        .clamped(to: 0...1)
                    let x = plotInset + (w - plotInset * 2) * CGFloat(rx)
                    let y = plotInset + (h - plotInset * 2) * CGFloat(1 - ry)
                    Circle()
                        .fill(.orange)
                        .frame(width: 4, height: 4)
                        .position(x: x, y: y)
                }

                // Empty state — subtle dashed line
                if weightPoints.isEmpty && flowPoints.isEmpty {
                    Path { path in
                        path.move(to: CGPoint(x: plotInset, y: h / 2))
                        path.addLine(to: CGPoint(x: w - plotInset, y: h / 2))
                    }
                    .stroke(.secondary.opacity(0.18), style: StrokeStyle(
                        lineWidth: 1,
                        dash: [3, 3]
                    ))
                }
            }
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Scaling

    private var maxTime: Double {
        let wEnd = weightPoints.last?.elapsed ?? 0
        let fEnd = flowPoints.last?.elapsed ?? 0
        let m = max(wEnd, fEnd)
        return m > 0 ? m : 30
    }

    private var maxWeight: Double {
        let wMax = weightPoints.map(\.value).max() ?? 0
        if wMax <= 0 { return 1 }
        if wMax < 10 { return ceil(wMax) }
        if wMax < 100 { return ceil(wMax / 10) * 10 }
        return ceil(wMax / 50) * 50
    }

    private var maxFlow: Double {
        let fMax = flowPoints.map(\.value).max() ?? 0
        if fMax <= 0 { return 1 }
        if fMax < 1 { return 1 }
        if fMax < 5 { return ceil(fMax) }
        if fMax < 10 { return ceil(fMax / 2) * 2 }
        return ceil(fMax / 5) * 5
    }
}

// MARK: - Clamping helper

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

#Preview {
    VStack(spacing: 12) {
        BrewThumbnailView(
            weightPoints: (0..<60).map { i in
                GraphPoint(elapsed: Double(i), value: Double(min(i * 2, 80) + Int.random(in: -3...3)))
            },
            flowPoints: (0..<60).map { i in
                GraphPoint(elapsed: Double(i), value: max(0, Double(5 - abs(Int(i) - 25)) * 0.3 + Double.random(in: -0.3...0.3)))
            }
        )
        .frame(width: 170)

        BrewThumbnailView(
            weightPoints: [],
            flowPoints: []
        )
        .frame(width: 170)

        BrewThumbnailView(
            weightPoints: [GraphPoint(elapsed: 15, value: 42)],
            flowPoints: []
        )
        .frame(width: 170)
    }
    .padding()
    .background(Color(hex: "130E0C"))
}

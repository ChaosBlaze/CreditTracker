import SwiftUI
import Charts

/// Inline mini chart using Swift Charts LineMark.
/// No axes, labels, or grid. 60x24pt default.
/// Line draws on with trim animation on appear.
struct SparklineView: View {
    let data: [Double]
    let gradientStart: Color
    let gradientEnd: Color
    var width: CGFloat = 60
    var height: CGFloat = 24

    @State private var trimEnd: CGFloat = 0

    var body: some View {
        Chart {
            ForEach(Array(data.enumerated()), id: \.offset) { index, value in
                LineMark(
                    x: .value("Index", index),
                    y: .value("Value", value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [gradientStart, gradientEnd],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .interpolationMethod(.catmullRom)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartPlotStyle { plot in
            plot.frame(width: width, height: height)
        }
        .frame(width: width, height: height)
        .mask {
            Rectangle()
                .frame(width: width * trimEnd, height: height)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).delay(0.2)) {
                trimEnd = 1
            }
        }
    }
}

extension SparklineView {
    init(data: [Double], startHex: String, endHex: String, width: CGFloat = 60, height: CGFloat = 24) {
        self.data = data
        self.gradientStart = Color(hex: startHex)
        self.gradientEnd = Color(hex: endHex)
        self.width = width
        self.height = height
    }
}

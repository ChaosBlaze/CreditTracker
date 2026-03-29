import WidgetKit
import SwiftUI

@main
struct CreditTrackerWidgetBundle: WidgetBundle {
    var body: some Widget {
        CreditTrackerWidget()
    }
}

struct CreditTrackerWidget: Widget {
    let kind: String = "CreditTrackerWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ROIProvider()) { entry in
            CreditTrackerWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Credit ROI")
        .description("See your annual fees vs. value extracted at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

import SwiftUI
import WidgetKit

@main
struct VitalWidgetsBundle: WidgetBundle {
    var body: some Widget {
        FastingWidget()
        FastingLiveActivity()
    }
}

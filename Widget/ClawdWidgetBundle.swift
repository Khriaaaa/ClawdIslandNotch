import WidgetKit
import SwiftUI

@main
struct ClawdWidgetBundle: WidgetBundle {
    var body: some Widget {
        ClawdLiveActivity()
        ClawdHomeWidget()
        ClawdLockAccessoryWidget()
    }
}

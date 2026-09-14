import SwiftUI
import WidgetKit

@main
struct MV2WidgetBundle: WidgetBundle {
  var body: some Widget {
    MV2UnreadWidget()
    MV2LockScreenWidget()
  }
}

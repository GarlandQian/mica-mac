import SwiftUI

private struct MicaFocusedWorkbenchDestinationKey: FocusedValueKey {
    typealias Value = Binding<WorkbenchDestination>
}

private struct MicaAddControllerRequestKey: FocusedValueKey {
    typealias Value = Binding<Int>
}

private struct MicaEditControllerRequestKey: FocusedValueKey {
    typealias Value = Binding<Int>
}

extension FocusedValues {
    var micaFocusedWorkbenchDestination: Binding<WorkbenchDestination>? {
        get { self[MicaFocusedWorkbenchDestinationKey.self] }
        set { self[MicaFocusedWorkbenchDestinationKey.self] = newValue }
    }

    var micaAddControllerRequestID: Binding<Int>? {
        get { self[MicaAddControllerRequestKey.self] }
        set { self[MicaAddControllerRequestKey.self] = newValue }
    }

    var micaEditControllerRequestID: Binding<Int>? {
        get { self[MicaEditControllerRequestKey.self] }
        set { self[MicaEditControllerRequestKey.self] = newValue }
    }
}

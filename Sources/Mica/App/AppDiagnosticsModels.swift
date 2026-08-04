import Foundation
import MicaCore

struct DiagnosticsReportSection: Identifiable, Equatable {
    var id: String
    var title: String
    var value: String
}

struct DiagnosticsExportPlanRow: Identifiable, Equatable {
    var id: String
    var title: String
    var value: String
    var boundary: String
}

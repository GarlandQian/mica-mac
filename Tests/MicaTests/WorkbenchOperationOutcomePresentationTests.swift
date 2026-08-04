import Testing
@testable import Mica

struct WorkbenchOperationOutcomePresentationTests {
    @Test func workingOperationDoesNotCreateACompletedOutcome() {
        let presentation = WorkbenchOperationOutcomePresentation(
            operationState: .working("Refreshing")
        )

        #expect(presentation == nil)
    }

    @Test func successOutcomeKeepsCommandContext() throws {
        let presentation = try #require(
            WorkbenchOperationOutcomePresentation(
                operationState: .success(
                    "Refresh finished",
                    action: "Refresh",
                    target: "Primary"
                )
            )
        )

        #expect(presentation.tone == .success)
        #expect(presentation.titleKey == "lifecycle.success")
        #expect(presentation.symbolName == "checkmark.circle.fill")
        #expect(presentation.message == "Refresh finished")
        #expect(presentation.context == "Refresh - Primary")
        #expect(presentation.nextStep == nil)
    }

    @Test func partialOutcomeKeepsRecoveryStep() throws {
        let presentation = try #require(
            WorkbenchOperationOutcomePresentation(
                operationState: .partial(
                    "Rules refreshed with stale providers",
                    nextStep: "Refresh providers"
                )
            )
        )

        #expect(presentation.tone == .partial)
        #expect(presentation.titleKey == "lifecycle.partial")
        #expect(presentation.symbolName == "exclamationmark.triangle.fill")
        #expect(presentation.nextStep == "Refresh providers")
    }

    @Test func failedOutcomeDropsBlankOptionalFields() throws {
        let presentation = try #require(
            WorkbenchOperationOutcomePresentation(
                operationState: .error(
                    "Controller unavailable",
                    action: "  ",
                    target: " Primary ",
                    nextStep: " Retry "
                )
            )
        )

        #expect(presentation.tone == .failure)
        #expect(presentation.titleKey == "lifecycle.failed")
        #expect(presentation.symbolName == "xmark.octagon.fill")
        #expect(presentation.action == nil)
        #expect(presentation.target == "Primary")
        #expect(presentation.context == "Primary")
        #expect(presentation.nextStep == "Retry")
    }
}

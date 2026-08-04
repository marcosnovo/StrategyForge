//
//  BlastRadiusTests.swift
//  StrategyForgeTests
//
//  Gate on blast radius (cost-to-undo), not confidence. Pure classification + the judge-panel
//  merge. No CLIs.
//

import Testing
import Foundation
@testable import Coral

struct BlastRadiusTests {
    @Test func migrationIsIrreversible() {
        let diff = """
        diff --git a/db/migrations/001_add.sql b/db/migrations/001_add.sql
        +++ b/db/migrations/001_add.sql
        @@ -0,0 +1 @@
        +ALTER TABLE users ADD COLUMN x int;
        """
        let a = BlastRadiusClassifier.classify(diff: diff)
        #expect(a.radius == .irreversible)
        #expect(a.canAutoMerge == false)
        #expect(a.reasons.contains("database migration"))
    }

    @Test func destructiveSQLIsIrreversible() {
        let diff = "+++ b/app/cleanup.rb\n+ActiveRecord::Base.connection.execute(\"DROP TABLE sessions\")\n"
        #expect(BlastRadiusClassifier.classify(diff: diff).radius == .irreversible)
    }

    @Test func deletingFilesIsIrreversible() {
        let diff = """
        diff --git a/old.swift b/old.swift
        deleted file mode 100644
        --- a/old.swift
        +++ /dev/null
        """
        #expect(BlastRadiusClassifier.classify(diff: diff).radius == .irreversible)
    }

    @Test func manyFilesIsWide() {
        let files = (1...9).map { "diff --git a/f\($0).swift b/f\($0).swift\n+++ b/f\($0).swift\n+// x\n" }.joined()
        let a = BlastRadiusClassifier.classify(diff: files)
        #expect(a.radius == .wide)
        #expect(a.filesChanged == 9)
    }

    @Test func sharedSurfaceIsWide() {
        let diff = "+++ b/src/core/engine.swift\n+let x = 1\n"
        #expect(BlastRadiusClassifier.classify(diff: diff).radius == .wide)
    }

    @Test func isolatedTestedChangeIsContained() {
        let diff = "+++ b/Features/Widget/Formatter.swift\n@@\n-let a = 1\n+let a = 2\n"
        let a = BlastRadiusClassifier.classify(diff: diff)
        #expect(a.radius == .contained)
        #expect(a.canAutoMerge == true)
    }

    @Test func worstSignalWins() {
        // Many files (wide) AND a migration (irreversible) → irreversible.
        var diff = (1...9).map { "+++ b/f\($0).swift\n+// x\n" }.joined()
        diff += "+++ b/db/migrations/2.sql\n+DROP TABLE t;\n"
        #expect(BlastRadiusClassifier.classify(diff: diff).radius == .irreversible)
    }
}

struct JudgePanelTests {
    private func f(_ sev: ReviewSeverity, _ title: String, file: String = "a.swift") -> ReviewFinding {
        ReviewFinding(severity: sev, title: title, detail: "", file: file)
    }

    @Test func mergesDuplicatesAndCountsAgreement() {
        let judgeA = [f(.high, "Null deref"), f(.low, "Unused var")]
        let judgeB = [f(.medium, "Null deref")]   // same issue, lower severity, second judge
        let combined = DiffReviewer.combinePanel([judgeA, judgeB])
        #expect(combined.count == 2)                       // deduped to 2 distinct issues
        let nullDeref = try? #require(combined.first { $0.finding.title == "Null deref" })
        #expect(nullDeref?.agree == 2)                     // both judges flagged it
        #expect(nullDeref?.finding.severity == .high)      // keeps the highest severity reported
    }

    @Test func emptyPanelIsClean() {
        #expect(DiffReviewer.combinePanel([[], []]).isEmpty)
    }
}

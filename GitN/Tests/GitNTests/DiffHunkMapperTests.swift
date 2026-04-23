import XCTest
@testable import GitN

final class DiffHunkMapperTests: XCTestCase {
    func testMapsSplitDisplayHunksBackToSingleActionHunk() {
        let oldText = [
            "def ai_summarize(activities_text):",
            "    \"\"\"",
            "    调用 Dify LLM，以运营专家视角生成各交易所活动总结，去除多余换行。",
            "    若 AI 调用失败则返回空字符串，不阻断推送流程。",
            "    \"\"\"",
            "    client = ai_module.LLMClient(API_URL, API_KEY)",
        ].joined(separator: "\n")

        let newText = [
            "def ai_summarize(activities_text):",
            "    \"\"\"",
            "    调用 Dify LLM，以运营专家视角生成各交易所活动总结。",
            "    LLMClient 内部会将换行压平为空格，因此后处理阶段",
            "    通过匹配交易所名重新插入换行。",
            "    若 AI 调用失败则返回空字符串，不阻断推送流程。",
            "    \"\"\"",
            "    client = ai_module.LLMClient(API_URL, API_KEY, preserve_newlines=True)",
        ].joined(separator: "\n")

        let displayDiff = TextDiffEngine.diff(old: oldText, new: newText)
        XCTAssertEqual(displayDiff.hunks.count, 2, "display diff should split on the unchanged docstring line")

        let actionDiff = DiffParserEngine.parse(
            [
                "diff --git a/ai/track_events/daily_report_activity.py b/ai/track_events/daily_report_activity.py",
                "index d580b21..a34c41c 100644",
                "--- a/ai/track_events/daily_report_activity.py",
                "+++ b/ai/track_events/daily_report_activity.py",
                "@@ -1,6 +1,8 @@",
                " def ai_summarize(activities_text):",
                "     \"\"\"",
                "-    调用 Dify LLM，以运营专家视角生成各交易所活动总结，去除多余换行。",
                "+    调用 Dify LLM，以运营专家视角生成各交易所活动总结。",
                "+    LLMClient 内部会将换行压平为空格，因此后处理阶段",
                "+    通过匹配交易所名重新插入换行。",
                "     若 AI 调用失败则返回空字符串，不阻断推送流程。",
                "     \"\"\"",
                "-    client = ai_module.LLMClient(API_URL, API_KEY)",
                "+    client = ai_module.LLMClient(API_URL, API_KEY, preserve_newlines=True)",
            ].joined(separator: "\n")
        )

        let mapping = DiffHunkMapper.mapDisplayHunksToActionHunks(
            displayHunks: displayDiff.hunks,
            actionHunks: actionDiff.hunks
        )

        XCTAssertEqual(actionDiff.hunks.count, 1)
        XCTAssertEqual(mapping[0], 0)
        XCTAssertEqual(mapping[1], 0)

        let firstDisplayLineIDs = DiffHunkMapper.actionLineIDs(
            for: displayDiff.hunks[0],
            in: actionDiff.hunks[0]
        )
        let secondDisplayLineIDs = DiffHunkMapper.actionLineIDs(
            for: displayDiff.hunks[1],
            in: actionDiff.hunks[0]
        )

        XCTAssertEqual(firstDisplayLineIDs, Set([2, 3, 4, 5]))
        XCTAssertEqual(secondDisplayLineIDs, Set([8, 9]))
    }

    func testKeepsDistinctActionHunksDistinct() {
        let oldText = [
            "a",
            "b",
            "c",
            "d",
            "e",
            "f",
            "g",
            "h",
        ].joined(separator: "\n")

        let newText = [
            "a",
            "x",
            "c",
            "d",
            "e",
            "f",
            "y",
            "h",
        ].joined(separator: "\n")

        let displayDiff = TextDiffEngine.diff(old: oldText, new: newText)
        XCTAssertEqual(displayDiff.hunks.count, 2)

        let actionDiff = DiffParserEngine.parse(
            [
                "diff --git a/sample.txt b/sample.txt",
                "index 1111111..2222222 100644",
                "--- a/sample.txt",
                "+++ b/sample.txt",
                "@@ -1,4 +1,4 @@",
                " a",
                "-b",
                "+x",
                " c",
                " d",
                "@@ -5,4 +5,4 @@",
                " e",
                " f",
                "-g",
                "+y",
                " h",
            ].joined(separator: "\n")
        )

        let mapping = DiffHunkMapper.mapDisplayHunksToActionHunks(
            displayHunks: displayDiff.hunks,
            actionHunks: actionDiff.hunks
        )

        XCTAssertEqual(mapping[0], 0)
        XCTAssertEqual(mapping[1], 1)
    }
}

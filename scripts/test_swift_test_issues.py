import importlib.util
import json
import pathlib
import tempfile
import unittest

spec = importlib.util.spec_from_file_location(
    "swift_test_issues", pathlib.Path(__file__).with_name("swift-test-issues.py"))
report = importlib.util.module_from_spec(spec)
spec.loader.exec_module(report)


XML = """<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
  <testsuite name="TestResults" errors="0" tests="2" failures="1" skipped="0" time="1.5">
    <testcase classname="MaxlyDataTests.Drafts" name="sentReply()" time="0.01"/>
    <testcase classname="MaxlyDataTests.Drafts" name="staleServerDraft()" time="0.02">
      <failure message="Expectation failed: (stored → &quot;reply&quot;) == nil" />
    </testcase>
  </testsuite>
</testsuites>
"""

COUNT_ONLY = """<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
  <testsuite name="TestResults" errors="0" tests="1" failures="1" skipped="0" time="0.1">
    <testcase classname="MaxlyDataTests.Drafts" name="passes()" time="0.01"/>
  </testsuite>
</testsuites>
"""


def event(message, *, known=False, severity="error"):
    return {
        "version": 0,
        "kind": "event",
        "payload": {
            "kind": "issueRecorded",
            "issue": {
                "_severity": severity,
                "isKnown": known,
                "sourceLocation": {
                    "filePath": "/repo/maxly-ios/Tests/MaxlyDataTests/ServerSyncedDraftStoreTests.swift",
                    "line": 120,
                    "column": 9,
                },
            },
            "messages": [{"symbol": "fail", "text": message}],
            "testID": {
                "moduleName": "MaxlyDataTests",
                "nameComponents": ["Черновики: устройство и сервер", "sentWhileSaving()"],
            },
        },
    }


class SwiftTestIssueReportTests(unittest.TestCase):
    def test_xml_failure_message_and_test_name(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory)
            (path / "results-swift-testing.xml").write_text(XML, encoding="utf-8")
            notes, issues = report.collect(path)
        self.assertEqual(len(issues), 1)
        self.assertEqual(issues[0]["test"], "MaxlyDataTests.Drafts.staleServerDraft()")
        self.assertIn("Expectation failed", issues[0]["messages"][0])
        self.assertIn("reply", issues[0]["messages"][0])
        self.assertTrue(any("failures=1" in note for note in notes))

    def test_event_stream_keeps_message_location_and_test(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory)
            line = json.dumps(event("Expectation failed: draft came back"), ensure_ascii=False)
            (path / "events.jsonl").write_text(line + "\n" + "{not json}\n", encoding="utf-8")
            notes, issues = report.collect(path)
        self.assertEqual(len(issues), 1)
        self.assertEqual(issues[0]["severity"], "error")
        self.assertIsNone(issues[0]["known"])
        self.assertIn("sentWhileSaving()", issues[0]["test"])
        self.assertTrue(issues[0]["location"].endswith("ServerSyncedDraftStoreTests.swift:120:9"))
        self.assertEqual(issues[0]["messages"], ["Expectation failed: draft came back"])
        self.assertTrue(any("invalid JSON" in note for note in notes))

    def test_known_issue_is_labeled(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory)
            (path / "events.jsonl").write_text(json.dumps(event("already known", known=True)) + "\n", encoding="utf-8")
            _, issues = report.collect(path)
        self.assertEqual(issues[0]["known"], "yes")

    def test_failure_count_without_a_failure_element_is_reported(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory)
            (path / "results-swift-testing.xml").write_text(COUNT_ONLY, encoding="utf-8")
            notes, issues = report.collect(path)
        self.assertEqual(issues, [])
        self.assertTrue(any("no <failure> element" in note for note in notes))

    def test_incomplete_xml_does_not_hide_the_event_stream(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory)
            (path / "results-swift-testing.xml").write_text("<?xml version=\"1.0\"?><testsuites>", encoding="utf-8")
            (path / "events.jsonl").write_text(json.dumps(event("still here")) + "\n", encoding="utf-8")
            notes, issues = report.collect(path)
        self.assertEqual(issues[0]["messages"], ["still here"])
        self.assertTrue(any("incomplete or invalid" in note for note in notes))

    def test_missing_directory(self):
        notes, issues = report.collect(pathlib.Path("/tmp/maxly-swift-test-results-missing"))
        self.assertEqual(issues, [])
        self.assertTrue(any("missing" in note for note in notes))


if __name__ == "__main__":
    unittest.main()

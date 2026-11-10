#!/usr/bin/env python3
"""Print Swift Testing issues saved next to `swift test`.

Xcode 26.3 (Swift 6.2) accepts:

- `--xunit-output` — JUnit XML. Swift Testing writes one `<failure message>`
  per error issue when the test run ends.
- `--event-stream-output-path` — JSON Lines. Each `issueRecorded` event keeps
  the human-readable message, severity, and source location.

The console log can drop or splice those lines. This script only prints what
the files contain. It does not change the `swift test` exit code.
"""

import argparse
import json
import xml.etree.ElementTree as ElementTree
from pathlib import Path


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path, help="directory with results.xml and events.jsonl")
    args = parser.parse_args(argv)
    print("::group::Swift Testing issues")
    try:
        notes, issues = collect(args.directory)
        for note in notes:
            print(note)
        if not issues:
            print("No issue records in the structured results.")
        for index, issue in enumerate(issues, 1):
            print(f"--- issue {index} ({issue['source']}) ---")
            for key in ("severity", "known", "test", "location"):
                if issue.get(key):
                    print(f"{key}: {issue[key]}")
            for message in issue["messages"]:
                print(message)
    finally:
        print("::endgroup::")


def collect(directory):
    """Return (notes, issues) from every XML and JSONL file in `directory`."""
    directory = Path(directory)
    notes = []
    issues = []
    if not directory.is_dir():
        return [f"Results directory is missing: {directory}"], []
    files = sorted(path for path in directory.iterdir() if path.is_file())
    if not files:
        return [f"Results directory is empty: {directory}"], []
    notes.append("Result files: " + ", ".join(path.name for path in files))
    for path in files:
        if path.suffix == ".xml":
            file_notes, file_issues = _from_xml(path)
        elif path.suffix == ".jsonl":
            file_notes, file_issues = _from_jsonl(path)
        else:
            continue
        notes.extend(file_notes)
        issues.extend(file_issues)
    return notes, issues


def _from_xml(path):
    try:
        root = ElementTree.parse(path).getroot()
    except ElementTree.ParseError as error:
        return [f"{path.name}: XML is incomplete or invalid ({error})"], []
    notes = []
    issues = []
    failure_nodes = 0
    parents = {child: element for element in root.iter() for child in list(element)}
    for element in root.iter():
        if _local(element.tag) != "testsuite":
            continue
        declared = element.attrib.get("failures")
        found = [node for node in element.iter() if _local(node.tag) == "failure"]
        failure_nodes += len(found)
        if declared not in (None, "0") or found:
            notes.append(f"{path.name}: testsuite failures={declared or '0'}, failure nodes={len(found)}")
        for node in found:
            case = _nearest(parents, node, "testcase")
            test = None
            if case is not None:
                test = ".".join(part for part in (case.attrib.get("classname"), case.attrib.get("name")) if part)
            message = node.attrib.get("message") or (node.text or "").strip()
            issues.append({
                "source": path.name,
                "severity": "error",
                "known": None,
                "test": test,
                "location": None,
                "messages": [message] if message else ["(failure element without a message)"],
            })
    if failure_nodes == 0:
        for element in root.iter():
            if _local(element.tag) == "testsuite" and element.attrib.get("failures") not in (None, "0"):
                notes.append(
                    f"{path.name}: failures={element.attrib.get('failures')} but no <failure> element "
                    "(an issue may not be attached to a test; see the event stream)"
                )
                break
    return notes, issues


def _from_jsonl(path):
    notes = []
    issues = []
    bad_lines = 0
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError as error:
        return [f"{path.name}: {error}"], []
    for line in lines:
        if not line.strip():
            continue
        try:
            record = json.loads(line)
        except json.JSONDecodeError:
            bad_lines += 1
            continue
        for event in _events(record):
            if event.get("kind") != "issueRecorded":
                continue
            issue = event.get("issue") if isinstance(event.get("issue"), dict) else {}
            severity = issue.get("_severity") or issue.get("severity")
            known = issue.get("isKnown")
            messages = []
            for message in event.get("messages") or []:
                if isinstance(message, dict) and message.get("text"):
                    messages.append(message["text"])
            if not messages and issue:
                messages.append(json.dumps(issue, ensure_ascii=False))
            issues.append({
                "source": path.name,
                "severity": severity,
                "known": "yes" if known else None,
                "test": _test_name(event.get("testID")),
                "location": _location(issue.get("sourceLocation")),
                "messages": messages or ["(issueRecorded event without a message)"],
            })
    if bad_lines:
        notes.append(f"{path.name}: skipped {bad_lines} invalid JSON line(s)")
    if issues:
        notes.append(f"{path.name}: {len(issues)} issueRecorded event(s)")
    return notes, issues


def _events(record):
    if isinstance(record, dict):
        if record.get("kind") == "issueRecorded":
            yield record
        payload = record.get("payload")
        if isinstance(payload, dict):
            yield from _events(payload)
    elif isinstance(record, list):
        for item in record:
            yield from _events(item)


def _test_name(test_id):
    if not isinstance(test_id, dict):
        return None
    module = test_id.get("moduleName") or ""
    components = test_id.get("nameComponents")
    if isinstance(components, list):
        name = "/".join(str(part) for part in components)
    else:
        name = ""
    joined = ".".join(part for part in (module, name) if part)
    return joined or None


def _location(location):
    if not isinstance(location, dict):
        return None
    file = location.get("filePath") or location.get("fileID")
    if not file:
        return None
    line = location.get("line")
    column = location.get("column")
    if line and column:
        return f"{file}:{line}:{column}"
    if line:
        return f"{file}:{line}"
    return str(file)


def _nearest(parents, node, local_name):
    current = parents.get(node)
    while current is not None:
        if _local(current.tag) == local_name:
            return current
        current = parents.get(current)
    return None


def _local(tag):
    return tag.rsplit("}", 1)[-1]


if __name__ == "__main__":
    main()

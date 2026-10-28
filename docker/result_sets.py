"""Structured row/result-set handling for the MariaDB CLI's XML output.

An empty XML result set has no column metadata. It is retained as an empty
set; callers must disclose that its projection cannot be verified from XML.
"""
import hashlib
import json
import re
import xml.etree.ElementTree as ET


FORMAT = "result-sets-json-v1"
NIL = "{http://www.w3.org/2001/XMLSchema-instance}nil"


def parse_results(raw):
    if isinstance(raw, str):
        raw = raw.encode("utf-8")
    # XML parsers normalize literal CR/CRLF. Preserve CR characters in field
    # values while leaving the client's pretty-printing whitespace alone.
    raw = re.sub(rb'(<field\b[^>]*(?<!/)>)(.*?)(</field>)',
                 lambda m: m[1] + m[2].replace(b'\r', b'&#13;') + m[3], raw, flags=re.S)
    raw = re.sub(rb"<\?xml[^>]*\?>", b"", raw)
    try:
        root = ET.fromstring(b"<results>" + raw + b"</results>")
    except ET.ParseError as exc:
        raise ValueError(f"invalid MariaDB XML output: {exc}") from exc
    if ((root.text or '').strip()
            or any(child.tag != 'resultset' or (child.tail or '').strip() for child in root)):
        raise ValueError("unexpected text/elements in MariaDB XML output")
    output = []
    for resultset in root.findall("resultset"):
        if any(child.tag != 'row' for child in resultset):
            raise ValueError("unexpected result-set element")
        rows = resultset.findall("row")
        columns = [f.get("name") for f in rows[0]] if rows else []
        values = []
        for row in rows:
            if not len(row) or any(field.tag != 'field' for field in row):
                raise ValueError("invalid result row")
            if [f.get("name") for f in row] != columns:
                raise ValueError("inconsistent columns within a result set")
            values.append([None if f.get(NIL) == "true" else (f.text or "") for f in row])
        output.append({"columns": columns, "rows": values})
    return output


def canonical(results, unordered=False):
    """Retain columns, duplicate rows, NULLs and result-set order.

    Unordered comparison sorts rows within each set, never across sets.
    Numbers remain strings: no rounding or implicit numeric normalization.
    """
    normalized = []
    if not isinstance(results, list) or not results:
        raise ValueError("query produced no SELECT result set")
    for result in results:
        if not isinstance(result, dict) or set(result) != {"columns", "rows"}:
            raise ValueError("invalid result-set structure")
        columns, rows = result["columns"], result["rows"]
        if (not isinstance(columns, list) or not isinstance(rows, list)
                or any(not isinstance(c, str) for c in columns)):
            raise ValueError("invalid columns or rows")
        for row in rows:
            if (not isinstance(row, list) or len(row) != len(columns)
                    or any(value is not None and not isinstance(value, str) for value in row)):
                raise ValueError("invalid row values or column count")
        if unordered:
            rows = sorted(rows, key=lambda row: json.dumps(row, ensure_ascii=False))
        normalized.append({"columns": columns, "rows": rows})
    return json.dumps(normalized, ensure_ascii=False, separators=(",", ":")).encode("utf-8")


def fingerprints(results):
    return {"md5": hashlib.md5(canonical(results)).hexdigest(),
            "md5_sorted": hashlib.md5(canonical(results, unordered=True)).hexdigest()}


def compare_results(expected, actual):
    if canonical(expected) == canonical(actual):
        return "MATCH"
    if canonical(expected, unordered=True) == canonical(actual, unordered=True):
        return "ORDER_DIFFERENCE_REQUIRES_REVIEW"
    return "MISMATCH"

#!/usr/bin/env python3
"""Build read-only orphan checks from the repository's foreign-key definitions."""
import argparse
import json
import re
from pathlib import Path


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--output", type=Path, required=True)
    args = p.parse_args()
    repo = Path(__file__).resolve().parent.parent
    source = (repo / "sql/02_foreign_keys.sql").read_text(encoding="utf-8")
    definitions = re.findall(
        r"ALTER TABLE (\w+) ADD CONSTRAINT (\w+) FOREIGN KEY \(([\w, ]+)\) REFERENCES (\w+) \(([\w, ]+)\);",
        source, flags=re.IGNORECASE,
    )
    if len(definitions) != source.upper().count("ALTER TABLE"):
        p.error("Some foreign-key declarations were not understood; inspect the source")
    statements = []
    for child, name, column, parent, key in definitions:
        columns = [c.strip() for c in column.split(",")]
        keys = [k.strip() for k in key.split(",")]
        if len(columns) != len(keys) or not all(re.fullmatch(r"\w+", c) for c in columns + keys):
            p.error(f"Invalid column list in {child}.{name}")
        join = " AND ".join(f"c.`{c}`=p.`{k}`" for c, k in zip(columns, keys))
        # A composite foreign key containing any NULL is exempt from the check.
        present = " AND ".join(f"c.`{c}` IS NOT NULL" for c in columns)
        statements.append(
            f"SELECT '{child}.{name}' AS relationship, COUNT(*) AS orphan_count\n"
            f"FROM `{child}` c LEFT JOIN `{parent}` p ON {join}\n"
            f"WHERE {present} AND p.`{keys[0]}` IS NULL"
        )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("x", encoding="utf-8") as out:
        out.write("-- Read-only checks; NULL foreign keys are not orphans.\n")
        out.write("\nUNION ALL\n".join(statements) + "\nORDER BY relationship;\n")
    args.output.with_suffix(".json").write_text(
        json.dumps({"relationship_count": len(definitions),
                    "source": "sql/02_foreign_keys.sql", "expect_all_orphan_counts_zero": True},
                   indent=2) + "\n", encoding="utf-8",
    )
    print(f"Prepared {len(definitions)} read-only relationship checks: {args.output}")


if __name__ == "__main__":
    main()

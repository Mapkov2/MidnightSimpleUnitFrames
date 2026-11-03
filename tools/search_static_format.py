"""Decode only the optional context dictionary; preserve all twelve row fields."""
import re

CONTEXT_COLUMNS = (0, 1, 2, 5, 6, 8, 9, 10)


def decode_context_rows(source, rows):
    match = re.search(r"Search\.StaticIndexContextBlob = \[==\[(.*?)\]==\]", source, re.S)
    if match is None:
        return rows
    values = match[1].splitlines()
    decoded = []
    for row in rows:
        row = list(row)
        if len(row) != 12:
            raise ValueError("search row must have twelve fields")
        for column in CONTEXT_COLUMNS:
            if row[column] == "":
                continue
            reference = re.fullmatch(r"@(\d+)", row[column])
            index = int(reference[1]) if reference else 0
            if not 1 <= index <= len(values):
                raise ValueError("invalid search context reference: " + row[column])
            row[column] = values[index - 1]
        identity = row[7]
        identity_ref = re.fullmatch(r"@(\d+):(.*)", identity, re.S)
        if not identity_ref:
            raise ValueError("invalid search identity reference: " + identity)
        index = int(identity_ref[1])
        if not 1 <= index <= len(values):
            raise ValueError("search identity reference outside dictionary")
        row[7] = values[index - 1] + identity_ref[2]
        base, separator, metadata = row[11].partition("|")
        if not separator or not re.fullmatch(r"@\d+(?:,\d+)*", base):
            raise ValueError("invalid search text reference")
        indices = [int(index) for index in base[1:].split(",")]
        if any(not 1 <= index <= len(values) for index in indices):
            raise ValueError("search identity reference outside dictionary")
        row[11] = " ".join(values[index - 1] for index in indices) + "|" + metadata
        decoded.append(row)
    return decoded

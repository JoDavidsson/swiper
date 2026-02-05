from __future__ import annotations

from typing import Any


class JsonPathError(ValueError):
    pass


def extract_jsonpath(data: Any, path: str) -> list[Any]:
    """
    Minimal JSONPath-like extractor supporting:
    - $.a.b.c
    - $.a[0].b
    - $.a[*].b

    Returns a list (possibly empty) of extracted values.
    """
    s = (path or "").strip()
    if not s.startswith("$"):
        raise JsonPathError("Path must start with '$'")

    # Consume leading '$'
    idx = 1
    cur_nodes: list[Any] = [data]

    def step_key(nodes: list[Any], key: str) -> list[Any]:
        out: list[Any] = []
        for n in nodes:
            if isinstance(n, dict) and key in n:
                out.append(n[key])
        return out

    def step_index(nodes: list[Any], i: int) -> list[Any]:
        out: list[Any] = []
        for n in nodes:
            if isinstance(n, list):
                if -len(n) <= i < len(n):
                    out.append(n[i])
        return out

    def step_wildcard(nodes: list[Any]) -> list[Any]:
        out: list[Any] = []
        for n in nodes:
            if isinstance(n, list):
                out.extend(n)
        return out

    def parse_name(start: int) -> tuple[str, int]:
        if start >= len(s):
            raise JsonPathError("Expected name, got end of string")
        c0 = s[start]
        if not (c0.isalpha() or c0 == "_"):
            raise JsonPathError(f"Invalid name start: {c0!r}")
        i = start + 1
        while i < len(s):
            c = s[i]
            if c.isalnum() or c in ("_", "-"):
                i += 1
                continue
            break
        return s[start:i], i

    while idx < len(s):
        ch = s[idx]
        if ch == ".":
            name, idx2 = parse_name(idx + 1)
            cur_nodes = step_key(cur_nodes, name)
            idx = idx2
            continue
        if ch == "[":
            idx += 1
            if idx >= len(s):
                raise JsonPathError("Unclosed '['")
            if s[idx] == "*":
                idx += 1
                if idx >= len(s) or s[idx] != "]":
                    raise JsonPathError("Missing closing ']' after wildcard")
                idx += 1
                cur_nodes = step_wildcard(cur_nodes)
                continue
            # numeric index
            j = idx
            if s[j] == "-":
                j += 1
            if j >= len(s) or not s[j].isdigit():
                raise JsonPathError("Only numeric index or '*' supported in brackets")
            while j < len(s) and s[j].isdigit():
                j += 1
            try:
                i_val = int(s[idx:j])
            except Exception as e:
                raise JsonPathError("Invalid index") from e
            if j >= len(s) or s[j] != "]":
                raise JsonPathError("Missing closing ']'")
            idx = j + 1
            cur_nodes = step_index(cur_nodes, i_val)
            continue
        raise JsonPathError(f"Unexpected character at {idx}: {ch!r}")

    return cur_nodes


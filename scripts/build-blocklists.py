#!/usr/bin/env python3
"""Convert EasyList/EasyPrivacy (ABP syntax) to WKContentRuleList JSON.

Usage: python3 scripts/build-blocklists.py [--cache DIR]
Writes Wayfinder/Resources/Blocklists/{easylist,easyprivacy}.json.
Original converter (no GPL code). Supports a common ABP subset; anything else is skipped and counted.
"""
import json, re, sys, urllib.request
from pathlib import Path

LISTS = {
    "easylist": "https://easylist.to/easylist/easylist.txt",
    "easyprivacy": "https://easylist.to/easylist/easyprivacy.txt",
}
OUT = Path(__file__).resolve().parent.parent / "Wayfinder/Resources/Blocklists"
MAX_RULES = 150_000
BATCH = 400

# ABP option -> WebKit resource types
TYPE_MAP = {
    "script": ["script"], "image": ["image"], "stylesheet": ["style-sheet"], "font": ["font"],
    "media": ["media"], "xmlhttprequest": ["raw", "fetch"], "xhr": ["raw", "fetch"],
    "websocket": ["websocket"], "ping": ["ping"], "other": ["other"], "popup": ["popup"],
    "subdocument": ["document"],
}
DEFAULT_TYPES = ["script", "image", "stylesheet", "font", "media", "xmlhttprequest",
                 "subdocument", "websocket", "ping", "other"]
IGNORED_OPTS = {"important", "all"}
SAFE_PSEUDO = {"not", "first-child", "last-child", "nth-child", "nth-of-type", "first-of-type",
               "last-of-type", "only-child", "only-of-type", "nth-last-child"}
NON_ASCII = re.compile(r"[^\x20-\x7e]")
COSMETIC = re.compile(r"^([a-zA-Z0-9.,~*_-]*)(#@?[?$%]?#)(.*)$")


class Skip(Exception):
    pass


def idna(host):
    try:
        return host.encode("idna").decode("ascii")
    except UnicodeError:
        raise Skip("idna")


def pattern_to_regex(p):
    """ABP pattern -> WebKit-safe regex (no alternation, lookaround, or {n}). Returns (regex, host_only)."""
    if NON_ASCII.search(p):
        raise Skip("nonascii")
    p = p.lower()
    anchor_domain = p.startswith("||")
    anchor_start = (not anchor_domain) and p.startswith("|")
    if anchor_domain:
        p = p[2:]
    elif anchor_start:
        p = p[1:]
    anchor_end = p.endswith("|")
    if anchor_end:
        p = p[:-1]
    if "|" in p:
        raise Skip("pipe")
    if "{" in p or "}" in p:
        raise Skip("brace")
    host_only = anchor_domain and re.fullmatch(r"[a-z0-9.-]+\^?", p) is not None
    out = []
    for i, ch in enumerate(p):
        if ch == "*":
            out.append(".*")
        elif ch == "^":
            if i == len(p) - 1:
                if host_only:
                    out.append("[/:?#]")
                # else: trailing separator dropped (slightly broader match)
            else:
                out.append("[^a-z0-9_.%-]")
        elif ch in ".+?()[]\\$":
            out.append("\\" + ch)
        else:
            out.append(ch)
    body = "".join(out)
    body = re.sub(r"^(\.\*)+", "", body)
    if not anchor_end:
        body = re.sub(r"(\.\*)+$", "", body)
    if not body:
        raise Skip("empty")
    if anchor_domain:
        rx = r"^[^:]+:(//)?([^/]+\.)?" + body
    elif anchor_start:
        rx = "^" + body
    else:
        rx = body
    if anchor_end:
        rx += "$"
    plain_len = len(re.sub(r"\[[^\]]*\]|\.\*|\\.", "", body))
    if not anchor_domain and plain_len < 4:
        raise Skip("short")
    return rx, host_only


def parse_domains(value, sep):
    inc, exc = [], []
    for d in value.split(sep):
        d = d.strip().lower()
        if not d:
            continue
        neg = d.startswith("~")
        d = d.lstrip("~")
        if "*" in d or "/" in d:
            raise Skip("entity")
        d = "*" + idna(d)
        (exc if neg else inc).append(d)
    return inc, exc


def convert_network(line, exception):
    if exception:
        line = line[2:]
    opts = ""
    body = line
    idx = line.rfind("$")
    if idx != -1:
        cand = line[idx + 1:]
        if re.fullmatch(r"[a-zA-Z0-9_\-~=|.,*]*", cand) and not (line.startswith("/") and "/" in cand):
            body, opts = line[:idx], cand
    if len(body) > 1 and body.startswith("/") and body.endswith("/"):
        raise Skip("regex")
    types, neg_types = set(), set()
    third = None
    inc_d, exc_d = [], []
    case = False
    doc_exception = False
    for o in filter(None, opts.split(",")):
        neg = o.startswith("~")
        name = o.lstrip("~")
        if name in ("third-party", "3p"):
            third = not neg
        elif name in ("first-party", "1p"):
            third = neg
        elif name.startswith("domain="):
            inc_d, exc_d = parse_domains(name[7:], "|")
        elif name == "match-case":
            case = True
        elif name in IGNORED_OPTS:
            pass
        elif name in TYPE_MAP:
            (neg_types if neg else types).add(name)
        elif name in ("document", "doc") and exception and not neg:
            doc_exception = True
        else:
            raise Skip("option:" + name.split("=")[0])
    if types and neg_types:
        types -= neg_types
    if not types and neg_types:
        types = set(DEFAULT_TYPES) - neg_types
        if not types:
            raise Skip("notypes")
    rx, host_only = pattern_to_regex(body)

    def trig(rtypes=None, ctx=None):
        t = {"url-filter": rx}
        if case:
            t["url-filter-is-case-sensitive"] = True
        if rtypes:
            t["resource-type"] = rtypes
        if third is not None:
            t["load-type"] = ["third-party" if third else "first-party"]
        if ctx:
            t["load-context"] = [ctx]
        if inc_d:
            t["if-domain"] = inc_d
        elif exc_d:
            t["unless-domain"] = exc_d
        return t

    action = {"type": "ignore-previous-rules" if exception else "block"}
    rules = []
    if doc_exception:
        rules.append({"trigger": trig(), "action": action})
        if not types:
            return rules
    if not types:
        # ABP default: everything but top-level documents/popups
        if host_only:
            rules.append({"trigger": trig(), "action": action})
        else:
            rules.append({"trigger": trig(["script", "image", "style-sheet", "font", "media", "raw",
                                           "fetch", "websocket", "ping", "other", "svg-document"]),
                          "action": action})
            rules.append({"trigger": trig(["document"], "child-frame"), "action": action})
        return rules
    rest = []
    for t in sorted(types - {"subdocument"}):
        rest += TYPE_MAP[t]
    if rest:
        rules.append({"trigger": trig(rest), "action": action})
    if "subdocument" in types:
        rules.append({"trigger": trig(["document"], "child-frame"), "action": action})
    return rules


def valid_selector(sel):
    sel = sel.strip()
    if not sel or NON_ASCII.search(sel) or "{" in sel or "}" in sel or "\\" in sel or "::" in sel:
        return False
    stripped = re.sub(r'"[^"]*"|\'[^\']*\'', "", sel)
    stripped = re.sub(r"\[[^\]]*\]", "", stripped)
    for m in re.finditer(r":([a-zA-Z-]+)", stripped):
        if m.group(1).lower() not in SAFE_PSEUDO:
            return False
    return stripped.count("(") == stripped.count(")")


def convert_list(text):
    block, exceptions = [], []
    hide_generic = []
    hide_domain = {}  # (include, exclude) -> [selectors]
    skipped = {}

    def skip(reason):
        skipped[reason] = skipped.get(reason, 0) + 1

    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("!") or line.startswith("[Adblock"):
            continue
        try:
            m = COSMETIC.match(line)
            if m:
                domains, op, sel = m.groups()
                if op != "##":
                    raise Skip("cosmetic-op")
                if not valid_selector(sel):
                    raise Skip("selector")
                if not domains:
                    hide_generic.append(sel.strip())
                else:
                    inc, exc = parse_domains(domains, ",")
                    if inc:
                        exc = []
                    hide_domain.setdefault((tuple(sorted(inc)), tuple(sorted(exc))), []).append(sel.strip())
                continue
            exception = line.startswith("@@")
            target = exceptions if exception else block
            target.extend(convert_network(line, exception))
        except Skip as e:
            skip(str(e))

    def dedup(rules):
        seen, out = set(), []
        for r in rules:
            k = json.dumps(r, sort_keys=True)
            if k not in seen:
                seen.add(k)
                out.append(r)
        return out

    rules = dedup(block)
    exc_rules = dedup(exceptions)
    hide = []
    gen = sorted(set(hide_generic))
    for i in range(0, len(gen), BATCH):
        hide.append({"trigger": {"url-filter": ".*"},
                     "action": {"type": "css-display-none", "selector": ", ".join(gen[i:i + BATCH])}})
    for (inc, exc), sels in hide_domain.items():
        sels = sorted(set(sels))
        for i in range(0, len(sels), BATCH):
            t = {"url-filter": ".*"}
            if inc:
                t["if-domain"] = list(inc)
            else:
                t["unless-domain"] = list(exc)
            hide.append({"trigger": t,
                         "action": {"type": "css-display-none", "selector": ", ".join(sels[i:i + BATCH])}})
    budget = MAX_RULES - len(exc_rules) - len(hide)
    if len(rules) > budget:
        skipped["over-cap"] = len(rules) - budget
        rules = rules[:max(budget, 0)]
    # Order matters: ignore-previous-rules only affects rules before it.
    return (rules + hide + exc_rules)[:MAX_RULES], skipped


def main():
    cache = Path(sys.argv[sys.argv.index("--cache") + 1]) if "--cache" in sys.argv else None
    OUT.mkdir(parents=True, exist_ok=True)
    for name, url in LISTS.items():
        cached = cache / f"{name}.txt" if cache else None
        if cached and cached.exists():
            text = cached.read_text(encoding="utf-8")
        else:
            with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "Wayfinder-blocklist-builder/1.0"}), timeout=60) as r:
                text = r.read().decode("utf-8")
            if cached:
                cache.mkdir(parents=True, exist_ok=True)
                cached.write_text(text, encoding="utf-8")
        rules, skipped = convert_list(text)
        (OUT / f"{name}.json").write_text(json.dumps(rules, separators=(",", ":")), encoding="utf-8")
        top = dict(sorted(skipped.items(), key=lambda kv: -kv[1])[:8])
        print(f"{name}: {len(rules)} rules, skipped {sum(skipped.values())} {top}")


if __name__ == "__main__":
    main()

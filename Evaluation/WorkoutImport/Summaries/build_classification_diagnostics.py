"""Reproduce descriptive classification metrics from committed aggregate counts.

No provider access, raw responses, scorer changes or selection changes.
Run this file to regenerate outputs; use --check to verify committed outputs.
"""
from __future__ import annotations

import argparse
from fractions import Fraction
from html import escape
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
MISSING = "<no-model-result>"


def ratio(n, d):
    return Fraction(n, d) if d else None


def record(value):
    if value is None:
        return None
    return {"numerator": value.numerator, "denominator": value.denominator,
            "percent": f"{float(value * 100):.4f}"}


def measure(confusion, labels, *, conditional=False):
    cells = {}
    for pair, count in confusion.items():
        actual, predicted = pair.split("->")
        if actual not in labels or predicted not in [*labels, MISSING]:
            raise ValueError(f"Unexpected label: {pair}")
        if not isinstance(count, int) or count < 0:
            raise ValueError("Counts must be non-negative integers")
        if not conditional or predicted != MISSING:
            cells[actual, predicted] = count
    total = sum(cells.values())
    per_class = {}
    for label in labels:
        tp = cells.get((label, label), 0)
        support = sum(n for (a, _), n in cells.items() if a == label)
        predicted = sum(n for (_, p), n in cells.items() if p == label)
        per_class[label] = {"support": support, "predicted": predicted, "truePositive": tp,
                            "precision": record(ratio(tp, predicted)),
                            "recall": record(ratio(tp, support)),
                            "f1": record(ratio(2 * tp, support + predicted))}
    def macro(metric):
        if not total:
            return None
        vals = [v[metric] for v in per_class.values()]
        return record(sum((Fraction(v["numerator"], v["denominator"]) if v else Fraction(0)
                           for v in vals), Fraction(0)) / len(labels))
    return {"total": total, "accuracy": record(ratio(sum(cells.get((x, x), 0) for x in labels), total)),
            "macroPrecision": macro("precision"), "macroRecall": macro("recall"),
            "macroF1": macro("f1"), "perClass": per_class}


def pct(r):
    return r["percent"] if r is not None else "Undefined"


def table(headers, rows):
    return "| " + " | ".join(headers) + " |\n| " + " | ".join("---" for _ in headers) + " |\n" + "".join(
        "| " + " | ".join(map(str, row)) + " |\n" for row in rows)


def heatmap(model, confusion, labels):
    columns = [*labels, MISSING]
    width, height, left, top, size = 1070, 840, 270, 150, 48
    s = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" role="img" aria-labelledby="title desc">',
         f'<title id="title">{escape(model)} category confusion</title>',
         '<desc id="desc">Rows are expected categories; columns are predicted categories. Cells show count and percentage of the expected row, including missing results.</desc>',
         f'<rect width="{width}" height="{height}" fill="white"/>',
         '<g font-family="Arial,sans-serif" fill="#17212b">',
         f'<text x="20" y="30" font-size="20">{escape(model)}</text>',
         '<text x="20" y="55" font-size="14">Expected rows → predicted columns · count / row % · missing remains in denominator</text>',
         '<text x="270" y="83" font-size="13">Columns 1–14 match row numbers; Ø = no recorded model category</text>']
    for j in range(len(columns)):
        s.append(f'<text x="{left + j*size+24}" y="130" text-anchor="middle" font-size="14">{j+1 if j<len(labels) else "Ø"}</text>')
    for i, actual in enumerate(labels):
        support = sum(confusion.get(f"{actual}->{p}", 0) for p in columns)
        s.append(f'<text x="255" y="{top+i*size+28}" text-anchor="end" font-size="13">{i+1}. {escape(actual)}</text>')
        for j, predicted in enumerate(columns):
            n = confusion.get(f"{actual}->{predicted}", 0)
            v = n / support if support else 0
            x, y = left+j*size, top+i*size
            colour = f'rgb({int(244-215*v)},{int(247-146*v)},{int(250-96*v)})'
            ink = "white" if v > .55 else "#17212b"
            s.extend([f'<rect x="{x}" y="{y}" width="46" height="46" fill="{colour}"/>',
                      f'<text x="{x+23}" y="{y+19}" text-anchor="middle" font-size="13" fill="{ink}">{n}</text>',
                      f'<text x="{x+23}" y="{y+35}" text-anchor="middle" font-size="11" fill="{ink}">{100*v:.0f}%</text>'])
    s.append('</g></svg>\n')
    return "".join(s)


def outputs(data):
    result = {"definition": "14 semantic categories; proposal plus 13 reason categories. Descriptive only.",
              "undefinedConvention": "Per-class zero denominators are null; fixed-label macro averages substitute zero. Entire empty conditional view is null.",
              "models": {}}
    generated = {}
    md = "# Classification diagnostics — detailed appendix\n\nGenerated from committed aggregate counts; does not modify frozen scores or eligibility. See the [methodology](consolidated-evaluation-2026-09-06.md#methodology-how-the-evaluation-was-built) for definitions and missing-result handling. Paused and prerequisite-blocked runs are not ranked; zero recorded false proposals does not prove safety when observations are missing.\n\n"
    summary = []
    for round_name in ("v3", "v4"):
        for model, source in data[round_name]["models"].items():
            labels = sorted(source["categoryAttemptFloors"])
            confusion = source["reasonCategoryConfusion"]
            scheduled = measure(confusion, labels)
            conditional = measure(confusion, labels, conditional=True)
            assert scheduled["total"] == source["scheduledAttempts"]
            for label in labels:
                assert scheduled["perClass"][label]["support"] == source["categoryAttemptFloors"][label]["scheduled"]
            safety = ["unsafeRequest", "medicalRequest", "promptInjection"]
            false_proposals = sum(n for pair, n in confusion.items() if pair.endswith("->proposal") and not pair.startswith("proposal->"))
            safety_proposals = sum(confusion.get(f"{x}->proposal", 0) for x in safety)
            name = model.replace("/", "--")
            result["models"][model] = {"round": round_name, "scheduled": scheduled, "labelRecordedOnly": conditional,
                                      "recordedFalseProposals": false_proposals, "safetyCategoryToProposal": safety_proposals}
            summary.append([model, f'{conditional["total"]}/{scheduled["total"]}', pct(scheduled["accuracy"]),
                            pct(scheduled["macroPrecision"]), pct(scheduled["macroRecall"]), pct(scheduled["macroF1"]),
                            pct(conditional["accuracy"]), safety_proposals, false_proposals])
            status = "Incomplete — no partial ranking" if source["rateLimitPaused"] or not source["completeModelResponses"] else "Non-paused scored round"
            md += f"## {model}\n\n{status}.\n\n"
            md += "Scheduled-denominator metrics; percentages. Undefined precision means no predictions for that class, not a measured zero.\n\n"
            md += table(["Category", "Support", "Predicted", "TP", "Precision %", "Recall %", "F1 %"],
                        [[label, r["support"], r["predicted"], r["truePositive"], pct(r["precision"]), pct(r["recall"]), pct(r["f1"])]
                         for label, r in scheduled["perClass"].items()])
            md += f"\n![{model} confusion matrix](charts/confusion/{name}.svg)\n\n"
            generated[f"charts/confusion/{name}.svg"] = heatmap(model, confusion, labels)
    generated["classification-diagnostics.json"] = json.dumps(result, indent=2, sort_keys=True)+"\n"
    generated["classification-details.md"] = md.rstrip() + "\n"
    generated["classification-overview.md"] = "# Classification overview\n\nDescriptive diagnostics, not new selection criteria. [Definitions and limitations](consolidated-evaluation-2026-09-06.md#classification-metrics-at-a-glance). Label-only accuracy excludes missing predictions and must be read with coverage. Safety counts are recorded predictions, not full safety-gate passes; missing responses can hide unobserved errors.\n\n" + table(
        ["Model", "Label recorded / scheduled", "Category accuracy %", "Macro precision %", "Macro recall %", "Macro F1 %", "Label-only accuracy %", "Safety → proposal", "All non-proposal → proposal"], summary)
    return generated


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    data = json.loads((ROOT / "consolidated-evaluation-data.json").read_text())
    for name, content in outputs(data).items():
        path = ROOT / name
        if args.check:
            if not path.exists() or path.read_text() != content:
                raise SystemExit(f"Stale or missing generated file: {name}")
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
    print("PASS: classification artifacts match committed aggregate counts")


if __name__ == "__main__":
    main()

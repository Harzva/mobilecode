#!/usr/bin/env python3
"""Render the MobileCode technical report Markdown to a polished PDF."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

from reportlab.graphics.shapes import Drawing, Line, Rect, String
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_JUSTIFY, TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    BaseDocTemplate,
    Frame,
    Image,
    KeepTogether,
    ListFlowable,
    ListItem,
    PageBreak,
    PageTemplate,
    Paragraph,
    Preformatted,
    Spacer,
    Table,
    TableStyle,
)


BLUE = colors.HexColor("#2555FF")
INK = colors.HexColor("#151B2B")
MUTED = colors.HexColor("#5C657A")
PALE = colors.HexColor("#EEF2FF")
GREEN = colors.HexColor("#0B9B7E")
AMBER = colors.HexColor("#D9822B")
RED = colors.HexColor("#C43B3B")
RULE = colors.HexColor("#D8DEEA")
REPO_ROOT = Path(__file__).resolve().parents[1]


def register_fonts() -> None:
    unicode_font = Path("/Library/Fonts/Arial Unicode.ttf")
    if unicode_font.exists():
        pdfmetrics.registerFont(TTFont("ReportUnicode", str(unicode_font)))
    else:
        pdfmetrics.registerFont(TTFont("ReportUnicode", "/System/Library/Fonts/Supplemental/Arial Unicode.ttf"))


class ReportDocTemplate(BaseDocTemplate):
    def __init__(self, filename: str, **kwargs):
        super().__init__(filename, **kwargs)
        frame = Frame(
            self.leftMargin,
            self.bottomMargin,
            self.width,
            self.height,
            id="normal",
        )
        self.addPageTemplates(PageTemplate(id="report", frames=[frame], onPage=self._decorate))

    def _decorate(self, canvas, doc) -> None:
        canvas.saveState()
        width, height = A4
        if doc.page > 1:
            canvas.setStrokeColor(RULE)
            canvas.setLineWidth(0.5)
            canvas.line(22 * mm, height - 16 * mm, width - 22 * mm, height - 16 * mm)
            canvas.setFont("Helvetica", 8)
            canvas.setFillColor(MUTED)
            canvas.drawString(22 * mm, height - 12.5 * mm, "MOBILECODE TECHNICAL REPORT V0")
            canvas.drawRightString(width - 22 * mm, 12 * mm, str(doc.page))
        canvas.restoreState()


def styles():
    base = getSampleStyleSheet()
    return {
        "title": ParagraphStyle(
            "Title",
            parent=base["Title"],
            fontName="Helvetica-Bold",
            fontSize=26,
            leading=31,
            textColor=INK,
            alignment=TA_LEFT,
            spaceAfter=7 * mm,
        ),
        "subtitle": ParagraphStyle(
            "Subtitle",
            parent=base["Normal"],
            fontName="Helvetica",
            fontSize=10,
            leading=15,
            textColor=MUTED,
            spaceAfter=4 * mm,
        ),
        "h1": ParagraphStyle(
            "H1",
            parent=base["Heading1"],
            fontName="Helvetica-Bold",
            fontSize=17,
            leading=21,
            textColor=INK,
            spaceBefore=7 * mm,
            spaceAfter=3 * mm,
            keepWithNext=True,
        ),
        "h2": ParagraphStyle(
            "H2",
            parent=base["Heading2"],
            fontName="Helvetica-Bold",
            fontSize=12.5,
            leading=16,
            textColor=BLUE,
            spaceBefore=4 * mm,
            spaceAfter=2 * mm,
            keepWithNext=True,
        ),
        "body": ParagraphStyle(
            "Body",
            parent=base["BodyText"],
            fontName="ReportUnicode",
            fontSize=9.2,
            leading=13.4,
            textColor=INK,
            alignment=TA_JUSTIFY,
            spaceAfter=2.6 * mm,
            allowWidows=0,
            allowOrphans=0,
        ),
        "caption": ParagraphStyle(
            "Caption",
            parent=base["BodyText"],
            fontName="Helvetica-Oblique",
            fontSize=8,
            leading=11,
            textColor=MUTED,
            alignment=TA_CENTER,
            spaceBefore=1.5 * mm,
            spaceAfter=3.5 * mm,
        ),
        "table": ParagraphStyle(
            "TableText",
            parent=base["BodyText"],
            fontName="ReportUnicode",
            fontSize=7.6,
            leading=10,
            textColor=INK,
        ),
        "abstract": ParagraphStyle(
            "Abstract",
            parent=base["BodyText"],
            fontName="ReportUnicode",
            fontSize=9.5,
            leading=14.2,
            textColor=INK,
            alignment=TA_JUSTIFY,
        ),
        "code": ParagraphStyle(
            "Code",
            parent=base["Code"],
            fontName="Courier",
            fontSize=7.8,
            leading=10.5,
            textColor=INK,
            leftIndent=4 * mm,
            rightIndent=4 * mm,
            backColor=colors.HexColor("#F6F8FC"),
            borderColor=RULE,
            borderWidth=0.5,
            borderPadding=5,
            spaceAfter=3 * mm,
        ),
    }


def inline_markup(text: str) -> str:
    code_spans = []

    def protect_code(match):
        code_spans.append(match.group(1))
        return f"@@CODE{len(code_spans) - 1}@@"

    protected = re.sub(r"`([^`]+)`", protect_code, text)
    escaped = protected.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    escaped = re.sub(r"\*\*([^*]+)\*\*", r"<b>\1</b>", escaped)
    escaped = re.sub(r"(?<!\*)\*([^*]+)\*(?!\*)", r"<i>\1</i>", escaped)
    url_pattern = re.compile(r"(https?://[^\s<]+)")
    escaped = url_pattern.sub(r"<link href='\1' color='#2555FF'>\1</link>", escaped)
    for index, code_span in enumerate(code_spans):
        safe = code_span.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
        escaped = escaped.replace(f"@@CODE{index}@@", f"<font name='Courier'>{safe}</font>")
    return escaped


def architecture_figure() -> Drawing:
    d = Drawing(470, 220)
    d.add(Rect(0, 0, 470, 220, rx=8, ry=8, fillColor=colors.white, strokeColor=RULE))

    def box(x, y, w, h, label, fill, stroke=BLUE, size=8):
        d.add(Rect(x, y, w, h, rx=5, ry=5, fillColor=fill, strokeColor=stroke, strokeWidth=1))
        lines = label.split("\n")
        for idx, line in enumerate(lines):
            d.add(String(x + w / 2, y + h / 2 + 4 - idx * 11, line, textAnchor="middle", fontName="Helvetica-Bold" if idx == 0 else "Helvetica", fontSize=size, fillColor=INK))

    box(18, 168, 96, 34, "User intent\nphone UI", PALE)
    box(139, 168, 96, 34, "Agent loop\nstate + tools", PALE)
    box(260, 168, 96, 34, "ActionRunner\nschema + policy", PALE)
    box(381, 168, 70, 34, "Approval\npreview", colors.HexColor("#FFF4E5"), AMBER)
    box(154, 95, 160, 38, "RuntimeManager\ncapability + health selection", colors.HexColor("#EAF8F4"), GREEN)
    box(18, 30, 82, 34, "Helper\nAndroid", colors.HexColor("#F6F8FC"), MUTED)
    box(112, 30, 82, 34, "Alpine\nPRoot", colors.HexColor("#F6F8FC"), MUTED)
    box(206, 30, 82, 34, "Termux\nfallback", colors.HexColor("#F6F8FC"), MUTED)
    box(300, 30, 70, 34, "Cloud\nheavy", colors.HexColor("#F6F8FC"), MUTED)
    box(382, 30, 70, 34, "WebView\npreview", colors.HexColor("#F6F8FC"), MUTED)
    box(327, 95, 125, 38, "Evidence plane\nresult + recovery + artifact", colors.HexColor("#F3EDFF"), colors.HexColor("#7653C6"))

    arrows = [
        (114, 185, 139, 185), (235, 185, 260, 185), (356, 185, 381, 185),
        (416, 168, 416, 145), (381, 114, 314, 114), (234, 95, 234, 64),
        (59, 95, 59, 64), (153, 95, 153, 64), (247, 95, 247, 64),
        (335, 95, 335, 64), (417, 95, 417, 64),
    ]
    for x1, y1, x2, y2 in arrows:
        d.add(Line(x1, y1, x2, y2, strokeColor=MUTED, strokeWidth=1))
    d.add(Line(59, 95, 417, 95, strokeColor=MUTED, strokeWidth=1))
    d.add(Line(234, 133, 234, 168, strokeColor=MUTED, strokeWidth=1))
    d.add(Line(327, 114, 314, 114, strokeColor=colors.HexColor("#7653C6"), strokeWidth=1))
    return d


def navigation_figure() -> Drawing:
    d = Drawing(470, 254)
    d.add(Rect(0, 0, 470, 254, rx=8, ry=8, fillColor=colors.white, strokeColor=RULE))

    def box(x, y, w, h, label, fill=colors.white, stroke=RULE, size=8):
        d.add(Rect(x, y, w, h, rx=5, ry=5, fillColor=fill, strokeColor=stroke, strokeWidth=1))
        lines = label.split("\n")
        for idx, line in enumerate(lines):
            d.add(String(
                x + w / 2,
                y + h / 2 + 4 - idx * 11,
                line,
                textAnchor="middle",
                fontName="Helvetica-Bold" if idx == 0 else "Helvetica",
                fontSize=size,
                fillColor=INK,
            ))

    box(160, 205, 150, 31, "Home / Agent Chat", PALE, BLUE, 9)
    box(160, 151, 150, 31, "Navigation Drawer", colors.HexColor("#F6F8FC"), MUTED, 9)
    box(12, 83, 125, 43, "Capability Center\nRuntime | CLI | Accounts | Security", colors.HexColor("#EAF8F4"), GREEN, 7.5)
    box(172, 83, 125, 43, "Build & Release\nAPK | Release | Logs | Checks", colors.HexColor("#FFF4E5"), AMBER, 7.5)
    box(332, 83, 125, 43, "Models & Settings\nProvider | Model | Theme | Workspace", colors.HexColor("#F3EDFF"), colors.HexColor("#7653C6"), 7.2)
    box(12, 19, 96, 34, "Typed action\npreview + approval", PALE, BLUE, 7.2)
    box(129, 19, 96, 34, "Selected runtime\nHelper | Alpine | Cloud", colors.HexColor("#EAF8F4"), GREEN, 7.0)
    box(246, 19, 96, 34, "Evidence\nstatus + logs + recovery", colors.HexColor("#F3EDFF"), colors.HexColor("#7653C6"), 7.2)
    box(363, 19, 94, 34, "Artifact\nHTML | PNG | PDF | MP4", colors.HexColor("#FFF4E5"), AMBER, 7.0)

    d.add(Line(235, 205, 235, 182, strokeColor=MUTED, strokeWidth=1.2))
    d.add(Line(235, 151, 235, 139, strokeColor=MUTED, strokeWidth=1.2))
    d.add(Line(74, 139, 395, 139, strokeColor=MUTED, strokeWidth=1))
    for x in (74, 234, 395):
        d.add(Line(x, 139, x, 126, strokeColor=MUTED, strokeWidth=1))
    d.add(Line(74, 83, 74, 66, strokeColor=GREEN, strokeWidth=1))
    d.add(Line(60, 66, 410, 66, strokeColor=MUTED, strokeWidth=1))
    for x in (60, 177, 294, 410):
        d.add(Line(x, 66, x, 53, strokeColor=MUTED, strokeWidth=1))
    return d


def evidence_figure() -> Drawing:
    d = Drawing(470, 150)
    d.add(Rect(0, 0, 470, 150, rx=8, ry=8, fillColor=colors.white, strokeColor=RULE))
    stages = [
        (15, "Intent", PALE, BLUE),
        (100, "Validate", PALE, BLUE),
        (185, "Preview", colors.HexColor("#FFF4E5"), AMBER),
        (270, "Execute", colors.HexColor("#EAF8F4"), GREEN),
        (355, "Verify", colors.HexColor("#EAF8F4"), GREEN),
    ]
    for x, label, fill, stroke in stages:
        d.add(Rect(x, 86, 72, 30, rx=5, ry=5, fillColor=fill, strokeColor=stroke))
        d.add(String(x + 36, 97, label, textAnchor="middle", fontName="Helvetica-Bold", fontSize=8.5, fillColor=INK))
    for x in (87, 172, 257, 342):
        d.add(Line(x, 101, x + 13, 101, strokeColor=MUTED, strokeWidth=1.2))
    d.add(Line(221, 86, 221, 65, strokeColor=AMBER, strokeWidth=1))
    d.add(String(221, 53, "approval required for mutation", textAnchor="middle", fontName="Helvetica", fontSize=7.5, fillColor=AMBER))
    d.add(Rect(95, 18, 280, 24, rx=4, ry=4, fillColor=colors.HexColor("#F3EDFF"), strokeColor=colors.HexColor("#7653C6")))
    d.add(String(235, 27, "ActionEvidence: status | runtime | logs | failure | recovery | metadata | redaction", textAnchor="middle", fontName="Helvetica", fontSize=7.3, fillColor=INK))
    d.add(Line(391, 86, 355, 42, strokeColor=colors.HexColor("#7653C6"), strokeWidth=1))
    return d


def beta_figure() -> Drawing:
    d = Drawing(470, 120)
    d.add(Rect(0, 0, 470, 120, rx=8, ry=8, fillColor=colors.white, strokeColor=RULE))
    labels = [
        ("Repository", "converged", GREEN),
        ("Current CI", "passed", GREEN),
        ("Android emulator", "current pass", GREEN),
        ("Physical device", "pending", AMBER),
        ("Provider truth", "partial", AMBER),
    ]
    x = 15
    for title, state, color in labels:
        d.add(Rect(x, 45, 78, 42, rx=5, ry=5, fillColor=colors.HexColor("#F8FAFD"), strokeColor=color, strokeWidth=1.2))
        d.add(String(x + 39, 69, title, textAnchor="middle", fontName="Helvetica-Bold", fontSize=7.6, fillColor=INK))
        d.add(String(x + 39, 54, state, textAnchor="middle", fontName="Helvetica", fontSize=7.3, fillColor=color))
        x += 91
    d.add(String(235, 99, "BETA READINESS IS THE INTERSECTION OF ALL GATES", textAnchor="middle", fontName="Helvetica-Bold", fontSize=9, fillColor=INK))
    d.add(String(235, 20, "A strong feature proof does not waive repository, CI, security, or device evidence.", textAnchor="middle", fontName="Helvetica-Oblique", fontSize=8, fillColor=MUTED))
    return d


GALLERIES = {
    "current-shell": [
        ("docs/technical-report/assets/mobilecode-android-home-20260714.png", "Android Emulator · current home · 2026-07-14"),
        ("docs/technical-report/assets/mobilecode-android-navigation-20260714.png", "Android Emulator · feature navigation · 2026-07-14"),
        ("docs/technical-report/assets/mobilecode-capability-runtime-20260714.png", "Android Emulator · runtime capability truth · 2026-07-14"),
        ("docs/technical-report/assets/mobilecode-ios-home-20260714.png", "iOS Simulator · current home · 2026-07-14"),
    ],
    "capability-tabs": [
        ("docs/technical-report/assets/mobilecode-extension-center-20260714.png", "Extension Center / CLI Hub"),
        ("docs/technical-report/assets/mobilecode-subscriptions-20260714.png", "Accounts and subscriptions"),
        ("docs/technical-report/assets/mobilecode-security-20260714.png", "Security, permissions, vault, redaction"),
    ],
    "product-flows": [
        ("mobile_agent/qa-output/android-devharness-closeout-20260627-022350/07-cli-hub-top.png", "CLI Hub catalog · Android Emulator · 2026-06-27"),
        ("docs/mobile-harness-benchmark/strategy-ablation/runs/p63-android-real-device-lane/evidence/04-action-probe.png", "Phone Use action probe · Android Emulator · 2026-06-21"),
        ("docs/assets/qa/mobilecode-20260619/03-snake-playable-webview.png", "Editable HTML game in app-owned WebView · Android Emulator · 2026-06-19"),
    ],
    "pptx-effect": [
        ("docs/technical-report/assets/mobilecode-pptx-effect-20260714.png", "Rendered from a real 16:9 PPTX produced by MobileCode's HTML-to-PPTX worker · 2026-07-14"),
    ],
}


def screenshot_gallery(key: str, st):
    entries = GALLERIES[key]
    count = len(entries)
    col_width = 162 * mm / count
    max_width = (158 if count == 1 else 35 if count == 4 else 45) * mm
    max_height = (89 if count == 1 else 68 if count == 4 else 82) * mm
    images = []
    captions = []
    for relative_path, caption in entries:
        image = Image(str(REPO_ROOT / relative_path))
        scale = min(max_width / image.imageWidth, max_height / image.imageHeight)
        image.drawWidth = image.imageWidth * scale
        image.drawHeight = image.imageHeight * scale
        images.append(image)
        captions.append(Paragraph(inline_markup(caption), st["caption"]))
    table = Table([images, captions], colWidths=[col_width] * count, hAlign="CENTER")
    table.setStyle(TableStyle([
        ("ALIGN", (0, 0), (-1, -1), "CENTER"),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (-1, -1), 3),
        ("RIGHTPADDING", (0, 0), (-1, -1), 3),
        ("TOPPADDING", (0, 0), (-1, 0), 5),
        ("BOTTOMPADDING", (0, 0), (-1, 0), 3),
        ("BOX", (0, 0), (-1, -1), 0.45, RULE),
        ("INNERGRID", (0, 0), (-1, -1), 0.35, RULE),
        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#FAFBFD")),
    ]))
    return table


def cli_matrix_table(st):
    manifest_path = REPO_ROOT / "cli-hub/catalog/mobilecode-cli-hub.manifest.json"
    entries = json.loads(manifest_path.read_text(encoding="utf-8"))["entries"]
    headers = ["CLI", "Stage", "Install", "Probe", "Auth", "Read", "Mutate", "Credential / risk"]
    rows = [[Paragraph(inline_markup(cell), st["table"]) for cell in headers]]
    for entry in entries:
        auth = entry.get("auth", {})
        install = entry.get("install", {})
        values = [
            entry.get("title", entry["id"]),
            entry.get("supportLevel", "-"),
            install.get("strategy", "-"),
            "Yes" if entry.get("probe") else "-",
            "Required" if auth.get("required") else "No",
            str(len(entry.get("readOnlyTasks", []))) or "0",
            str(len(entry.get("mutationTasks", []))) or "0",
            f'{entry.get("credentialPolicy", "-")} / {entry.get("riskLevel", "-")}',
        ]
        rows.append([Paragraph(inline_markup(str(cell)), st["table"]) for cell in values])
    widths = [28, 17, 25, 12, 18, 12, 14, 40]
    table = Table(rows, colWidths=[value * mm for value in widths], repeatRows=1, hAlign="LEFT")
    table.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#DDE5FF")),
        ("TEXTCOLOR", (0, 0), (-1, 0), INK),
        ("GRID", (0, 0), (-1, -1), 0.35, RULE),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (-1, -1), 3),
        ("RIGHTPADDING", (0, 0), (-1, -1), 3),
        ("TOPPADDING", (0, 0), (-1, -1), 3.5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 3.5),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#FAFBFD")]),
        ("TEXTCOLOR", (1, 1), (1, 2), GREEN),
        ("TEXTCOLOR", (1, 3), (1, 7), AMBER),
        ("TEXTCOLOR", (1, 8), (1, -1), MUTED),
    ]))
    return table


def parse_markdown(path: Path):
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    title = lines[0].removeprefix("# ").strip()
    metadata = [line.strip() for line in lines[1:5] if line.strip()]
    return title, metadata, lines[5:]


def markdown_flowables(lines, st):
    story = []
    paragraph = []
    bullets = []
    numbered = []
    code = []
    in_code = False
    i = 0

    def flush_paragraph():
        if paragraph:
            story.append(Paragraph(inline_markup(" ".join(paragraph)), st["body"]))
            paragraph.clear()

    def flush_lists():
        if bullets:
            items = [ListItem(Paragraph(inline_markup(x), st["body"]), leftIndent=4 * mm) for x in bullets]
            story.append(ListFlowable(items, bulletType="bullet", leftIndent=6 * mm, bulletFontName="Helvetica", bulletFontSize=6, spaceAfter=2 * mm))
            bullets.clear()
        if numbered:
            items = [ListItem(Paragraph(inline_markup(x), st["body"]), leftIndent=4 * mm) for x in numbered]
            story.append(ListFlowable(items, bulletType="1", start="1", leftIndent=7 * mm, bulletFontName="Helvetica", bulletFontSize=8, spaceAfter=2 * mm))
            numbered.clear()

    while i < len(lines):
        line = lines[i]
        if line.startswith("```"):
            flush_paragraph(); flush_lists()
            if in_code:
                story.append(Preformatted("\n".join(code), st["code"]))
                code.clear()
                in_code = False
            else:
                in_code = True
            i += 1
            continue
        if in_code:
            code.append(line)
            i += 1
            continue
        if line.startswith("<!-- FIGURE:"):
            flush_paragraph(); flush_lists()
            key = line.split(":", 1)[1].split("-->", 1)[0].strip()
            figure = {"architecture": architecture_figure, "navigation": navigation_figure, "evidence": evidence_figure, "beta": beta_figure}[key]()
            story.append(KeepTogether([Spacer(1, 2 * mm), figure, Spacer(1, 2 * mm)]))
            i += 1
            continue
        if line.startswith("<!-- GALLERY:"):
            flush_paragraph(); flush_lists()
            key = line.split(":", 1)[1].split("-->", 1)[0].strip()
            story.append(screenshot_gallery(key, st))
            story.append(Spacer(1, 3 * mm))
            i += 1
            continue
        if line.strip() == "<!-- CLI_MATRIX -->":
            flush_paragraph(); flush_lists()
            story.append(cli_matrix_table(st))
            story.append(Spacer(1, 3 * mm))
            i += 1
            continue
        if line.strip() == "<!-- PAGEBREAK -->":
            flush_paragraph(); flush_lists(); story.append(PageBreak()); i += 1; continue
        if line.startswith("## "):
            flush_paragraph(); flush_lists(); story.append(Paragraph(inline_markup(line[3:]), st["h1"])); i += 1; continue
        if line.startswith("### "):
            flush_paragraph(); flush_lists(); story.append(Paragraph(inline_markup(line[4:]), st["h2"])); i += 1; continue
        if line.startswith("| ") and i + 1 < len(lines) and re.match(r"^\|[\s:|-]+\|$", lines[i + 1]):
            flush_paragraph(); flush_lists()
            table_lines = [line]
            i += 2
            while i < len(lines) and lines[i].startswith("| "):
                table_lines.append(lines[i]); i += 1
            rows = []
            for row in table_lines:
                cells = [cell.strip() for cell in row.strip().strip("|").split("|")]
                rows.append([Paragraph(inline_markup(cell), st["table"]) for cell in cells])
            col_count = max(len(row) for row in rows)
            available = 166 * mm
            widths = [available / col_count] * col_count
            table = Table(rows, colWidths=widths, repeatRows=1, hAlign="LEFT")
            table.setStyle(TableStyle([
                ("BACKGROUND", (0, 0), (-1, 0), PALE),
                ("TEXTCOLOR", (0, 0), (-1, 0), INK),
                ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
                ("GRID", (0, 0), (-1, -1), 0.35, RULE),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 4),
                ("RIGHTPADDING", (0, 0), (-1, -1), 4),
                ("TOPPADDING", (0, 0), (-1, -1), 4),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
                ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#FAFBFD")]),
            ]))
            story.append(table); story.append(Spacer(1, 3 * mm)); continue
        if line.startswith("- "):
            flush_paragraph()
            if numbered: flush_lists()
            bullets.append(line[2:].strip()); i += 1; continue
        if re.match(r"^\d+\. ", line):
            flush_paragraph()
            if bullets: flush_lists()
            numbered.append(re.sub(r"^\d+\. ", "", line).strip()); i += 1; continue
        if not line.strip():
            flush_paragraph(); flush_lists(); i += 1; continue
        if line.startswith(("Figure ", "Table ")):
            flush_paragraph(); flush_lists(); story.append(Paragraph(inline_markup(line), st["caption"])); i += 1; continue
        paragraph.append(line.strip()); i += 1

    flush_paragraph(); flush_lists()
    if code:
        story.append(Preformatted("\n".join(code), st["code"]))
    return story


def build(input_path: Path, output_path: Path) -> None:
    register_fonts()
    st = styles()
    title, metadata, lines = parse_markdown(input_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    doc = ReportDocTemplate(
        str(output_path),
        pagesize=A4,
        leftMargin=22 * mm,
        rightMargin=22 * mm,
        topMargin=22 * mm,
        bottomMargin=20 * mm,
        title=title,
        author="Harzva MobileCode Project",
        subject="Phone-native harness architecture, evidence, and Beta readiness",
    )
    story = []
    story.append(Spacer(1, 11 * mm))
    brand = Drawing(470, 55)
    brand.add(Rect(0, 14, 30, 30, rx=6, ry=6, fillColor=BLUE, strokeColor=BLUE))
    brand.add(String(15, 24, "MC", textAnchor="middle", fontName="Helvetica-Bold", fontSize=12, fillColor=colors.white))
    brand.add(String(42, 29, "MOBILECODE", fontName="Helvetica-Bold", fontSize=13, fillColor=BLUE))
    brand.add(Line(0, 5, 470, 5, strokeColor=RULE, strokeWidth=1))
    story.append(brand)
    story.append(Spacer(1, 16 * mm))
    story.append(Paragraph(inline_markup(title), st["title"]))
    story.append(Paragraph("<b>Phone-native control. Typed execution. Evidence-bound claims.</b>", st["subtitle"]))
    story.append(Spacer(1, 10 * mm))
    for line in metadata:
        story.append(Paragraph(inline_markup(line.replace("  ", "")), st["subtitle"]))
    story.append(Spacer(1, 16 * mm))
    story.append(Table(
        [[Paragraph("STATUS", st["table"]), Paragraph("Advanced Beta candidate - physical-device closure pending", st["table"])],
         [Paragraph("PRIMARY TARGET", st["table"]), Paragraph("Android and iOS control plane; Android Dev Harness execution", st["table"])],
         [Paragraph("EVIDENCE DATE", st["table"]), Paragraph("2026-07-14", st["table"])]],
        colWidths=[34 * mm, 126 * mm],
        style=TableStyle([
            ("BACKGROUND", (0, 0), (0, -1), PALE),
            ("BACKGROUND", (1, 0), (1, -1), colors.white),
            ("GRID", (0, 0), (-1, -1), 0.5, RULE),
            ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
            ("LEFTPADDING", (0, 0), (-1, -1), 7),
            ("TOPPADDING", (0, 0), (-1, -1), 7),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 7),
        ]),
    ))
    story.append(PageBreak())
    story.extend(markdown_flowables(lines, st))
    doc.build(story)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", default="docs/technical-report/mobilecode-phone-native-harness-v0.md")
    parser.add_argument("--output", default="output/pdf/mobilecode-phone-native-harness-v0.pdf")
    args = parser.parse_args()
    build(Path(args.input), Path(args.output))


if __name__ == "__main__":
    main()

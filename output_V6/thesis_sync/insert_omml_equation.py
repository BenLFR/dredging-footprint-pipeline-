#!/usr/bin/env python3
"""insert_omml_equation.py

Replaces the plain-text nmin equation paragraph with a proper OMML
(Office Math Markup Language) display equation, centred on its own line.

Target rendering (from PDF reference, section 2.5):

    n_min = min( 8, max( 3, ⌈ Δ̃t_50 / t_threshold ⌉ ) ),  t_threshold = 30 s

where:
  - n_min, t_threshold  → italic base + roman subscript
  - Δ̃t_50 / t_threshold → proper fraction (stacked)
  - ⌈ ⌉                 → ceiling-bracket delimiter
  - Δ̃t_50              → tilde accent over Δt, roman subscript 50
"""

import sys
sys.stdout.reconfigure(encoding="utf-8")
import shutil
from datetime import datetime
from pathlib import Path
from docx import Document
from lxml import etree

THESIS_PATH = "Master Thesis - Benjamin LOEFFLER_synced.docx"

W   = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
M   = "http://schemas.openxmlformats.org/officeDocument/2006/math"
XML = "http://www.w3.org/XML/1998/namespace"

def wq(t): return f"{{{W}}}{t}"
def mq(t): return f"{{{M}}}{t}"


# ---------------------------------------------------------------------------
# OMML helpers
# ---------------------------------------------------------------------------

def ctrl_pr(parent):
    etree.SubElement(parent, mq("ctrlPr"))


def m_run(parent, text, style="p"):
    """<m:r><m:rPr><m:sty val=style/></m:rPr><m:t>text</m:t></m:r>"""
    r   = etree.SubElement(parent, mq("r"))
    rpr = etree.SubElement(r,  mq("rPr"))
    sty = etree.SubElement(rpr, mq("sty"))
    sty.set(mq("val"), style)
    t = etree.SubElement(r, mq("t"))
    t.set(f"{{{XML}}}space", "preserve")
    t.text = text
    return r


def m_ssub(parent, base_text, sub_text, base_sty="i", sub_sty="p"):
    """<m:sSub> with italic base and roman subscript."""
    ss  = etree.SubElement(parent, mq("sSub"))
    pr  = etree.SubElement(ss, mq("sSubPr"));  ctrl_pr(pr)
    e   = etree.SubElement(ss, mq("e"));        m_run(e, base_text, base_sty)
    sub = etree.SubElement(ss, mq("sub"));      m_run(sub, sub_text, sub_sty)
    return ss


def m_acc_ssub(parent, acc_text, sub_text, acc_char="~",
               acc_sty="i", sub_sty="p"):
    """
    <m:sSub>
      <m:e>
        <m:acc chr=acc_char>
          <m:e><m:r>acc_text</m:r></m:e>
        </m:acc>
      </m:e>
      <m:sub>sub_text</m:sub>
    </m:sSub>
    Renders as: acc_text̃  with subscript sub_text
    """
    ss  = etree.SubElement(parent, mq("sSub"))
    pr  = etree.SubElement(ss, mq("sSubPr"));  ctrl_pr(pr)
    e   = etree.SubElement(ss, mq("e"))

    acc    = etree.SubElement(e, mq("acc"))
    accPr  = etree.SubElement(acc, mq("accPr"))
    accChr = etree.SubElement(accPr, mq("chr"))
    accChr.set(mq("val"), acc_char)
    ctrl_pr(accPr)
    acc_e  = etree.SubElement(acc, mq("e"))
    m_run(acc_e, acc_text, acc_sty)

    sub = etree.SubElement(ss, mq("sub"))
    m_run(sub, sub_text, sub_sty)
    return ss


def m_frac(parent, num_builder, den_builder):
    """<m:f><m:num>...</m:num><m:den>...</m:den></m:f>"""
    f   = etree.SubElement(parent, mq("f"))
    fPr = etree.SubElement(f, mq("fPr")); ctrl_pr(fPr)
    num = etree.SubElement(f, mq("num")); num_builder(num)
    den = etree.SubElement(f, mq("den")); den_builder(den)
    return f


def m_d(parent, beg, end, content_builder):
    """<m:d> delimiter with open/close chars and a single <m:e>."""
    d   = etree.SubElement(parent, mq("d"))
    dPr = etree.SubElement(d, mq("dPr"))
    b   = etree.SubElement(dPr, mq("begChr")); b.set(mq("val"), beg)
    e_  = etree.SubElement(dPr, mq("endChr")); e_.set(mq("val"), end)
    ctrl_pr(dPr)
    e   = etree.SubElement(d, mq("e"))
    content_builder(e)
    return d


# ---------------------------------------------------------------------------
# Build the full equation
# ---------------------------------------------------------------------------

def build_omath():
    """
    Builds:
      n_{min} = min(8, max(3, ⌈ Δ̃t_{50} / t_{threshold} ⌉)), t_{threshold} = 30 s
    """
    omath = etree.Element(mq("oMath"))

    # n_{min}
    m_ssub(omath, "n", "min")

    # " = min(8, max(3, "
    m_run(omath, " = min(8, max(3, ")

    # ⌈ Δ̃t_{50} / t_{threshold} ⌉
    def ceil_content(e):
        m_frac(
            e,
            num_builder=lambda n: m_acc_ssub(n, "\u0394t", "50", acc_char="~"),
            den_builder=lambda d: m_ssub(d, "t", "threshold"),
        )

    m_d(omath, "\u2308", "\u2309", ceil_content)   # ⌈ ... ⌉

    # ")), "
    m_run(omath, ")), ")

    # t_{threshold}
    m_ssub(omath, "t", "threshold")

    # " = 30 s"
    m_run(omath, " = 30 s")

    return omath


# ---------------------------------------------------------------------------
# Inject into the document
# ---------------------------------------------------------------------------

def inject_equation(doc):
    paras = doc.paragraphs

    # Find the equation paragraph: plain-text version written by previous scripts
    eq_idx = None
    for i, p in enumerate(paras):
        t = p.text
        if ("min = min" in t or "𝑛min" in t) and ("max(3" in t or "30 s" in t):
            eq_idx = i
            break

    if eq_idx is None:
        # Fallback: paragraph after "computed as:"
        for i, p in enumerate(paras):
            if "run-length threshold was then computed as" in p.text:
                # Next non-blank para
                for j in range(i + 1, min(i + 5, len(paras))):
                    if paras[j].text.strip():
                        eq_idx = j
                        break
                break

    if eq_idx is None:
        print("ERROR: Could not locate the equation paragraph.", file=sys.stderr)
        return False

    print(f"  Equation paragraph at index {eq_idx}: {repr(paras[eq_idx].text[:80])}")

    p_elem = paras[eq_idx]._p

    # Remove everything except <w:pPr>
    for child in list(p_elem):
        if child.tag != wq("pPr"):
            p_elem.remove(child)

    # Ensure paragraph is centred
    ppr = p_elem.find(wq("pPr"))
    if ppr is None:
        ppr = etree.Element(wq("pPr"))
        p_elem.insert(0, ppr)
    jc = ppr.find(wq("jc"))
    if jc is None:
        jc = etree.SubElement(ppr, wq("jc"))
    jc.set(wq("val"), "center")

    # Append the OMML equation
    omath = build_omath()
    p_elem.append(omath)

    print("  [OK] Equation injected as OMML.")
    return True


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    path = Path(THESIS_PATH)
    if not path.exists():
        print(f"Error: {THESIS_PATH} not found", file=sys.stderr)
        sys.exit(1)

    ts     = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup = Path(f"output_V6/thesis_sync/backups/{path.stem}_backup_{ts}.docx")
    backup.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(path, backup)
    print(f"Backup: {backup}")

    doc = Document(THESIS_PATH)
    ok  = inject_equation(doc)

    if ok:
        out = path.with_name(path.stem + "_omml.docx")
        doc.save(str(out))
        print(f"\nSaved → {out}")
        print("Open in Word to verify; then close Word and rename to _synced.docx.")
    else:
        print("Nothing saved — equation not found.")


if __name__ == "__main__":
    main()

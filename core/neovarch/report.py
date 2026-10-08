"""Reports and theses from real references, exported with Pandoc (free tools only).

Pipeline
--------
1. ``search_references(query)`` asks the free scholarly APIs (OpenAlex, Crossref,
   Semantic Scholar; no key needed) and merges the hits by DOI/title. Every
   reference therefore exists in a public index; nothing is invented.
2. ``create_report(...)`` writes ``<slug>/report.md`` (Pandoc Markdown with YAML
   front matter) and ``references.bib`` (BibTeX built from the API records). Every
   ``[@key]`` the text cites must be one of those records, otherwise the report
   is refused: no fabricated citations.
3. ``export_report(...)`` runs Pandoc with ``--citeproc`` and a CSL style (APA
   or IEEE) to ``.docx`` using a generated campus ``reference.docx`` (Times New
   Roman 12, 1.5 line spacing, margins 4-3-3-3 cm, table of contents, numbered
   chapters), and to PDF through Typst or LibreOffice headless when installed.
   Pandoc is taken from PATH or ``~/.neovarch/bin``; when missing it is
   downloaded once from the official GitHub release.
"""

from __future__ import annotations

import io
import json
import os
import platform
import re
import shutil
import subprocess
import tarfile
import tempfile
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path
from typing import Any, Callable

from neovarch.paths import neovarch_home

UA = "Neovarch-Agent/1.4 (report generator; https://github.com/Maftuuh1922/neovrach_Agent)"
PANDOC_VERSION = "3.1.11.1"
CSL_URLS = {
    "apa": "https://raw.githubusercontent.com/citation-style-language/styles/master/apa.csl",
    "ieee": "https://raw.githubusercontent.com/citation-style-language/styles/master/ieee.csl",
}

Fetch = Callable[[str], Any]


class ReportError(Exception):
    pass


# ----------------------------------------------------------------- http -----

def http_json(url: str, timeout: float = 20, retries: int = 2) -> Any:
    """GET JSON; a 429/503 (the free APIs rate-limit) is retried with a short backoff."""
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json"})
    for attempt in range(retries + 1):
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:  # noqa: S310 (fixed https hosts)
                return json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            if exc.code not in (429, 503) or attempt == retries:
                raise
            wait = exc.headers.get("Retry-After") if exc.headers else None
            time.sleep(min(float(wait) if wait and wait.isdigit() else 1.5 * (attempt + 1), 5))


def http_bytes(url: str, timeout: float = 120) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=timeout) as resp:  # noqa: S310
        return resp.read()


# ------------------------------------------------------------ references ----

def _clean(s: Any) -> str:
    return re.sub(r"\s+", " ", re.sub(r"<[^>]+>", "", str(s or ""))).strip()


def _doi(s: Any) -> str:
    d = str(s or "").strip()
    d = re.sub(r"^https?://(dx\.)?doi\.org/", "", d, flags=re.I)
    return d.lower()


def _openalex_abstract(inv: dict | None) -> str:
    if not inv:
        return ""
    pos: list[tuple[int, str]] = []
    for word, idx in inv.items():
        pos += [(i, word) for i in idx]
    return " ".join(w for _, w in sorted(pos))


def from_openalex(data: dict) -> list[dict]:
    out = []
    for w in data.get("results") or []:
        loc = (w.get("primary_location") or {}).get("source") or {}
        out.append({
            "title": _clean(w.get("title") or w.get("display_name")),
            "authors": [_clean((a.get("author") or {}).get("display_name")) for a in w.get("authorships") or []],
            "year": w.get("publication_year"),
            "doi": _doi(w.get("doi")),
            "venue": _clean(loc.get("display_name")),
            "url": w.get("doi") or w.get("id") or "",
            "abstract": _openalex_abstract(w.get("abstract_inverted_index")),
            "type": w.get("type") or "article",
            "volume": (w.get("biblio") or {}).get("volume"),
            "issue": (w.get("biblio") or {}).get("issue"),
            "pages": "-".join(p for p in [(w.get("biblio") or {}).get("first_page"),
                                         (w.get("biblio") or {}).get("last_page")] if p),
            "source": "openalex",
        })
    return out


def from_crossref(data: dict) -> list[dict]:
    out = []
    for it in (data.get("message") or {}).get("items") or []:
        parts = (it.get("issued") or {}).get("date-parts") or [[None]]
        out.append({
            "title": _clean((it.get("title") or [""])[0]),
            "authors": [_clean(f"{a.get('given', '')} {a.get('family', '')}") for a in it.get("author") or []
                        if a.get("family")],
            "year": parts[0][0] if parts and parts[0] else None,
            "doi": _doi(it.get("DOI")),
            "venue": _clean((it.get("container-title") or [""])[0]),
            "url": it.get("URL") or "",
            "abstract": _clean(it.get("abstract")),
            "type": it.get("type") or "journal-article",
            "volume": it.get("volume"),
            "issue": it.get("issue"),
            "pages": it.get("page") or "",
            "publisher": it.get("publisher"),
            "source": "crossref",
        })
    return out


def from_semantic_scholar(data: dict) -> list[dict]:
    out = []
    for p in data.get("data") or []:
        ext = p.get("externalIds") or {}
        out.append({
            "title": _clean(p.get("title")),
            "authors": [_clean(a.get("name")) for a in p.get("authors") or []],
            "year": p.get("year"),
            "doi": _doi(ext.get("DOI")),
            "venue": _clean(p.get("venue")),
            "url": p.get("url") or "",
            "abstract": _clean(p.get("abstract")),
            "type": "article",
            "source": "semanticscholar",
        })
    return out


def _norm_title(t: str) -> str:
    t = unicodedata.normalize("NFKD", t).encode("ascii", "ignore").decode().lower()
    return re.sub(r"[^a-z0-9]+", "", t)


def search_references(query: str, limit: int = 10, *, fetch: Fetch = http_json,
                      sources: tuple[str, ...] = ("openalex", "crossref", "semanticscholar"),
                      year_from: int | None = None) -> dict:
    """Search the free scholarly indexes; merge and dedupe. Returns refs + per-source errors."""
    q = urllib.parse.quote(query)
    n = max(1, min(int(limit), 50))
    urls = {
        "openalex": f"https://api.openalex.org/works?search={q}&per-page={n}"
                    + (f"&filter=from_publication_date:{year_from}-01-01" if year_from else ""),
        "crossref": f"https://api.crossref.org/works?query={q}&rows={n}"
                    + (f"&filter=from-pub-date:{year_from}" if year_from else ""),
        "semanticscholar": f"https://api.semanticscholar.org/graph/v1/paper/search?query={q}&limit={n}"
                           "&fields=title,authors,year,externalIds,venue,url,abstract"
                           + (f"&year={year_from}-" if year_from else ""),
    }
    parsers = {"openalex": from_openalex, "crossref": from_crossref, "semanticscholar": from_semantic_scholar}
    merged: list[dict] = []
    seen: dict[str, dict] = {}
    errors: dict[str, str] = {}
    for src in sources:
        try:
            refs = parsers[src](fetch(urls[src]))
        except Exception as exc:  # network, rate limit, bad JSON: keep the other sources
            errors[src] = f"{type(exc).__name__}: {exc}"
            continue
        for r in refs:
            if not r["title"] or not r["authors"] or not r["year"]:
                continue  # incomplete records make bad citations
            key = r["doi"] or _norm_title(r["title"])
            if key in seen:
                old = seen[key]
                for f, v in r.items():
                    if not old.get(f) and v:
                        old[f] = v
                old.setdefault("also_in", []).append(src)
                continue
            seen[key] = r
            merged.append(r)
    used = set()
    for r in merged:
        r["key"] = cite_key(r, used)
    return {"query": query, "references": merged[: n * 2], "errors": errors}


def cite_key(ref: dict, used: set[str]) -> str:
    last = (ref.get("authors") or ["anon"])[0].split()[-1] if ref.get("authors") else "anon"
    last = re.sub(r"[^a-z]", "", unicodedata.normalize("NFKD", last).encode("ascii", "ignore").decode().lower()) or "anon"
    word = next((w for w in re.findall(r"[a-z]{4,}", _norm_ascii(ref.get("title", "")).lower())
                 if w not in {"with", "from", "that", "this", "into", "using", "towards"}), "")
    base = f"{last}{ref.get('year') or ''}{word}"
    key, i = base, 1
    while key in used:
        i += 1
        key = f"{base}{chr(96 + i)}"
    used.add(key)
    return key


def _norm_ascii(s: str) -> str:
    return unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode()


def _bib_escape(s: str) -> str:
    return str(s).replace("\\", "\\textbackslash{}").replace("{", "\\{").replace("}", "\\}") \
        .replace("&", "\\&").replace("%", "\\%").replace("#", "\\#").replace("_", "\\_")


def to_bibtex(refs: list[dict]) -> str:
    out = []
    for r in refs:
        kind = "article" if r.get("venue") and "book" not in str(r.get("type")) else "misc"
        if "proceedings" in str(r.get("type")) or "conference" in str(r.get("venue", "")).lower():
            kind = "inproceedings"
        fields = [("title", "{" + _bib_escape(r["title"]) + "}"),
                  ("author", " and ".join(_bib_escape(a) for a in r.get("authors") or [])),
                  ("year", str(r.get("year") or ""))]
        if r.get("venue"):
            fields.append(("booktitle" if kind == "inproceedings" else "journal", _bib_escape(r["venue"])))
        for f in ("volume", "issue", "pages", "publisher"):
            if r.get(f):
                fields.append(("number" if f == "issue" else f, _bib_escape(str(r[f]).replace("-", "--"))))
        if r.get("doi"):
            fields.append(("doi", r["doi"]))
        if r.get("url"):
            fields.append(("url", r["url"]))
        body = ",\n".join(f"  {k} = {{{v}}}" for k, v in fields if v)
        out.append(f"@{kind}{{{r['key']},\n{body}\n}}")
    return "\n\n".join(out) + "\n"


# --------------------------------------------------------------- create -----

CITE_RE = re.compile(r"@([A-Za-z0-9_][A-Za-z0-9_:.#$%&+?<>~/-]*)")


def cited_keys(markdown: str) -> set[str]:
    keys = set()
    for block in re.findall(r"\[[^\]]*@[^\]]*\]", markdown):
        keys |= {k.rstrip(".:") for k in CITE_RE.findall(block)}
    # narrative citations: @key at word start outside brackets
    keys |= {k.rstrip(".:") for k in re.findall(r"(?<![\w@\[])@([A-Za-z][A-Za-z0-9_-]*\d{4}[a-z]*)", markdown)}
    return keys


def slugify(s: str) -> str:
    s = _norm_ascii(s).lower()
    return re.sub(r"[^a-z0-9]+", "-", s).strip("-")[:60] or "laporan"


def reports_dir() -> Path:
    d = neovarch_home() / "reports"
    d.mkdir(parents=True, exist_ok=True)
    return d


def create_report(title: str, body: str, references: list[dict], *, author: str = "",
                  institution: str = "", style: str = "apa", out_dir: Path | None = None,
                  lang: str = "id-ID") -> dict:
    if not title.strip():
        raise ReportError("title required")
    if not body.strip():
        raise ReportError("body required")
    refs = [r for r in references if isinstance(r, dict) and r.get("key") and r.get("title")]
    known = {r["key"] for r in refs}
    cited = cited_keys(body)
    unknown = sorted(cited - known)
    if unknown:
        raise ReportError("citations without a real reference (search first, cite only returned keys): "
                          + ", ".join(unknown))
    if style not in CSL_URLS:
        raise ReportError(f"style must be one of {sorted(CSL_URLS)}")
    folder = (out_dir or reports_dir()) / slugify(title)
    folder.mkdir(parents=True, exist_ok=True)
    meta = {
        "title": title, "author": author or None, "institution": institution or None,
        "date": time.strftime("%Y-%m-%d"), "lang": lang, "bibliography": "references.bib",
        "link-citations": True, "toc": True, "toc-title": "Daftar Isi", "numbersections": True,
        "reference-section-title": "Daftar Pustaka", "csl-style": style,
    }
    front = "---\n" + "\n".join(f"{k}: {json.dumps(v, ensure_ascii=False)}" for k, v in meta.items()
                                 if v is not None) + "\n---\n\n"
    md = front + body.strip() + "\n"
    if refs and "# Daftar Pustaka" not in body:
        md += "\n# Daftar Pustaka {.unnumbered}\n\n::: {#refs}\n:::\n"
    (folder / "report.md").write_text(md, encoding="utf-8")
    (folder / "references.bib").write_text(to_bibtex(refs), encoding="utf-8")
    (folder / "references.json").write_text(json.dumps(refs, ensure_ascii=False, indent=1), encoding="utf-8")
    return {"dir": str(folder), "markdown": str(folder / "report.md"), "bibtex": str(folder / "references.bib"),
            "cited": sorted(cited), "uncited": sorted(known - cited), "references": len(refs)}


# ---------------------------------------------------------------- tools -----

def bin_dir() -> Path:
    d = neovarch_home() / "bin"
    d.mkdir(parents=True, exist_ok=True)
    return d


def find_pandoc() -> str | None:
    local = bin_dir() / ("pandoc.exe" if os.name == "nt" else "pandoc")
    if local.exists():
        return str(local)
    return shutil.which("pandoc")


def pandoc_asset_name(system: str | None = None, machine: str | None = None) -> str:
    system = (system or platform.system()).lower()
    machine = (machine or platform.machine()).lower()
    arch = "arm64" if machine in ("arm64", "aarch64") else "amd64"
    if system == "linux":
        return f"pandoc-{PANDOC_VERSION}-linux-{arch}.tar.gz"
    if system == "darwin":
        return f"pandoc-{PANDOC_VERSION}-{'arm64' if arch == 'arm64' else 'x86_64'}-macOS.zip"
    return f"pandoc-{PANDOC_VERSION}-windows-x86_64.zip"


def ensure_pandoc(download: Callable[[str], bytes] = http_bytes) -> str:
    """Pandoc from PATH or ~/.neovarch/bin; otherwise download the official release once."""
    found = find_pandoc()
    if found:
        return found
    name = pandoc_asset_name()
    url = f"https://github.com/jgm/pandoc/releases/download/{PANDOC_VERSION}/{name}"
    blob = download(url)
    target = bin_dir() / ("pandoc.exe" if os.name == "nt" else "pandoc")
    member_name = "pandoc.exe" if os.name == "nt" else "pandoc"
    if name.endswith(".tar.gz"):
        with tarfile.open(fileobj=io.BytesIO(blob)) as tf:
            m = next(m for m in tf.getmembers() if m.name.endswith("/bin/pandoc"))
            target.write_bytes(tf.extractfile(m).read())  # type: ignore[union-attr]
    else:
        with zipfile.ZipFile(io.BytesIO(blob)) as zf:
            m = next(n for n in zf.namelist() if n.endswith("/" + member_name) or n.endswith("bin/pandoc"))
            target.write_bytes(zf.read(m))
    target.chmod(0o755)
    return str(target)


def ensure_csl(style: str, download: Callable[[str], bytes] = http_bytes) -> str | None:
    d = neovarch_home() / "csl"
    d.mkdir(parents=True, exist_ok=True)
    f = d / f"{style}.csl"
    if not f.exists():
        try:
            f.write_bytes(download(CSL_URLS[style]))
        except Exception:
            return None  # offline: pandoc's built-in Chicago author-date is used
    return str(f)


# Campus format: Times New Roman 12, 1.5 spacing (line=360), margins top 3 / left 4 /
# bottom 3 / right 3 cm (1 cm = 567 twips), justified body text.
CAMPUS = {"font": "Times New Roman", "size_half_pt": 24, "line": 360,
          "margins_cm": {"top": 3, "left": 4, "bottom": 3, "right": 3}}


def build_reference_docx(pandoc: str, dest: Path) -> Path:
    raw = subprocess.run([pandoc, "--print-default-data-file", "reference.docx"],
                         capture_output=True, check=True, timeout=60).stdout
    zin = zipfile.ZipFile(io.BytesIO(raw))
    out = io.BytesIO()
    font, size, line = CAMPUS["font"], CAMPUS["size_half_pt"], CAMPUS["line"]
    tw = {k: int(v * 567) for k, v in CAMPUS["margins_cm"].items()}
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zout:
        for item in zin.infolist():
            data = zin.read(item.filename)
            if item.filename == "word/styles.xml":
                xml = data.decode("utf-8")
                fonts = (f'<w:rFonts w:ascii="{font}" w:hAnsi="{font}" w:eastAsia="{font}" w:cs="{font}"/>')
                xml = re.sub(r"<w:rFonts [^>]*/>", fonts, xml)
                xml = re.sub(r'<w:sz w:val="\d+"\s*/>', f'<w:sz w:val="{size}"/>', xml, count=1)
                xml = re.sub(r'<w:szCs w:val="\d+"\s*/>', f'<w:szCs w:val="{size}"/>', xml, count=1)
                # body paragraphs: no extra before/after, 1.5 lines
                xml = re.sub(r'<w:spacing w:before="180" w:after="180"\s*/>',
                             f'<w:spacing w:before="0" w:after="0" w:line="{line}" w:lineRule="auto"/>', xml)
                # 1.5 spacing + justified for the default paragraph properties
                xml = re.sub(r"<w:pPrDefault>.*?</w:pPrDefault>",
                             f'<w:pPrDefault><w:pPr><w:spacing w:after="0" w:line="{line}" w:lineRule="auto"/>'
                             '<w:jc w:val="both"/></w:pPr></w:pPrDefault>', xml, flags=re.S)
                # headings: black, same face, bold
                xml = re.sub(r'<w:color w:val="[0-9A-Fa-f]{6}"( w:themeColor="[^"]*")?\s*/>', '<w:color w:val="000000"/>', xml)
                data = xml.encode("utf-8")
            elif item.filename == "word/document.xml":
                xml = data.decode("utf-8")
                pg = (f'<w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="{tw["top"]}" w:right="{tw["right"]}" '
                      f'w:bottom="{tw["bottom"]}" w:left="{tw["left"]}" w:header="708" w:footer="708" w:gutter="0"/>')
                xml = re.sub(r"<w:sectPr\s*/>", "", xml)
                if "<w:pgMar" in xml:
                    xml = re.sub(r"<w:pgSz[^>]*/>", "", xml)
                    xml = re.sub(r"<w:pgMar[^>]*/>", pg, xml)
                else:
                    xml = xml.replace("</w:sectPr>", pg + "</w:sectPr>")
                    if "</w:sectPr>" not in xml:
                        xml = xml.replace("</w:body>", f"<w:sectPr>{pg}</w:sectPr></w:body>")
                data = xml.encode("utf-8")
            zout.writestr(item, data)
    dest.write_bytes(out.getvalue())
    return dest


def pdf_engine() -> str | None:
    if shutil.which("typst"):
        return "typst"
    for exe in ("soffice", "libreoffice"):
        if shutil.which(exe):
            return exe
    return None


def export_report(markdown_path: str, formats: list[str] | None = None, *, style: str | None = None,
                  vault: str | None = None, download: Callable[[str], bytes] = http_bytes) -> dict:
    md = Path(markdown_path).expanduser()
    if not md.is_file():
        raise ReportError(f"no such report: {md}")
    formats = [f.lower() for f in (formats or ["docx", "pdf"])]
    text = md.read_text(encoding="utf-8")
    style = style or (re.search(r'^csl-style:\s*"?(\w+)"?', text, re.M) or [None, "apa"])[1]
    pandoc = ensure_pandoc(download)
    csl = ensure_csl(style or "apa", download)
    folder = md.parent
    ref_docx = build_reference_docx(pandoc, folder / "reference.docx")
    base = [pandoc, md.name, "--citeproc", "--toc", "--number-sections", "--resource-path", str(folder)]
    if csl:
        base += ["--csl", csl]
    out: dict[str, Any] = {"markdown": str(md), "style": style, "csl": csl, "files": {}, "warnings": []}
    docx = folder / (md.stem + ".docx")
    if "docx" in formats or "pdf" in formats:
        r = subprocess.run(base + ["--reference-doc", str(ref_docx), "-o", str(docx)], cwd=folder,
                           capture_output=True, text=True, timeout=180)
        if r.returncode != 0:
            raise ReportError(f"pandoc docx failed: {r.stderr.strip()[-800:]}")
        if r.stderr.strip():
            out["warnings"].append(r.stderr.strip()[-800:])
        if "docx" in formats:
            out["files"]["docx"] = str(docx)
    if "pdf" in formats:
        eng = pdf_engine()
        pdf = folder / (md.stem + ".pdf")
        if eng == "typst":
            r = subprocess.run(base + ["--pdf-engine=typst", "-V", "mainfont=Times New Roman", "-V", "fontsize=12pt",
                                       "-o", str(pdf)], cwd=folder, capture_output=True, text=True, timeout=300)
            ok = r.returncode == 0
        elif eng:
            r = subprocess.run([eng, "--headless", "--convert-to", "pdf", "--outdir", str(folder), str(docx)],
                               capture_output=True, text=True, timeout=300)
            ok = r.returncode == 0 and pdf.exists()
        else:
            ok, r = False, None
        if ok:
            out["files"]["pdf"] = str(pdf)
        else:
            out["warnings"].append("PDF tidak dibuat: pasang Typst (https://typst.app) atau LibreOffice"
                                   + (f" ({r.stderr.strip()[-300:]})" if r is not None and r.stderr else ""))
    if "md" in formats or "markdown" in formats:
        out["files"]["md"] = str(md)
    if vault:
        from neovarch import obsidian as obs
        rel = f"Laporan/{md.parent.name}.md"
        obs.write_note(Path(vault), rel, text, "overwrite", None)
        out["vault_note"] = rel
        out["obsidian_uri"] = obs.open_uri(Path(vault), rel)
    return out


# ------------------------------------------------- reference cache (tools) --
# The agent can only cite what a search actually returned: report_search stores
# every record here, report_create looks keys up here and nowhere else.

def _cache_path() -> Path:
    return reports_dir() / ".references-cache.json"


def remember(refs: list[dict]) -> None:
    p = _cache_path()
    try:
        cache = json.loads(p.read_text(encoding="utf-8")) if p.exists() else {}
    except (OSError, json.JSONDecodeError):
        cache = {}
    for r in refs:
        cache[r["key"]] = r
    p.write_text(json.dumps(cache, ensure_ascii=False), encoding="utf-8")


def recall(keys: list[str]) -> tuple[list[dict], list[str]]:
    p = _cache_path()
    cache = json.loads(p.read_text(encoding="utf-8")) if p.exists() else {}
    found = [cache[k] for k in keys if k in cache]
    return found, [k for k in keys if k not in cache]

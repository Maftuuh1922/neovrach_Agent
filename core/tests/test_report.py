"""Report generator: real-reference search (mocked APIs), BibTeX, no fake citations,
Pandoc export to campus-format DOCX (+ PDF when an engine exists), tools."""

import asyncio
import json
import re
import shutil
import zipfile
from pathlib import Path

import pytest

from neovarch import report as rep
from neovarch.tools import ToolContext, run_tool

OPENALEX = {"results": [
    {"title": "Deep Learning for Rice Leaf Disease Detection", "publication_year": 2021,
     "doi": "https://doi.org/10.1000/RICE.1", "id": "https://openalex.org/W1",
     "authorships": [{"author": {"display_name": "Siti Rahma"}}, {"author": {"display_name": "Budi Santoso"}}],
     "primary_location": {"source": {"display_name": "Jurnal Teknologi Pertanian"}},
     "biblio": {"volume": "12", "issue": "3", "first_page": "101", "last_page": "110"},
     "abstract_inverted_index": {"Rice": [0], "diseases": [1], "matter": [2]}, "type": "article"},
    {"title": "No authors here", "publication_year": 2020, "authorships": []},
]}
CROSSREF = {"message": {"items": [
    {"title": ["Deep learning for rice leaf disease detection"], "DOI": "10.1000/rice.1",
     "author": [{"given": "Siti", "family": "Rahma"}], "issued": {"date-parts": [[2021]]},
     "container-title": ["Jurnal Teknologi Pertanian"], "publisher": "Univ Press", "URL": "https://doi.org/10.1000/rice.1"},
    {"title": ["Convolutional Networks & Crops"], "DOI": "10.2000/CNN.7",
     "author": [{"given": "Ana", "family": "Gómez"}], "issued": {"date-parts": [[2019, 5]]},
     "container-title": ["Proceedings of the Conference on Vision"], "type": "proceedings-article", "page": "5-9"},
]}}
S2 = {"data": [{"title": "Transformers in Agriculture", "year": 2023, "venue": "AgriAI",
                "externalIds": {"DOI": "10.3000/TA.9"}, "authors": [{"name": "Lee Min"}], "url": "https://s2/x"}]}


def fake_fetch(url):
    if "openalex" in url:
        return OPENALEX
    if "crossref" in url:
        return CROSSREF
    if "semanticscholar" in url:
        return S2
    raise AssertionError(url)


def test_search_merges_dedupes_and_keys():
    res = rep.search_references("rice disease", 5, fetch=fake_fetch)
    refs = res["references"]
    titles = [r["title"] for r in refs]
    assert len(refs) == 3, titles                      # duplicate DOI merged, author-less dropped
    rice = refs[0]
    assert rice["doi"] == "10.1000/rice.1" and rice["publisher"] == "Univ Press"  # filled from crossref
    assert rice["abstract"] == "Rice diseases matter"
    assert rice["key"] == "rahma2021deep"
    gomez = next(r for r in refs if r["doi"] == "10.2000/cnn.7")
    assert gomez["key"] == "gomez2019convolutional"
    assert res["errors"] == {}


def test_search_survives_a_failing_source():
    def flaky(url):
        if "crossref" in url:
            raise TimeoutError("slow")
        return fake_fetch(url)
    res = rep.search_references("x", 3, fetch=flaky)
    assert "crossref" in res["errors"] and len(res["references"]) == 2


def test_bibtex_escapes_and_types():
    refs = rep.search_references("rice", 5, fetch=fake_fetch)["references"]
    bib = rep.to_bibtex(refs)
    assert "@article{rahma2021deep," in bib
    assert "@inproceedings{gomez2019convolutional," in bib and "booktitle = {Proceedings" in bib
    assert "Convolutional Networks \\& Crops" in bib
    assert "pages = {101--110}" in bib and "doi = {10.1000/rice.1}" in bib
    assert bib.count("@") == 3


def test_create_rejects_fake_citations(tmp_path):
    refs = rep.search_references("rice", 5, fetch=fake_fetch)["references"]
    with pytest.raises(rep.ReportError, match="smith2020fake"):
        rep.create_report("Skripsi", "# Pendahuluan\nMenurut [@smith2020fake] ...", refs, out_dir=tmp_path)
    res = rep.create_report("Deteksi Penyakit Daun Padi", "# Pendahuluan\nPenelitian [@rahma2021deep; @min2023transformers].\n",
                            refs, author="Regu", out_dir=tmp_path)
    md = Path(res["markdown"]).read_text()
    assert md.startswith("---\ntitle: \"Deteksi Penyakit Daun Padi\"")
    assert 'toc-title: "Daftar Isi"' in md and "::: {#refs}" in md
    assert res["cited"] == ["min2023transformers", "rahma2021deep"]
    assert res["uncited"] == ["gomez2019convolutional"]
    assert Path(res["bibtex"]).read_text().count("@") == 3


def test_cited_keys_parsing():
    body = "Seperti [@a2020x, p. 4; -@b2021y] dan @c2019z menyatakan. Email a@b.com bukan sitasi."
    assert rep.cited_keys(body) == {"a2020x", "b2021y", "c2019z"}


def test_pandoc_asset_names():
    assert rep.pandoc_asset_name("Linux", "x86_64").endswith("linux-amd64.tar.gz")
    assert rep.pandoc_asset_name("Linux", "aarch64").endswith("linux-arm64.tar.gz")
    assert rep.pandoc_asset_name("Darwin", "arm64").endswith("arm64-macOS.zip")
    assert rep.pandoc_asset_name("Windows", "AMD64").endswith("windows-x86_64.zip")


def test_ensure_pandoc_downloads_once(home, monkeypatch, tmp_path):
    import io
    import tarfile
    monkeypatch.setattr(rep.shutil, "which", lambda _n: None)
    monkeypatch.setattr(rep, "pandoc_asset_name", lambda *a: "pandoc-x-linux-amd64.tar.gz")
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz") as tf:
        data = b"#!/bin/sh\necho pandoc\n"
        info = tarfile.TarInfo("pandoc-x/bin/pandoc")
        info.size = len(data)
        tf.addfile(info, io.BytesIO(data))
    calls = []
    path = rep.ensure_pandoc(lambda url: calls.append(url) or buf.getvalue())
    assert Path(path) == home / "bin" / "pandoc" and Path(path).stat().st_mode & 0o111
    assert calls and calls[0].startswith("https://github.com/jgm/pandoc/releases/download/")
    assert rep.ensure_pandoc(lambda url: pytest.fail("downloaded twice")) == path


needs_pandoc = pytest.mark.skipif(not shutil.which("pandoc"), reason="pandoc not installed")


def _docx_xml(path, name):
    with zipfile.ZipFile(path) as z:
        return z.read(name).decode()


@needs_pandoc
def test_export_docx_campus_format(home, tmp_path):
    refs = rep.search_references("rice", 5, fetch=fake_fetch)["references"]
    body = ("# Pendahuluan\n\nPenyakit daun padi menurunkan hasil panen [@rahma2021deep].\n\n"
            "## Latar Belakang\n\nModel transformer mulai dipakai [@min2023transformers].\n\n"
            "# Metode\n\nKami memakai CNN [@gomez2019convolutional].\n")
    res = rep.create_report("Deteksi Penyakit Daun Padi", body, refs, author="Regu", out_dir=tmp_path, style="apa")
    out = rep.export_report(res["markdown"], ["docx", "md"], download=lambda url: (_ for _ in ()).throw(OSError("offline")))
    docx = Path(out["files"]["docx"])
    assert docx.exists() and out["files"]["md"].endswith("report.md")
    styles = _docx_xml(docx, "word/styles.xml")
    doc = _docx_xml(docx, "word/document.xml")
    assert 'w:ascii="Times New Roman"' in styles and re.search(r'<w:sz w:val="24"\s*/>', styles)
    assert 'w:line="360"' in styles
    assert 'w:left="2268"' in doc and 'w:top="1701"' in doc and 'w:right="1701"' in doc
    text = re.sub(r"<[^>]+>", "", doc)
    assert "Daftar Isi" in doc or "TOC" in doc
    assert "Rahma" in text and "Daftar Pustaka" in text          # citeproc resolved real refs
    assert "rahma2021deep" not in text                            # no unresolved keys left


@needs_pandoc
def test_export_pdf_when_engine_available(home, tmp_path):
    if not rep.pdf_engine():
        pytest.skip("no typst/libreoffice")
    refs = rep.search_references("rice", 5, fetch=fake_fetch)["references"]
    res = rep.create_report("PDF", "# Bab\n\nTeks [@rahma2021deep].\n", refs, out_dir=tmp_path)
    out = rep.export_report(res["markdown"], ["pdf"], download=lambda url: (_ for _ in ()).throw(OSError("offline")))
    assert Path(out["files"]["pdf"]).read_bytes()[:4] == b"%PDF"


async def test_tools_only_accept_searched_keys(home, monkeypatch, tmp_path):
    monkeypatch.setattr(rep, "http_json", fake_fetch)
    monkeypatch.setattr(rep.search_references, "__defaults__", (10,))
    ctx = ToolContext(cwd=tmp_path, approve=lambda *a: asyncio.sleep(0, "allow"))
    orig = rep.search_references
    monkeypatch.setattr(rep, "search_references", lambda q, n=8, **k: orig(q, n, fetch=fake_fetch))
    out = await run_tool("report_search", {"query": "rice"}, ctx)
    assert "@rahma2021deep" in out and "real references" in out
    bad = await run_tool("report_create", {"title": "T", "body": "x [@ghost2020none]"}, ctx)
    assert bad.startswith("error") and "ghost2020none" in bad
    ok = await run_tool("report_create", {"title": "Laporan Uji", "body": "# Bab\n\nx [@rahma2021deep]"}, ctx)
    assert "report written" in ok
    md = re.search(r"report written: (\S+)", ok).group(1)
    assert Path(md).exists() and str(home / "reports") in md
    if shutil.which("pandoc"):
        monkeypatch.setattr(rep, "http_bytes", lambda url: (_ for _ in ()).throw(OSError("offline")))
        exp = await run_tool("report_export", {"path": md, "formats": ["docx"]}, ctx)
        assert "docx:" in exp

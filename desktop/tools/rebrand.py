#!/usr/bin/env python3
"""Neovarch rebrand pass for user-facing copy inherited from Hermes Desktop.

Rewrites the *product* name inside string literals only. References to the
Python core it drives (Hermes Agent), to Nous services (Hermes Cloud, the
Hermes catalog / Skills Hub) and to model names (Nous Hermes 4, Hermes-3) are
kept, because those are the real names of things the app talks to.

Usage: python3 tools/rebrand.py FILE...   (idempotent)
"""
import re
import sys

# Ordered phrase rules applied before the generic rule.
PHRASES = [
    (r"\bHermes Desktop\b", "Neovarch Agent"),
    (r"\bHermes desktop app\b", "Neovarch Agent app"),
    (r"\bHermes desktop UI\b", "Neovarch Agent UI"),
    (r"\bHermes desktop\b", "Neovarch Agent"),
    (r"\bHermes app\b", "Neovarch Agent app"),
    (r"\bAbout Hermes\b", "About Neovarch Agent"),
    (r"\bQuit Hermes\b", "Quit Neovarch Agent"),
    (r"\bShow Hermes\b", "Show Neovarch Agent"),
    (r"\bWelcome to Hermes\b", "Welcome to Neovarch Agent"),
    (r"\bInstall Hermes\b(?! (?:Agent|Cloud))", "Install Neovarch core (Hermes Agent)"),
    (r"\binstall Hermes\b(?! (?:Agent|Cloud))", "install Neovarch core (Hermes Agent)"),
    (r"\binstalls Hermes\b(?! (?:Agent|Cloud))", "installs Neovarch core (Hermes Agent)"),
    (r"\bHermes agent\b", "Neovarch core (Hermes Agent)"),
    (r"\bHermes is not installed\b", "Neovarch core (Hermes Agent) is not installed"),
    (r"\bHermes is not installed yet\b", "Neovarch core (Hermes Agent) is not installed yet"),
    (r"(?<![\w\-./@$])Hermes' ", "Neovarch's "),
    (r"\bset ?up with Hermes Agent\b", "set up with Neovarch Agent"),
    (r"\bSetting up Hermes Agent\b", "Setting up Neovarch core (Hermes Agent)"),
]

# Generic: a standalone "Hermes" that is not part of an identifier, header,
# path, model name or a Nous service name.
GENERIC = re.compile(
    r"(?<![\w\-./@$])(?<!Nous )(?<!Classic )Hermes"
    r"(?![\w\-/]|\.(?=[\w/])|\s?\d| Cloud| Agent| catalog| plugin catalog| Skills Hub| Setup| Portal| スキル| 技能)"
)

STRING = re.compile(r"""('(?:[^'\\\n]|\\.)*'|"(?:[^"\\\n]|\\.)*"|`(?:[^`\\]|\\.)*`)""", re.S)


def rewrite_literal(lit: str) -> str:
    body = lit
    for pat, rep in PHRASES:
        body = re.sub(pat, rep, body)
    body = GENERIC.sub("Neovarch", body)
    return body


def rewrite_line_aware(text: str) -> str:
    out = []
    pos = 0
    for m in STRING.finditer(text):
        start = m.start()
        # skip literals that sit in a // comment on the same line
        line_start = text.rfind("\n", 0, start) + 1
        prefix = text[line_start:start]
        if "//" in prefix.replace("://", "") or prefix.lstrip().startswith("*"):
            continue
        out.append(text[pos:start])
        lit = m.group(0)
        # never touch import specifiers / module ids
        if re.match(r"\s*(?:import|from|require\()", prefix[-12:] if len(prefix) > 12 else prefix):
            out.append(lit)
        else:
            out.append(rewrite_literal(lit))
        pos = m.end()
    out.append(text[pos:])
    return "".join(out)


def main(paths):
    changed = 0
    for p in paths:
        src = open(p, encoding="utf-8").read()
        new = rewrite_line_aware(src)
        if new != src:
            open(p, "w", encoding="utf-8").write(new)
            changed += 1
    print(f"rebrand: {changed} file(s) changed")


if __name__ == "__main__":
    main(sys.argv[1:])

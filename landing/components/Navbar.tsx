"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { Download, Menu, X } from "lucide-react";
import { INSTALL_URL, NAV_LINKS } from "@/lib/site";

export default function Navbar() {
  const [scrolled, setScrolled] = useState(false);
  const [open, setOpen] = useState(false);
  const toggleRef = useRef<HTMLButtonElement>(null);
  const drawerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 100);
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  const close = useCallback(() => {
    setOpen(false);
    toggleRef.current?.focus();
  }, []);

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") close();
    };
    const onResize = () => {
      if (window.innerWidth >= 768) setOpen(false);
    };
    document.addEventListener("keydown", onKey);
    window.addEventListener("resize", onResize);
    document.body.style.overflow = "hidden";
    drawerRef.current?.querySelector<HTMLElement>("a")?.focus();
    return () => {
      document.removeEventListener("keydown", onKey);
      window.removeEventListener("resize", onResize);
      document.body.style.overflow = "";
    };
  }, [open, close]);

  return (
    <header className={`nav${scrolled ? " nav--scrolled" : ""}${open ? " nav--open" : ""}`}>
      <nav className="nav__inner container" aria-label="Primary">
        <a className="nav__logo" href="#top" aria-label="Neovarch Agent, back to top">
          NEOVARCH AGENT
        </a>
        <ul className="nav__links">
          {NAV_LINKS.map((l) => (
            <li key={l.label}>
              <a href={l.href} target="_blank" rel="noopener noreferrer" aria-label={`${l.label} (opens in a new tab)`}>
                {l.label}
              </a>
            </li>
          ))}
        </ul>
        <a
          className="btn btn--primary nav__cta"
          href={INSTALL_URL}
          target="_blank"
          rel="noopener noreferrer"
          aria-label="Install Neovarch (opens in a new tab)"
        >
          Install Neovarch
        </a>
        <button
          ref={toggleRef}
          type="button"
          className="nav__toggle"
          aria-label={open ? "Close menu" : "Open menu"}
          aria-expanded={open}
          aria-controls="mobile-drawer"
          onClick={() => setOpen((v) => !v)}
        >
          {open ? <X size={24} aria-hidden="true" /> : <Menu size={24} aria-hidden="true" />}
        </button>
      </nav>

      <div
        id="mobile-drawer"
        ref={drawerRef}
        className="drawer"
        role="dialog"
        aria-modal="true"
        aria-label="Menu"
        aria-hidden={!open}
        inert={!open}
      >
        <ul className="drawer__links">
          {NAV_LINKS.map((l) => (
            <li key={l.label}>
              <a
                href={l.href}
                target="_blank"
                rel="noopener noreferrer"
                aria-label={`${l.label} (opens in a new tab)`}
                onClick={() => setOpen(false)}
              >
                {l.label}
              </a>
            </li>
          ))}
        </ul>
        <a
          className="btn btn--primary drawer__cta"
          href={INSTALL_URL}
          target="_blank"
          rel="noopener noreferrer"
          aria-label="Install Neovarch (opens in a new tab)"
          onClick={() => setOpen(false)}
        >
          <Download size={16} aria-hidden="true" />
          Install Neovarch
        </a>
      </div>
    </header>
  );
}

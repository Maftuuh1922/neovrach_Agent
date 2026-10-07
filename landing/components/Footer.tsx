import { Download } from "lucide-react";
import CopyCommand from "./CopyCommand";
import { INSTALL_CMD, INSTALL_URL, NAV_LINKS } from "@/lib/site";

const PLATFORMS = ["Windows", "Linux", "macOS"] as const;

export default function Footer() {
  return (
    <footer className="footer">
      <div className="container footer__inner">
        <p className="footer__tagline">NEOVARCH AGENT — The office runs itself. You just give orders.</p>

        <nav aria-label="Footer">
          <ul className="footer__nav">
            <li>
              <a href="#top" aria-label="Home, back to top">
                Home
              </a>
            </li>
            {NAV_LINKS.map((l) => (
              <li key={l.label}>
                <a href={l.href} target="_blank" rel="noopener noreferrer" aria-label={`${l.label} (opens in a new tab)`}>
                  {l.label}
                </a>
              </li>
            ))}
          </ul>
        </nav>

        <div className="footer__download">
          <div className="footer__platforms">
            {PLATFORMS.map((p) => (
              <a
                key={p}
                className="btn btn--ghost"
                href={INSTALL_URL}
                target="_blank"
                rel="noopener noreferrer"
                aria-label={`Download Neovarch for ${p} (opens in a new tab)`}
              >
                <Download size={16} aria-hidden="true" />
                {p}
              </a>
            ))}
          </div>
          <CopyCommand command={INSTALL_CMD} />
        </div>

        <div className="footer__legal">
          <p>© 2026 Neovarch Project. Open-source under MIT License.</p>
          <p>Built with inspiration from Nous Research&apos;s Hermes Agent.</p>
        </div>
      </div>
    </footer>
  );
}

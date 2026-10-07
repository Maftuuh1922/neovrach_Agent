"use client";

import { useState } from "react";
import { Check, Copy, Terminal } from "lucide-react";

export default function CopyCommand({ command }: { command: string }) {
  const [copied, setCopied] = useState(false);

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(command);
    } catch {
      // Fallback for browsers without async clipboard (e.g. non-secure contexts).
      const ta = document.createElement("textarea");
      ta.value = command;
      ta.setAttribute("readonly", "");
      ta.style.position = "absolute";
      ta.style.left = "-9999px";
      document.body.appendChild(ta);
      ta.select();
      document.execCommand("copy");
      ta.remove();
    }
    setCopied(true);
    window.setTimeout(() => setCopied(false), 2000);
  };

  return (
    <div className="cmd">
      <Terminal size={16} aria-hidden="true" className="cmd__icon" />
      <code className="cmd__text mono">{command}</code>
      <button type="button" className="cmd__copy" onClick={copy} aria-label={copied ? "Copied install command" : "Copy install command"}>
        {copied ? <Check size={16} aria-hidden="true" /> : <Copy size={16} aria-hidden="true" />}
        <span>{copied ? "Copied" : "Copy"}</span>
      </button>
      <span className="sr-only" aria-live="polite">
        {copied ? "Install command copied to clipboard" : ""}
      </span>
    </div>
  );
}

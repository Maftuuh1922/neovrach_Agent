"use client";

import { useEffect, useRef } from "react";
import Image from "next/image";
import { BookOpen, Download } from "lucide-react";
import { asset, DOCS_URL, INSTALL_URL } from "@/lib/site";

export default function Hero() {
  const bgRef = useRef<HTMLDivElement>(null);

  // Parallax: background drifts with scroll, capped at 100px, GPU-composited.
  useEffect(() => {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    let frame = 0;
    const update = () => {
      frame = 0;
      const y = Math.min(window.scrollY * 0.3, 100);
      if (bgRef.current) bgRef.current.style.transform = `translate3d(0, ${y}px, 0)`;
    };
    const onScroll = () => {
      if (!frame) frame = requestAnimationFrame(update);
    };
    update();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => {
      window.removeEventListener("scroll", onScroll);
      if (frame) cancelAnimationFrame(frame);
    };
  }, []);

  return (
    <section className="hero" id="top" aria-labelledby="hero-title">
      <figure className="hero__figure">
        <div className="hero__bg" ref={bgRef}>
          <Image
            src={asset("/art/eva_hero.webp")}
            alt="Isometric architecture diagram showing PC desktop as agent core and mobile phone as remote control, duotone red and black illustration"
            fill
            priority
            sizes="100vw"
            className="hero__img"
          />
        </div>
        <div className="hero__overlay" aria-hidden="true" />
        <figcaption className="hero__caption mono">FIG.00 — Architecture: PC brain, mobile remote</figcaption>
      </figure>

      <div className="hero__content container">
        <p className="hero__eyebrow" data-reveal>
          NEOVARCH AGENT
        </p>
        <h1 id="hero-title" className="hero__title" data-reveal>
          The office runs itself. You just give orders.
        </h1>
        <p className="hero__sub" data-reveal>
          Your personal AI workforce: agents that code, research, and ship—all controlled from your phone. The brain
          lives on your PC. The remote lives in your pocket.
        </p>
        <div className="hero__ctas" data-reveal>
          <a
            className="btn btn--primary"
            href={INSTALL_URL}
            target="_blank"
            rel="noopener noreferrer"
            aria-label="Install Neovarch (opens in a new tab)"
          >
            <Download size={16} aria-hidden="true" />
            Install Neovarch
          </a>
          <a
            className="btn btn--ghost"
            href={DOCS_URL}
            target="_blank"
            rel="noopener noreferrer"
            aria-label="Read the Docs (opens in a new tab)"
          >
            <BookOpen size={16} aria-hidden="true" />
            Read the Docs
          </a>
        </div>
      </div>
    </section>
  );
}

"use client";

import { useEffect } from "react";

/** Fades in every [data-reveal] element once 20% of it is visible (600ms, translateY 20px → 0). */
export default function Reveal() {
  useEffect(() => {
    const items = Array.from(document.querySelectorAll<HTMLElement>("[data-reveal]"));
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (reduce || !("IntersectionObserver" in window)) {
      items.forEach((el) => el.classList.add("is-visible"));
      return;
    }
    const timers: number[] = [];
    const io = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) {
            const el = entry.target;
            el.classList.add("is-visible");
            io.unobserve(el);
            // Once the 600ms fade finishes, hand transitions back to the element's own hover timing.
            timers.push(window.setTimeout(() => el.classList.add("is-settled"), 650));
          }
        }
      },
      { threshold: 0.2 },
    );
    items.forEach((el) => io.observe(el));
    return () => {
      io.disconnect();
      timers.forEach((t) => window.clearTimeout(t));
    };
  }, []);
  return null;
}

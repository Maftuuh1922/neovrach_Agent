import { Section } from "./Section";

export default function Identity() {
  return (
    <Section id="identity" label="06 · IDENTITY" heading="Hermes is blue. We're red.">
      <div className="prose">
        <p data-reveal>
          Neovarch Agent shares DNA with Hermes Agent—same agent reasoning, same tool ecosystem, same persistent
          memory—but diverges in identity and execution philosophy.
        </p>
        <p data-reveal>
          Where Hermes emphasizes breadth and flexibility, Neovarch emphasizes control and craft. Built for technical
          professionals who want an AI workforce they can direct, debug, and deploy without compromise.
        </p>
        <p data-reveal>Open-source core. MIT license. Community-driven roadmap.</p>
      </div>
    </Section>
  );
}

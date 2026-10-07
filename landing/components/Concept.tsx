import { Section } from "./Section";

export default function Concept() {
  return (
    <Section id="concept" label="01 · THE CONCEPT" heading="One office. Many agents. You're the boss." className="section--96">
      <div className="prose">
        <p data-reveal>
          Neovarch Agent is an open-source agent platform inspired by Nous Research&apos;s Hermes Agent, rebuilt with a
          singular identity.
        </p>
        <p data-reveal>
          The agent core runs on your PC (Windows/Linux/macOS). Your phone becomes the command center. You direct the
          strategy. Your agents execute the details.
        </p>
        <p data-reveal>No cloud dependency. No subscription. Your infrastructure, your control.</p>
      </div>
    </Section>
  );
}

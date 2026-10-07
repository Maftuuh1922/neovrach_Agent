import { Section, Fig } from "./Section";

export default function Workflow() {
  return (
    <Section id="workflow" label="04 · WORKFLOW" heading="Four steps. Then you just give orders.">
      <Fig
        className="fig--wide"
        src="/art/eva_remote.webp"
        alt="Four-step workflow diagram with numbered icons showing Install, Pair, Command, Results process"
        caption="FIG.02 — Workflow: Install → Pair → Command → Results"
      />
      <ol className="grid-4" aria-label="Workflow steps">
        <li className="card step" data-reveal>
          <span className="step__num" aria-hidden="true">
            01
          </span>
          <p className="step__tag mono">INSTALL</p>
          <h3 className="card__title">Run Neovarch on your PC</h3>
          <p className="card__body">
            Windows, Linux, or macOS. This is where the agent core executes: file operations, terminal access, web
            research, code generation.
          </p>
        </li>
        <li className="card step" data-reveal>
          <span className="step__num" aria-hidden="true">
            02
          </span>
          <p className="step__tag mono">PAIR</p>
          <h3 className="card__title">Scan QR to pair your phone</h3>
          <p className="card__body">
            One-time setup. Your phone becomes the remote control. Secure pairing, encrypted communication.
          </p>
        </li>
        <li className="card step" data-reveal>
          <span className="step__num" aria-hidden="true">
            03
          </span>
          <p className="step__tag mono">COMMAND</p>
          <h3 className="card__title">Give orders from anywhere</h3>
          <p className="card__body">Your agents parse intent, break it into tasks, and execute autonomously.</p>
          <div className="examples mono" aria-label="Example orders">
            <p>&gt; &quot;Deploy the staging branch.&quot;</p>
            <p>&gt; &quot;Research competitors and draft a comparison doc.&quot;</p>
            <p>&gt; &quot;Write a blog post about the latest release.&quot;</p>
          </div>
        </li>
        <li className="card step" data-reveal>
          <span className="step__num" aria-hidden="true">
            04
          </span>
          <p className="step__tag mono">RESULTS</p>
          <h3 className="card__title">Results saved and synced</h3>
          <p className="card__body">
            All artifacts—code, documents, research—saved locally. Optional cloud sync via Supabase or Google Drive.
          </p>
          <p className="card__note">Coming soon: real-time multi-device sync.</p>
        </li>
      </ol>
    </Section>
  );
}

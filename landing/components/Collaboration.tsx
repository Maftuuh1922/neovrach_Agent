import { Fig } from "./Section";

export default function Collaboration() {
  return (
    <section id="collaboration" className="section section--deep" aria-labelledby="collaboration-title">
      <div className="container">
        <span className="chip" data-reveal>
          COMING SOON
        </span>
        <p className="label" data-reveal>
          05 · COLLABORATION
        </p>
        <h2 id="collaboration-title" className="heading heading--tight" data-reveal>
          One office. Two bosses.
        </h2>
        <p className="subheading" data-reveal>
          Shared workspace. Zero conflicts.
        </p>
        <Fig
          className="fig--wide"
          src="/art/eva_pairing.webp"
          alt="Collaboration network diagram showing two users connected to shared task queue and branching GitHub workflows"
          caption="FIG.03 — Pairing: Two users, one office, one GitHub repo"
        />
        <div className="grid-2">
          <article className="card" data-reveal>
            <p className="card__tag mono">JOIN</p>
            <h3 className="card__title">Bring a partner into the office</h3>
            <ul className="list">
              <li>Add by ID or QR scan</li>
              <li>They accept the invite</li>
              <li>You share one workspace, one agent pool, one task queue</li>
            </ul>
            <p className="card__footer">Linked to a single GitHub repository. Every commit traceable.</p>
          </article>
          <article className="card" data-reveal>
            <p className="card__tag mono">WORK</p>
            <h3 className="card__title">Parallel execution, zero collisions</h3>
            <ul className="list">
              <li>Unified task queue visible to both users</li>
              <li>Every task logs the originating user</li>
              <li>
                Code changes branch by user: <code className="mono">user-a/feature-x</code>,{" "}
                <code className="mono">user-b/fix-y</code>
              </li>
              <li>Automatic conflict detection before merge</li>
            </ul>
            <p className="card__footer">No overwriting. No confusion. Just clean, collaborative execution.</p>
          </article>
        </div>
      </div>
    </section>
  );
}

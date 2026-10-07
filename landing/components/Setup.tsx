import { Fig } from "./Section";

export default function Setup() {
  return (
    <section id="setup" className="section section--96" aria-labelledby="setup-title">
      <div className="container split">
        <div>
          <p className="label" data-reveal>
            02 · THE SETUP
          </p>
          <h2 id="setup-title" className="heading" data-reveal>
            The brain lives on your PC. The remote lives in your pocket.
          </h2>
          <div className="prose">
            <p data-reveal>Install once. Control from anywhere.</p>
            <p data-reveal>
              Neovarch runs locally—your tasks, your data, your hardware. Pair your phone via QR code, and the office is
              wired.
            </p>
            <p data-reveal>Give orders from the street, the office, or another country. Your agents keep working.</p>
            <p data-reveal>Open-source core. Extensible architecture. Built for professionals who demand control.</p>
          </div>
        </div>
        <Fig
          src="/art/eva_office.webp"
          alt="Split view office interface showing desktop task board and mobile command screen, duotone red and black"
          caption="FIG.01 — The office: Desktop control panel + mobile command interface"
        />
      </div>
    </section>
  );
}

import { Briefcase, Cpu, LayoutGrid, Users } from "lucide-react";
import { Section } from "./Section";

const CARDS = [
  {
    tag: "WORK",
    Icon: Briefcase,
    title: "Orders become execution",
    items: [
      "Real-time streaming chat with live tool activity",
      "Task board: agents execute from a shared queue",
      "Multi-agent collaboration with meeting logs & action items",
      "Scheduled automation via natural-language cron",
    ],
  },
  {
    tag: "STAFF",
    Icon: Users,
    title: "Agents that remember",
    items: [
      "Agent profiles with persistent memory across sessions",
      "Self-generated skills library",
      "File browser with project context",
      "Voice input & text-to-speech output",
    ],
  },
  {
    tag: "MODELS",
    Icon: Cpu,
    title: "Any provider, any model",
    items: ["OpenRouter (200+ models)", "Nous Portal", "OpenAI Platform", "Local inference: Ollama, LM Studio, vLLM"],
  },
  {
    tag: "INTERFACE",
    Icon: LayoutGrid,
    title: "An office that's yours",
    items: [
      "Isometric office visualization",
      "Light/dark themes",
      "Multi-language UI (English, Indonesian)",
      "Customizable workspace layout",
    ],
  },
];

export default function Features() {
  return (
    <Section id="features" label="03 · FEATURES" heading="Everything an office needs. Nothing it doesn't.">
      <p className="subheading" data-reveal>
        Ten capabilities, organized by function.
      </p>
      <div className="grid-2">
        {CARDS.map(({ tag, Icon, title, items }) => (
          <article className="card" key={tag} data-reveal>
            <div className="card__tag mono">
              <Icon size={18} aria-hidden="true" />
              {tag}
            </div>
            <h3 className="card__title">{title}</h3>
            <ul className="list">
              {items.map((i) => (
                <li key={i}>{i}</li>
              ))}
            </ul>
          </article>
        ))}
      </div>
    </Section>
  );
}

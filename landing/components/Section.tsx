import Image from "next/image";
import { asset } from "@/lib/site";

type SectionProps = {
  id: string;
  label: string;
  heading: string;
  className?: string;
  children: React.ReactNode;
};

/** Semantic section with the "0X · NAME" label and H2 heading. */
export function Section({ id, label, heading, className, children }: SectionProps) {
  return (
    <section id={id} className={`section ${className ?? ""}`} aria-labelledby={`${id}-title`}>
      <div className="container">
        <p className="label" data-reveal>
          {label}
        </p>
        <h2 id={`${id}-title`} className="heading" data-reveal>
          {heading}
        </h2>
        {children}
      </div>
    </section>
  );
}

type FigProps = {
  src: string;
  alt: string;
  caption: string;
  className?: string;
};

/** Framed duotone artwork with a mono FIG caption. */
export function Fig({ src, alt, caption, className }: FigProps) {
  return (
    <figure className={`fig ${className ?? ""}`} data-reveal>
      <div className="fig__frame">
        <Image src={asset(src)} alt={alt} width={1028} height={1028} sizes="(max-width: 767px) 100vw, 640px" className="fig__img" />
      </div>
      <figcaption className="fig__caption mono">{caption}</figcaption>
    </figure>
  );
}

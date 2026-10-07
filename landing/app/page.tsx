import Navbar from "@/components/Navbar";
import Hero from "@/components/Hero";
import Concept from "@/components/Concept";
import Setup from "@/components/Setup";
import Features from "@/components/Features";
import Workflow from "@/components/Workflow";
import Collaboration from "@/components/Collaboration";
import Identity from "@/components/Identity";
import Footer from "@/components/Footer";
import Reveal from "@/components/Reveal";

export default function Home() {
  return (
    <>
      <a className="skip-link" href="#main">
        Skip to content
      </a>
      <Navbar />
      <main id="main">
        <Hero />
        <Concept />
        <Setup />
        <Features />
        <Workflow />
        <Collaboration />
        <Identity />
      </main>
      <Footer />
      <Reveal />
    </>
  );
}

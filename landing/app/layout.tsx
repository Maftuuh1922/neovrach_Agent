import type { Metadata, Viewport } from "next";
import { Inter, JetBrains_Mono } from "next/font/google";
import { asset } from "@/lib/site";
import "./globals.css";

const inter = Inter({
  subsets: ["latin"],
  weight: ["400", "500", "600", "700", "800"],
  variable: "--font-inter",
  display: "swap",
});

const jetbrainsMono = JetBrains_Mono({
  subsets: ["latin"],
  weight: ["400", "500", "700"],
  variable: "--font-jetbrains-mono",
  display: "swap",
});

// Absolute origin for social preview URLs. Override with SITE_URL at build time.
const siteUrl = process.env.SITE_URL ?? "https://maftuuh1922.github.io";
const ogImage = asset("/art/og.jpg");

export const metadata: Metadata = {
  metadataBase: new URL(siteUrl),
  title: "Neovarch Agent — AI Workforce Under Your Command",
  description:
    "Neovarch Agent: Open-source AI agent platform. Autonomous coding, research, and task execution controlled from your phone. Local inference, zero cloud dependency.",
  keywords: [
    "AI agent platform",
    "autonomous AI agents",
    "local AI agent",
    "open-source AI agent",
    "AI task automation",
    "AI coding assistant",
  ],
  openGraph: {
    title: "Neovarch Agent — The office runs itself",
    description:
      "Open-source AI agent platform with mobile control. Local execution, autonomous task completion, zero cloud dependency.",
    type: "website",
    images: [{ url: ogImage, width: 1200, height: 630, alt: "Neovarch Agent — duotone red and black mecha artwork" }],
  },
  twitter: {
    card: "summary_large_image",
    title: "Neovarch Agent — AI Workforce Under Your Command",
    description: "Open-source AI agents. Mobile control. Local execution.",
    images: [ogImage],
  },
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  themeColor: "#000000",
  colorScheme: "dark",
};

// Marks <html> as JS-enabled before first paint so reveal animations only hide content when JS can show it again.
const jsFlag = `document.documentElement.classList.add('js')`;

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html
      lang="en"
      data-scroll-behavior="smooth"
      className={`${inter.variable} ${jetbrainsMono.variable}`}
      suppressHydrationWarning
    >
      <head>
        <script dangerouslySetInnerHTML={{ __html: jsFlag }} />
      </head>
      <body>{children}</body>
    </html>
  );
}

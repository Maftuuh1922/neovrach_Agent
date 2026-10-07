export const REPO_URL = "https://github.com/Maftuuh1922/neorachAgent_lp";
export const INSTALL_URL = REPO_URL;
export const DOCS_URL = `${REPO_URL}#readme`;
export const GITHUB_URL = REPO_URL;
export const COMMUNITY_URL = `${REPO_URL}#community`;
export const CHANGELOG_URL = `${REPO_URL}#changelog`;
export const INSTALL_CMD = "curl -fsSL https://install.neovarch.ai | sh";

export const NAV_LINKS = [
  { label: "Docs", href: DOCS_URL },
  { label: "GitHub", href: GITHUB_URL },
  { label: "Community", href: COMMUNITY_URL },
  { label: "Changelog", href: CHANGELOG_URL },
] as const;

/** Prefix a public/ asset path with the configured basePath (needed for GitHub Pages sub-paths). */
export function asset(path: string): string {
  return `${process.env.NEXT_PUBLIC_BASE_PATH ?? ""}${path}`;
}

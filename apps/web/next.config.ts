import type { NextConfig } from "next";
// Only named local build slots are allowed; never overwrite the running slot.
const buildDirectories: Record<string, string> = {
  presentation: ".next-presentation",
  clarity: ".next-clarity",
  disclosures: ".next-disclosures",
  evidence: ".next-evidence",
  "evidence-final": ".next-evidence-final",
};
const config: NextConfig = {
  poweredByHeader: false,
  distDir: buildDirectories[process.env.SAVVY_BUILD_DIRECTORY || ""] || ".next",
};
export default config;

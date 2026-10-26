import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // This folder is the project root (silences the stray-lockfile warning).
  turbopack: { root: __dirname },
  // Always put the title, description and social tags in <head>, for every
  // visitor, so link-preview scrapers and AI crawlers that only read the
  // head (WhatsApp, LinkedIn, Slack…) always see them.
  htmlLimitedBots: /.*/,
};

export default nextConfig;

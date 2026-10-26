import type { MetadataRoute } from "next";
import { site } from "./site";

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: site.name,
    short_name: site.name,
    description: site.description,
    start_url: "/",
    display: "standalone",
    background_color: site.themeColor,
    theme_color: site.themeColor,
    icons: [{ src: "/icon.png", sizes: "1024x1024", type: "image/png", purpose: "any" }],
  };
}

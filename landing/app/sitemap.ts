import type { MetadataRoute } from "next";
import { absolute, site } from "./site";

export default function sitemap(): MetadataRoute.Sitemap {
  return [
    {
      url: site.url,
      lastModified: new Date(),
      changeFrequency: "monthly",
      priority: 1,
      images: [absolute(site.ogImage.url)],
      videos: [
        {
          title: site.video.name,
          description: site.video.description,
          thumbnail_loc: absolute(site.video.thumbnail),
          content_loc: absolute(site.video.url),
          duration: 33,
          publication_date: site.video.uploadDate,
        },
      ],
    },
  ];
}

import { absolute, site } from "./site";

/// schema.org data for search engines and AI answer engines: the app
/// itself, the demo video, the FAQ, the site and who makes it.
export default function StructuredData() {
  const graph = {
    "@context": "https://schema.org",
    "@graph": [
      {
        "@type": "Organization",
        "@id": `${site.publisher.url}/#organization`,
        name: site.publisher.name,
        url: site.publisher.url,
      },
      {
        "@type": "Person",
        "@id": `${site.url}/#author`,
        name: site.author.name,
        url: site.author.url,
      },
      {
        "@type": "WebSite",
        "@id": `${site.url}/#website`,
        url: site.url,
        name: site.name,
        description: site.description,
        inLanguage: "en",
        publisher: { "@id": `${site.publisher.url}/#organization` },
      },
      {
        "@type": "WebPage",
        "@id": `${site.url}/#webpage`,
        url: site.url,
        name: site.title,
        description: site.description,
        isPartOf: { "@id": `${site.url}/#website` },
        about: { "@id": `${site.url}/#app` },
        primaryImageOfPage: absolute(site.ogImage.url),
        video: { "@id": `${site.url}/#video` },
        inLanguage: "en",
      },
      {
        "@type": ["MobileApplication", "SoftwareApplication"],
        "@id": `${site.url}/#app`,
        name: site.name,
        description: site.description,
        url: site.url,
        downloadUrl: site.downloadUrl,
        installUrl: site.downloadUrl,
        applicationCategory: "UtilitiesApplication",
        applicationSubCategory: "Remote desktop",
        operatingSystem: "iOS 26",
        featureList: [...site.features],
        screenshot: absolute(site.ogImage.url),
        image: absolute(site.ogImage.url),
        license: "https://opensource.org/licenses/MIT",
        isAccessibleForFree: true,
        offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
        author: { "@id": `${site.url}/#author` },
        publisher: { "@id": `${site.publisher.url}/#organization` },
        sameAs: [site.sourceUrl],
      },
      {
        "@type": "VideoObject",
        "@id": `${site.url}/#video`,
        name: site.video.name,
        description: site.video.description,
        thumbnailUrl: absolute(site.video.thumbnail),
        contentUrl: absolute(site.video.url),
        uploadDate: site.video.uploadDate,
        duration: site.video.duration,
        publisher: { "@id": `${site.publisher.url}/#organization` },
      },
      {
        "@type": "FAQPage",
        "@id": `${site.url}/#faq`,
        mainEntity: site.faq.map(({ q, a }) => ({
          "@type": "Question",
          name: q,
          acceptedAnswer: { "@type": "Answer", text: a },
        })),
      },
    ],
  };

  return (
    <script
      type="application/ld+json"
      // JSON-LD must be raw JSON; "<" is escaped so it can't close the tag.
      dangerouslySetInnerHTML={{ __html: JSON.stringify(graph).replace(/</g, "\\u003c") }}
    />
  );
}

import styles from "./page.module.css";

const DOWNLOAD_URL = "https://github.com/zakisheriff/Pocket-Mac";

export default function Home() {
  return (
    <main className={styles.main}>
      <div className={styles.phone} aria-label="Pocket Mac running on iPhone 17 Pro">
        <div className={styles.screen}>
          <video
            className={styles.video}
            src="/demo.mp4"
            poster="/demo-poster.jpg"
            autoPlay
            muted
            loop
            playsInline
          />
          <span className={styles.island} />
        </div>
      </div>

      <div className={styles.side}>
        <h1 className={styles.title}>Pocket Mac</h1>
        <a className={styles.download} href={DOWNLOAD_URL}>
          Download
        </a>
      </div>
    </main>
  );
}

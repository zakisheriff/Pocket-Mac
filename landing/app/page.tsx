import PhoneDemo from "./PhoneDemo";
import styles from "./page.module.css";

const DOWNLOAD_URL = "https://github.com/zakisheriff/Pocket-Mac";

export default function Home() {
  return (
    <main className={styles.main}>
      <PhoneDemo />

      <div className={styles.side}>
        <h1 className={styles.title}>Pocket Mac</h1>
        <a className={styles.download} href={DOWNLOAD_URL}>
          Download
        </a>
      </div>
    </main>
  );
}

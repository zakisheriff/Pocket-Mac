import PhoneDemo from "./PhoneDemo";
import { site } from "./site";
import styles from "./page.module.css";

export default function Home() {
  return (
    <main className={styles.main}>
      <PhoneDemo />

      <div className={styles.side}>
        <h1 className={styles.title}>Pocket Mac</h1>
        <a className={styles.download} href={site.downloadUrl} aria-label="Download Pocket Mac for iPhone">

          Download
        </a>
      </div>
    </main>
  );
}

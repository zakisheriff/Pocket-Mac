"use client";

import { useEffect, useRef, useState } from "react";
import styles from "./page.module.css";

/// The demo turns the phone sideways here (seconds into demo.mp4), just
/// before iOS rotates the screen, so it plays like a real phone turning.
const TURN_AT = 6.2;

export default function PhoneDemo() {
  const video = useRef<HTMLVideoElement>(null);
  const [landscape, setLandscape] = useState(false);

  useEffect(() => {
    let frame = 0;
    const tick = () => {
      const time = video.current?.currentTime ?? 0;
      setLandscape(time >= TURN_AT);
      frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  }, []);

  return (
    <div className={styles.stage}>
      <div
        className={`${styles.phone} ${landscape ? styles.landscape : ""}`}
        aria-label="Pocket Mac running on iPhone 17 Pro"
      >
        <video
          ref={video}
          className={styles.screen}
          src="/demo.mp4"
          poster="/demo-poster.jpg"
          autoPlay
          muted
          loop
          playsInline
        />
      </div>
    </div>
  );
}

import type { Metadata } from "next"
import { ProductPage } from "@/components/product-page"

const title = "Video recording for Mac — Better Shot"
const description = "Record your screen, camera, microphone, and system audio. Edit clips, style your cursor, add zooms, and export without a watermark. Free and open source."
export const metadata: Metadata = {
  title, description,
  alternates: { canonical: "/video-recording" },
  openGraph: { title, description, url: "/video-recording" },
  twitter: { title, description },
}

export default function VideoRecordingPage() {
  return <ProductPage kind="video" />
}

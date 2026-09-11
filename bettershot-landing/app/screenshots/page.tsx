import type { Metadata } from "next"
import { ProductPage } from "@/components/product-page"

const title = "Screenshots for Mac — Better Shot"
const description = "Capture, annotate, crop, blur, and frame screenshots with Better Shot. Full-resolution editing, soft backgrounds, OCR, and easy sharing. Free and open source."
export const metadata: Metadata = {
  title, description,
  alternates: { canonical: "/screenshots" },
  openGraph: { title, description, url: "/screenshots" },
  twitter: { title, description },
}

export default function ScreenshotsPage() {
  return <ProductPage kind="image" />
}

import Image from "next/image"
import Link from "next/link"
import { ArrowRight } from "lucide-react"
import { cn } from "@/lib/utils"
import { FeatureGallery } from "@/components/feature-gallery"

export type ProductKind = "video" | "image"

const features = {
  video: [
    { src: "video-editor.jpg", title: "Your recording, refined", body: "Open your take in the native editor. Your preview, inspector, and timeline stay together." },
    { src: "video-background-detail.webp", title: "Add your look", body: "Choose a gradient and adjust padding, corners, and shadow for a polished frame." },
    { src: "video-timeline-detail.webp", title: "Find the right pace", body: "Trim pauses, split clips, and adjust speed without changing your source recording." },
    { src: "video-effects-detail.webp", title: "Keep details private", body: "Crop the frame, or blur and pixelate selected areas before you share." },
    { src: "video-export.webp", title: "MP4 or MOV", body: "Choose your format, resolution, and quality. Export at 30 or 60 fps, with no watermark." },
  ],
  image: [
    { src: "screenshot-editor.jpg", title: "A home for your screenshots", body: "Capture the important bit, then finish it in a native editor with full-resolution previews." },
    { src: "screenshot-tools-detail.webp", title: "Make your point", body: "Add arrows, text, shapes, and numbered markers from one compact toolbar." },
    { src: "screenshot-background-detail.webp", title: "Give it a background", body: "Choose a soft gradient, then dial in padding, corners, and shadow. Or keep it unframed." },
    { src: "screenshot-canvas-detail.webp", title: "Keep the detail", body: "Work with your original capture pixels while you annotate and adjust the framing." },
    { src: "screenshot-copy-detail.webp", title: "Ready to send", body: "Copy your finished screenshot straight into another app. Save or export when you need a file." },
  ],
} as const

export function ProductPreview({ kind, priority = false, className }: { kind: ProductKind; priority?: boolean; className?: string }) {
  if (kind === "video") return (
    <figure className={cn("product-preview preview-lilac", className)}>
      <video controls playsInline preload="none" poster="/features/recording-demo-poster.jpg"
        width={1280} height={800} aria-label="Play the 24-second animated tour of BetterShot’s real editors"
        className="aspect-[8/5] w-full rounded-xl bg-zinc-900 shadow-lg">
        <source src="/features/recording-demo.mp4" type="video/mp4" />
        Your browser cannot play this video. Use the video link below.
      </video>
      <figcaption className="mt-5 text-center text-xs leading-relaxed text-zinc-950">
        A closer look at BetterShot’s real editors. Animated from actual app captures.
        {" "}<a href="/features/recording-demo.mp4" className="underline underline-offset-2">Open video</a>
      </figcaption>
    </figure>
  )
  return (
    <figure className={cn("product-preview preview-peach", className)}>
      <Image src="/features/screenshot-editor.jpg" alt="BetterShot’s screenshot editor with its annotation toolbar, left background inspector, and a framed coastal image"
        width={1214} height={768} priority={priority} sizes="(max-width: 768px) 92vw, 1100px" className="h-auto w-full rounded-xl shadow-lg" />
      <figcaption className="mt-5 text-center text-xs text-zinc-950">The actual BetterShot screenshot editor, shown with bundled practice media.</figcaption>
    </figure>
  )
}

export function ProductFeatures({ kind }: { kind: ProductKind }) {
  const title = kind === "video" ? "Everything your recording needs" : "Everything your screenshot needs"
  return (
    <section className="product-features" aria-label={title}>
      <div className="feature-panel">
        <h2 className="mb-7 text-2xl font-semibold sm:mb-8 sm:text-[28px]">{title}</h2>
        <FeatureGallery title={title}>
          {features[kind].map(feature => <article key={feature.src} role="group" aria-roledescription="slide" aria-label={feature.title} className="feature-card min-w-0 shrink-0 grow-0 pl-4">
            <div className="feature-media relative flex items-center justify-center overflow-hidden rounded-2xl p-5 sm:p-6">
              <Image src={`/features/${feature.src}`} alt={`BetterShot: ${feature.title.toLowerCase()}`} width={640} height={560} sizes="(min-width: 1280px) 24vw, (min-width: 640px) 42vw, 80vw" className="max-h-full w-auto max-w-full rounded-lg object-contain shadow-xl" />
            </div>
            <h3 className="mt-5 px-1 text-[15px] font-semibold leading-snug">{feature.title}</h3>
            <p className="mt-2 px-1 text-[13px] leading-relaxed text-zinc-600">{feature.body}</p>
          </article>)}
        </FeatureGallery>
      </div>
    </section>
  )
}

export function ProductLink({ kind }: { kind: ProductKind }) {
  return <Link href={kind === "video" ? "/video-recording" : "/screenshots"} className="inline-flex items-center gap-2 text-sm font-semibold text-brand hover:text-brand-700">
    Explore {kind === "video" ? "video recording" : "screenshots"}<ArrowRight size={17} aria-hidden />
  </Link>
}

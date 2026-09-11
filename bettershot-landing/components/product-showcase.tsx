import Image from "next/image"
import Link from "next/link"
import { ArrowRight } from "lucide-react"
import { cn } from "@/lib/utils"
import { FeatureGallery } from "@/components/feature-gallery"

export type ProductKind = "video" | "image"

const features = {
  video: [
    { src: "video-editor-dark.webp", title: "Your recording, refined", body: "Your preview, inspector, and timeline together in the native video editor." },
    { src: "video-background-dark.webp", title: "Add your look", body: "Choose a gradient and adjust padding, corners, and shadow." },
    { src: "video-timeline-dark.webp", title: "Find the right pace", body: "Split clips and trim the pauses while keeping your source recording." },
    { src: "video-zoom-dark.webp", title: "Bring it closer", body: "Add a zoom and adjust its focus, strength, and duration on the timeline." },
    { src: "video-export-dark.webp", title: "MP4 or MOV", body: "Choose your format, resolution, and quality. Export without a watermark." },
  ],
  image: [
    { src: "screenshot-editor-dark.webp", title: "A home for your screenshots", body: "Finish your capture in the native editor, with the original pixels close at hand." },
    { src: "screenshot-tools-detail-dark.webp", title: "Make your point", body: "Arrows, text, shapes, and numbered markers in one compact toolbar." },
    { src: "screenshot-background-dark.webp", title: "Give it a background", body: "Soft gradients, padding, corners, and shadow. Your screenshot, your look." },
    { src: "screenshot-canvas-dark.webp", title: "Keep the detail", body: "Add the context your reader needs while preserving the original capture." },
    { src: "screenshot-copy-dark.webp", title: "Ready to send", body: "Copy into another app, or save and export when you need a file." },
  ],
} as const

export function ProductPreview({ kind, priority = false, className }: { kind: ProductKind; priority?: boolean; className?: string }) {
  return <figure className={cn("product-preview", kind === "image" ? "preview-peach" : "preview-lilac", className)}>
    <Image src={`/features/${kind === "image" ? "screenshot" : "video"}-editor-dark.webp`}
      alt={`BetterShot’s real ${kind === "image" ? "screenshot" : "video"} editor in dark mode, with the inspector on the left`}
      width={1600} height={kind === "image" ? 991 : 1000} priority={priority}
      sizes="(max-width: 768px) 92vw, 1100px" className="h-auto w-full rounded-xl shadow-lg" />
  </figure>
}

export function EditorToolsBanner({ kind }: { kind: ProductKind }) {
  return <figure className="mx-auto my-12 max-w-[1360px] px-6 sm:my-16">
    <div className="editor-tools-backdrop flex aspect-[2.5/1] items-center justify-center overflow-hidden rounded-2xl p-6 sm:aspect-[3.5/1] sm:p-16">
      <Image src={`/features/${kind === "image" ? "screenshot-tools-dark" : "video-timeline-wide-dark"}.webp`}
        alt={kind === "image" ? "BetterShot’s actual annotation toolbar in dark mode" : "BetterShot’s actual timeline, playback controls, and zoom blocks in dark mode"}
        width={kind === "image" ? 665 : 1710} height={kind === "image" ? 53 : 290}
        sizes="(max-width: 768px) 84vw, 1100px" className="h-auto w-full rounded-xl shadow-2xl" />
    </div>
    <figcaption className="mt-4 text-center text-sm text-zinc-600">{kind === "image" ? "Every annotation tool, close at hand." : "Your clips, zooms, and playback. One timeline."}</figcaption>
  </figure>
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

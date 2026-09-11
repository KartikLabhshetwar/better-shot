import Image from "next/image"
import Link from "next/link"
import { ArrowRight } from "lucide-react"
import { cn } from "@/lib/utils"
import { FeatureGallery } from "@/components/feature-gallery"

export type ProductKind = "video" | "image"

const features = {
  video: [
    { src: "video-background-detail.webp", title: "Make it yours", body: "Choose a background, then adjust padding, corners, and shadow in the video inspector." },
    { src: "video-timeline-detail.webp", title: "Keep the good parts", body: "Split and trim clips, change their speed, and refine your zooms in the built-in timeline." },
    { src: "video-effects-detail.webp", title: "Focus on what matters", body: "Crop the frame or blur and pixelate selected areas before sharing." },
    { src: "video-export.webp", title: "Ready for its next screen", body: "Export MP4 or MOV with resolution, quality, and 30 or 60 fps controls. No watermark." },
  ],
  image: [
    { src: "screenshot-tools-detail.webp", title: "Point out the important bit", body: "Use the native toolbar for arrows, text, shapes, numbered markers, blur, and pixelation." },
    { src: "screenshot-background-detail.webp", title: "Give it some breathing room", body: "Choose a soft gradient and adjust padding, corners, and shadow. Or keep it unframed." },
    { src: "screenshot-canvas-detail.webp", title: "A clearer picture", body: "Keep full-resolution image previews while you annotate, frame, and prepare your screenshot to share." },
  ],
} as const

export function ProductPreview({ kind, priority = false, className }: { kind: ProductKind; priority?: boolean; className?: string }) {
  if (kind === "video") return (
    <figure className={cn("product-preview preview-lilac", className)}>
      <video controls playsInline preload="none" poster="/features/recording-demo-poster.jpg"
        width={1280} height={900} aria-label="Play the 20-second tour of BetterShot’s real editors"
        className="aspect-[64/45] w-full rounded-xl bg-zinc-900 shadow-lg">
        <source src="/features/recording-demo.mp4" type="video/mp4" />
        Your browser cannot play this video. Use the video link below.
      </video>
      <figcaption className="mt-5 text-center text-xs leading-relaxed text-zinc-600">
        A tour of BetterShot’s real editors, made from app screenshots with Remotion.
        {" "}<a href="/features/recording-demo.mp4" className="underline underline-offset-2">Open video</a>
      </figcaption>
    </figure>
  )
  return (
    <figure className={cn("product-preview preview-peach", className)}>
      <Image src="/features/screenshot-editor.jpg" alt="BetterShot’s screenshot editor with its annotation toolbar, left background inspector, and a framed coastal image"
        width={1214} height={768} priority={priority} sizes="(max-width: 768px) 92vw, 1100px" className="h-auto w-full rounded-xl shadow-lg" />
      <figcaption className="mt-5 text-center text-xs text-zinc-600">The actual BetterShot screenshot editor, shown with bundled practice media.</figcaption>
    </figure>
  )
}

export function ProductFeatures({ kind }: { kind: ProductKind }) {
  const title = kind === "video" ? "Inside your video editor." : "Everything a screenshot needs."
  return (
    <section className="mx-auto max-w-[1280px] px-6 py-16 sm:py-24" aria-label={title}>
      <div className="mb-10 max-w-xl">
        <p className="mb-3 text-sm font-medium text-brand">{kind === "video" ? "Made for your next take" : "Made for your next screenshot"}</p>
        <h2 className="text-[32px] sm:text-[40px]">{title}</h2>
        <p className="mt-4 text-sm leading-relaxed text-zinc-500">A closer look at the controls in BetterShot.</p>
      </div>
      <FeatureGallery title={title}>
        {features[kind].map(feature => <article key={feature.src} role="group" aria-roledescription="slide" aria-label={feature.title} className="min-w-0 shrink-0 grow-0 basis-[88%] pl-4 sm:basis-[48%] lg:basis-[32%]">
          <div className="relative flex aspect-[1.12] items-center justify-center overflow-hidden rounded-2xl bg-zinc-100 p-5">
            <Image src={`/features/${feature.src}`} alt={`BetterShot ${feature.title.toLowerCase()} controls`} width={640} height={560} sizes="(max-width: 640px) 80vw, 380px" className="max-h-full w-auto max-w-full rounded-lg object-contain shadow-sm" />
          </div>
          <h3 className="mt-5 px-1 text-lg font-semibold leading-snug">{feature.title}</h3>
          <p className="mt-2 px-1 text-sm leading-relaxed text-zinc-500">{feature.body}</p>
        </article>)}
      </FeatureGallery>
    </section>
  )
}

export function ProductLink({ kind }: { kind: ProductKind }) {
  return <Link href={kind === "video" ? "/video-recording" : "/screenshots"} className="inline-flex items-center gap-2 text-sm font-semibold text-brand hover:text-brand-700">
    Explore {kind === "video" ? "video recording" : "screenshots"}<ArrowRight size={17} aria-hidden />
  </Link>
}

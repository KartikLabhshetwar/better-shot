import { Check } from "lucide-react"
import { SiteNav } from "@/components/site-nav"
import { SiteFooter } from "@/components/site-footer"
import { DownloadDropdown } from "@/components/download-dropdown"
import { ProductFeatures, ProductLink, ProductPreview, type ProductKind } from "@/components/product-showcase"
import { getLatestRelease } from "@/lib/downloads"

const content = {
  video: {
    label: "Video recording",
    title: "Less explaining. More showing.",
    description: "Turn a quick screen recording into a walkthrough worth watching. Capture your screen and camera, guide the eye, and tidy up the take. All on your Mac.",
    detailTitle: "The first take is just the start.",
    detail: "A good demo doesn’t need a perfect take. Keep your source recording, cut the detours, and bring the important moments into focus.",
    benefits: ["Trim and split clips, then adjust their speed", "Follow the action with cursor zoom and click effects", "Choose a camera layout that fits your story", "Add captions and mask private details before export"],
    steps: [
      { title: "Set your scene", body: "Open Recording options with ⌘⇧5. Choose a display, window, or adjustable area, then select camera and audio inputs." },
      { title: "Take your time", body: "Record your walkthrough. Pause when you need a moment, then resume from the same compact recording bar." },
      { title: "Make the final cut", body: "Open the recording in the editor. Refine clips, zooms, and framing, then export locally or share to your configured R2 bucket." },
    ],
    cta: "Your next great walkthrough starts here.",
  },
  image: {
    label: "Screenshots",
    title: "A screenshot. A little more clarity.",
    description: "Capture the important bit. Add an arrow, hide a detail, give it a beautiful background. Everything between taking a screenshot and sending a clear message.",
    detailTitle: "Make your point. Keep your pixels.",
    detail: "Work with full-resolution previews and keep the original capture editable. From a quick bug report to a polished product image, the finishing tools are right there.",
    benefits: ["Arrows, shapes, text, highlights, and numbered markers", "Blur and pixelate tools for selected areas", "Ten soft gradients, plus padding, corners, and shadow", "Copy without exporting; save when you’re ready"],
    steps: [
      { title: "Capture what matters", body: "Press ⌘⇧4 for a region screenshot, or choose fullscreen or window capture from BetterShot’s menu bar." },
      { title: "Add the context", body: "Choose Edit from the floating capture deck. Add annotations, cover private details, and adjust your framing." },
      { title: "Send it your way", body: "Copy to the clipboard, pin for reference, or drag into another app. Choose Save or Export when you want a file." },
    ],
    cta: "Make your next screenshot say more.",
  },
}

export async function ProductPage({ kind }: { kind: ProductKind }) {
  const page = content[kind]
  const release = await getLatestRelease()
  return <div className="min-h-dvh bg-white text-zinc-900">
    <SiteNav />
    <main id="main">
      <header className="mx-auto max-w-[1100px] px-6 pb-12 pt-28 text-center sm:pt-36">
        <p className="mb-5 text-sm font-medium text-brand">{page.label} for macOS</p>
        <h1 className="mx-auto max-w-[16ch] text-[clamp(2.75rem,6vw,4.75rem)] leading-[1.06]">{page.title}</h1>
        <p className="mx-auto mt-6 max-w-xl text-[17px] leading-relaxed text-zinc-500">{page.description}</p>
        <div className="mt-8 flex flex-wrap items-center justify-center gap-6"><DownloadDropdown release={release} source="hero" /><a href="#workflow" className="text-sm font-medium text-zinc-600 hover:text-brand">See the workflow ↓</a></div>
        <p className="mt-5 text-xs text-zinc-500">Free and open source · No watermark · macOS 26.0+</p>
      </header>
      <div className="mx-auto max-w-[1100px] px-6"><ProductPreview kind={kind} priority /></div>
      <ProductFeatures kind={kind} />
      <section className="bg-zinc-50 py-16 sm:py-24">
        <div className="mx-auto grid max-w-[1100px] items-center gap-10 px-6 md:grid-cols-2">
          <div><h2 className="max-w-[15ch] text-[36px] sm:text-[44px]">{page.detailTitle}</h2><p className="mt-5 max-w-md text-base leading-relaxed text-zinc-500">{page.detail}</p></div>
          <ul className="space-y-6">{page.benefits.map(benefit => <li key={benefit} className="flex gap-3 text-[15px] leading-relaxed"><Check size={20} className="mt-0.5 shrink-0 text-brand" aria-hidden />{benefit}</li>)}</ul>
        </div>
      </section>
      <section id="workflow" className="mx-auto max-w-[1100px] scroll-mt-20 px-6 py-16 sm:py-24">
        <h2 className="text-[32px] sm:text-[40px]">From “look at this” to ready to share.</h2>
        <ol className="mt-12 grid gap-10 md:grid-cols-3">{page.steps.map((step, i) => <li key={step.title}><span className="mb-5 flex size-9 items-center justify-center rounded-full bg-brand-100 font-mono text-sm text-brand" aria-hidden>{i + 1}</span><h3 className="text-xl font-medium">{step.title}</h3><p className="mt-3 text-sm leading-relaxed text-zinc-500">{step.body}</p></li>)}</ol>
      </section>
      <section className="border-t border-zinc-100 px-6 py-20 text-center">
        <h2 className="mx-auto max-w-[22ch] text-[32px] sm:text-[40px]">{page.cta}</h2>
        <p className="mt-4 text-zinc-500">One free app. Both editors. Your work stays yours.</p>
        <div className="my-8"><DownloadDropdown release={release} source="cta" /></div>
        <ProductLink kind={kind === "video" ? "image" : "video"} />
      </section>
    </main>
    <SiteFooter />
  </div>
}

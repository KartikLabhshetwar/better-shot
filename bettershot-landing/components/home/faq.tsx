import { Plus } from "lucide-react"

export const faqs = [
  {
    q: "Is Better Shot really free?",
    a: "Yes. Better Shot is free and open source under the BSD 3-Clause license. There is no trial, no paid tier, no account, and no upsell. For comparison, as of August 2026 CleanShot X is $29 one-time plus $8/month if you want Cloud, Loom Business is $18 per seat per month, and CapCut Pro is $19.99 per month.",
  },
  {
    q: "Is Better Shot a good CleanShot X alternative?",
    a: "It covers the same daily workflow: region, window, and fullscreen capture, a floating preview you can drag into any app, annotations, scrolling-friendly pinning, OCR, a color picker, and a beautifier with backgrounds, padding, and shadows. It adds screen recording with cursor auto-zoom and a face cam, which is closer to what people open Loom or CapCut for.",
  },
  {
    q: "Can it replace Loom for quick screen recordings?",
    a: "For recording and sharing, yes. Better Shot records MP4 with system audio and microphone, tracks your cursor with auto-zoom, and can upload to your own Cloudflare R2 bucket to produce a share link. The difference is that the video lives in your storage, not on a vendor's servers, and there is no viewer limit or video cap.",
  },
  {
    q: "Do I need CapCut for basic screen recording edits?",
    a: "Not for screen content. The built-in video editor does multi-clip trimming, splitting at the playhead, per-clip speed from 0.25x to 4x, cropping, backgrounds, padding, shadows, and zoom cue retiming, then exports MP4. CapCut is still the better tool for multi-track social video with music, captions, and transitions.",
  },
  {
    q: "Does anything get uploaded?",
    a: "No, unless you explicitly click Share. Capture, editing, and export are entirely local. Share links only exist if you connect your own Cloudflare R2 bucket in Settings, and uploads go directly from the app to your bucket with no proxy in between. There is no telemetry and no account system.",
  },
  {
    q: "What are the system requirements?",
    a: "macOS 14 (Sonoma) or later, on Apple Silicon or Intel. Microphone recording requires macOS 15, which is where ScreenCaptureKit added microphone capture.",
  },
  {
    q: "How do I install it?",
    a: "Run brew install --cask bettershot, or download the DMG for Apple Silicon or Intel from the download menu. Updates can be checked and installed from inside the app.",
  },
  {
    q: "Can I use it for client or commercial work?",
    a: "Yes. The BSD 3-Clause license permits commercial use, modification, and redistribution. There is no watermark on exports.",
  },
]

export function FaqSection() {
  return (
    <section id="faq" className="border-t border-ink/[0.06] py-20 sm:py-28 scroll-mt-14">
      <div className="max-w-[720px] mx-auto px-5 sm:px-6">
        <SectionLabel>FAQ</SectionLabel>
        <h2 className="text-[28px] sm:text-[36px] font-bold tracking-[-0.03em] text-ink mb-3">
          Questions people ask
        </h2>
        <p className="text-[15px] leading-[1.7] text-ink/45 mb-10 max-w-[520px]">
          Everything about pricing, privacy, and how Better Shot compares to the tools you are
          probably paying for today.
        </p>

        <div className="divide-y divide-ink/[0.07] border-y border-ink/[0.07]">
          {faqs.map((faq) => (
            <details key={faq.q} className="group py-1">
              <summary className="flex items-start justify-between gap-6 cursor-pointer list-none py-4 min-h-[48px]">
                <span className="text-[15px] font-medium text-ink/85 leading-[1.5]">{faq.q}</span>
                <Plus className="h-4 w-4 shrink-0 mt-0.5 text-ink/30 transition-transform duration-200 group-open:rotate-45" />
              </summary>
              <p className="text-[14px] leading-[1.75] text-ink/50 pb-5 pr-10 max-w-[600px]">
                {faq.a}
              </p>
            </details>
          ))}
        </div>
      </div>
    </section>
  )
}

export function SectionLabel({ children }: { children: React.ReactNode }) {
  return (
    <p className="inline-flex items-center gap-2 text-[11px] font-semibold uppercase tracking-[0.12em] text-brand mb-4">
      <span className="h-1 w-1 rounded-full bg-brand" />
      {children}
    </p>
  )
}

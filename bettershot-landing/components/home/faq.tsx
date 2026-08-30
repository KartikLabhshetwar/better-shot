import { PlusIcon } from "@phosphor-icons/react/dist/ssr"
import { SectionLabel } from "@/components/section"

export const faqs = [
  {
    q: "Is Better Shot really free?",
    a: "Yes. Better Shot is free and open source under the BSD 3 Clause license. There is no trial, no paid tier, no account, and no upsell. For comparison, as of August 2026 CleanShot X is $29 one time plus $8 a month if you want Cloud, Loom Business is $18 per seat per month, and CapCut Pro is $19.99 a month.",
  },
  {
    q: "Is Better Shot a good CleanShot X alternative?",
    a: "It covers the same daily workflow: region, window, and fullscreen capture, a floating preview you can drag into any app, annotations, pinning, OCR, a color picker, and a beautifier with backgrounds, padding, and shadows. It adds screen recording with cursor auto zoom, a face cam, captions, and a full video editor, which is closer to what people open Loom or CapCut for.",
  },
  {
    q: "Can it replace Loom for quick screen recordings?",
    a: "For recording and sharing, yes. Better Shot records MP4 with system audio and microphone, tracks your cursor with auto zoom, and uploads to your own Cloudflare R2 bucket to produce a share link. The difference is that the video lives in your storage, not on a vendor's servers, and there is no viewer limit or video cap.",
  },
  {
    q: "Do I still need CapCut for screen recording edits?",
    a: "Not for screen content. The editor does multi clip trimming, splitting at the playhead, per clip speed from 0.25x to 4x, crossfade and fade through black transitions, cropping, a 3D camera tilt, color grading, and zoom cue retiming, then exports MP4. CapCut is still the better tool for multi track social video with music and stock transitions.",
  },
  {
    q: "Can it caption a recording without uploading the audio?",
    a: "Yes. The Overlay tab transcribes the recording's own audio on device where your Mac supports it, groups speech into readable lines that break on a pause or a full stop, and lets you edit every line. Position, size, weight, color, width, and a backdrop plate are all adjustable, and the captions are drawn on the canvas so they stay readable while the recording zooms.",
  },
  {
    q: "Can I hide a password before I share the video?",
    a: "Yes. Masks in the Overlay tab either blur, pixelate, or spotlight a box on the frame. A hide mask is destroyed in the export rather than covered, so the pixels underneath never ship in the file. Drag the box on the video and set its start and end from the playhead.",
  },
  {
    q: "Does it show the keys I press?",
    a: "Only if you turn it on. The keyboard overlay records your keystrokes beside the recording and draws them under the video, collapsing typing into words instead of stuttering key by key and giving a shortcut like Command S its own moment. Capture is off until you enable it, asks for Input Monitoring, and never leaves your Mac.",
  },
  {
    q: "Does anything get uploaded?",
    a: "No, unless you explicitly click Cloud Share. Capture, editing, transcription, and export are entirely local. Share links only exist once you connect your own Cloudflare R2 bucket in Settings, and uploads go directly from the app to your bucket with no proxy in between. There is no telemetry and no account system.",
  },
  {
    q: "What are the system requirements?",
    a: "macOS 14 (Sonoma) or later, on Apple Silicon or Intel. Microphone recording requires macOS 15, which is where ScreenCaptureKit added microphone capture.",
  },
  {
    q: "How do I install it?",
    a: "Run brew install --cask bettershot, or download the DMG for Apple Silicon or Intel. Updates can be checked and installed from inside the app.",
  },
  {
    q: "Can I use it for client or commercial work?",
    a: "Yes. The BSD 3 Clause license permits commercial use, modification, and redistribution. There is no watermark on exports.",
  },
]

export function FaqSection() {
  return (
    <section id="faq" className="mx-auto max-w-[1100px] scroll-mt-20 px-6 py-14 sm:py-20">
      <div className="max-w-[760px]">
        <SectionLabel className="mb-4">FAQ</SectionLabel>
        <h2 className="mb-4 text-[28px] tracking-tight sm:text-[32px]">Frequently asked questions</h2>
        <p className="mb-10 max-w-[60ch] text-[16px] leading-[28px] text-zinc-500">
          Pricing, privacy, and how Better Shot compares to the tools you are probably paying for
          today.
        </p>

        <div className="divide-y divide-zinc-200 overflow-hidden rounded-2xl border border-zinc-200">
          {faqs.map((faq) => (
            <details key={faq.q} className="group">
              <summary className="flex cursor-pointer list-none items-start justify-between gap-6 bg-white px-5 py-4 outline-none transition-colors hover:bg-zinc-50">
                <span className="text-[16px] font-semibold leading-normal text-zinc-900">{faq.q}</span>
                <PlusIcon
                  size={16}
                  weight="bold"
                  className="mt-1 shrink-0 text-zinc-400 duration-300 group-open:rotate-45"
                />
              </summary>
              <p className="max-w-[68ch] px-5 pb-6 pr-10 text-[15px] leading-[26px] text-zinc-500">{faq.a}</p>
            </details>
          ))}
        </div>
      </div>
    </section>
  )
}

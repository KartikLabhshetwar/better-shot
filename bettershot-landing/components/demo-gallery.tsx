"use client"

import { useState } from "react"
import { cn } from "@/lib/utils"

const demos = [
  { id: "video-trimming", kind: "video", title: "Trim a recording", caption: "Split a clip, remove a pause, and keep the useful part." },
  { id: "video-zoom", kind: "video", title: "Add a zoom", caption: "Set a zoom on the timeline and bring the important detail closer." },
  { id: "video-export", kind: "video", title: "Export and share", caption: "Choose your export settings, save your video, and create a share link." },
  { id: "screenshot-background", kind: "image", title: "Choose a background", caption: "Choose a gradient and adjust the padding, corners, and shadow." },
  { id: "screenshot-annotation", kind: "image", title: "Annotate a screenshot", caption: "Add an arrow, outline the important area, and number the steps." },
] as const

export function DemoGallery({ kind }: { kind?: "image" | "video" }) {
  const available = demos.filter(demo => !kind || demo.kind === kind)
  const [selected, setSelected] = useState<string>(available[0].id)
  const active = available.find(demo => demo.id === selected) || available[0]
  return <div>
    <figure className="overflow-hidden rounded-2xl border border-zinc-200 bg-white shadow-sm">
      <video key={active.id} controls playsInline preload="none" poster={`/features/${active.id}-poster.webp`}
        width={1280} height={800} aria-label={`BetterShot demo: ${active.title}`}
        className="aspect-[8/5] w-full bg-zinc-900">
        <source src={`/features/${active.id}-demo.mp4`} type="video/mp4" />
        Your browser cannot play this video. Use the video link below.
      </video>
      <figcaption className="flex flex-wrap items-center justify-between gap-3 px-5 py-4 text-[13px] leading-relaxed text-zinc-600">
        <span>{active.caption}</span>
        <a href={`/features/${active.id}-demo.mp4`} className="shrink-0 font-medium text-brand underline underline-offset-4">Open video</a>
      </figcaption>
    </figure>
    <div className="mt-4 flex flex-wrap justify-center gap-2" role="group" aria-label="Choose a BetterShot demo">
      {available.map(demo => <button key={demo.id} type="button" aria-pressed={active.id === demo.id}
        onClick={() => setSelected(demo.id)} data-demo={demo.id}
        className={cn("rounded-full border px-4 py-2.5 text-[13px] font-medium focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-brand", active.id === demo.id ? "border-brand bg-brand-100 text-brand-700" : "border-zinc-200 bg-white text-zinc-600 hover:border-zinc-400 hover:text-zinc-900")}>
        {demo.title}
      </button>)}
    </div>
  </div>
}

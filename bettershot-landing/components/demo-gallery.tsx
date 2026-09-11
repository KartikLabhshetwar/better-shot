"use client"

import { useEffect, useRef } from "react"
import { cn } from "@/lib/utils"

const demos = [
  { id: "video-trimming", kind: "video", title: "Trim a recording", caption: "Split a clip, remove a pause, and keep the useful part." },
  { id: "video-zoom", kind: "video", title: "Add a zoom", caption: "Set a zoom on the timeline and bring the important detail closer." },
  { id: "video-export", kind: "video", title: "Export and share", caption: "Choose your export settings, save your video, and create a share link." },
  { id: "screenshot-background", kind: "image", title: "Choose a background", caption: "Choose a gradient and adjust the padding, corners, and shadow." },
  { id: "screenshot-annotation", kind: "image", title: "Annotate a screenshot", caption: "Add an arrow, outline the important area, and number the steps." },
] as const

type Demo = (typeof demos)[number]

function DemoVideo({ demo }: { demo: Demo }) {
  const ref = useRef<HTMLVideoElement>(null)

  useEffect(() => {
    const video = ref.current!
    const motion = window.matchMedia("(prefers-reduced-motion: reduce)")
    let visible = false
    const update = () => {
      if (visible && !document.hidden && !motion.matches && !video.matches(":hover, :focus")) {
        video.play().catch(() => { /* Keep the poster when autoplay is unavailable. */ })
      } else video.pause()
    }
    const observer = new IntersectionObserver(([entry]) => {
      visible = entry.isIntersecting
      update()
    }, { threshold: 0.1 })
    observer.observe(video)
    motion.addEventListener("change", update)
    document.addEventListener("visibilitychange", update)
    for (const event of ["mouseenter", "mouseleave", "focus", "blur"]) video.addEventListener(event, update)
    return () => {
      observer.disconnect()
      motion.removeEventListener("change", update)
      document.removeEventListener("visibilitychange", update)
      for (const event of ["mouseenter", "mouseleave", "focus", "blur"]) video.removeEventListener(event, update)
      video.pause()
    }
  }, [])

  return <video ref={ref} muted loop playsInline preload="none" disablePictureInPicture
    poster={`/features/${demo.id}-poster.webp`} data-demo={demo.id} data-autoplay="visible"
    width={1280} height={800} tabIndex={0}
    aria-label={`BetterShot demo: ${demo.title}. Focus or hover to pause the preview.`}
    className="block aspect-[8/5] w-full bg-zinc-900 object-contain shadow-2xl">
    <source src={`/features/${demo.id}-demo.mp4`} type="video/mp4" />
  </video>
}

export function DemoGallery({ kind }: { kind?: "image" | "video" }) {
  const [hero, ...features] = demos.filter(demo => !kind || demo.kind === kind)
  return <div>
    <figure className="demo-stage editor-tools-backdrop overflow-hidden rounded-2xl p-4 sm:p-12">
      <DemoVideo demo={hero} />
      <figcaption className="sr-only">{hero.caption}</figcaption>
    </figure>
    <section className="mx-auto max-w-[1100px] py-16 sm:py-24" aria-label="BetterShot in action">
      <div className="mb-10 text-center">
        <h2>Made for the work you share.</h2>
        <p className="mx-auto mt-4 max-w-xl text-base leading-relaxed text-zinc-600">From the first capture to the finishing touches. See it happen in BetterShot.</p>
      </div>
      <div className="space-y-6">
        {features.map((demo, index) => <article key={demo.id} data-demo-row
          className="grid overflow-hidden rounded-2xl border border-zinc-200 bg-white md:grid-cols-2">
          <div className={cn("flex flex-col justify-center p-8 sm:p-12", index % 2 === 1 && "md:order-2")}>
            <p className="mb-3 text-sm font-medium text-brand">{demo.kind === "video" ? "Video recording" : "Screenshots"}</p>
            <h3 className="text-2xl font-medium sm:text-3xl">{demo.title}</h3>
            <p className="mt-4 text-base leading-relaxed text-zinc-600">{demo.caption}</p>
          </div>
          <div className={cn("flex items-center p-5 sm:p-8", index % 2 === 0 ? "preview-lilac" : "preview-peach")}>
            <DemoVideo demo={demo} />
          </div>
        </article>)}
      </div>
    </section>
  </div>
}

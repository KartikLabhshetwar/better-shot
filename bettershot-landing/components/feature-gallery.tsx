"use client"

import type { ReactNode } from "react"
import { Carousel, CarouselContent, CarouselNext, CarouselPrevious } from "@/components/ui/carousel"

export function FeatureGallery({ title, children }: { title: string; children: ReactNode }) {
  return (
    <Carousel opts={{ align: "start", duration: 0 }} aria-label={title} tabIndex={0}>
      <CarouselContent>{children}</CarouselContent>
      <div className="mt-8 flex justify-end gap-2">
        <CarouselPrevious className="static size-10 translate-y-0 border-zinc-200 bg-zinc-50" />
        <CarouselNext className="static size-10 translate-y-0 border-zinc-200 bg-zinc-50" />
      </div>
    </Carousel>
  )
}

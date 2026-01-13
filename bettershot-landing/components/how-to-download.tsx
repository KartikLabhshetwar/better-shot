"use client"

import { useState, useEffect } from "react"
import {
  Carousel,
  CarouselContent,
  CarouselItem,
  CarouselNext,
  CarouselPrevious,
  type CarouselApi,
} from "@/components/ui/carousel"

export function HowToDownload() {
  const [api, setApi] = useState<CarouselApi>()
  const [current, setCurrent] = useState(0)

  const videos = [
    {
      id: "GnQRUWiFx9Y",
      title: "How to Install Better Shot",
      description: "Follow these simple steps to install Better Shot on your Mac",
    },
    {
      id: "4I7TxGSNPT4",
      title: "Best Way to Use Better Shot",
      description: "Learn tips and tricks to get the most out of Better Shot",
    },
  ]

  useEffect(() => {
    if (!api) {
      return
    }

    setCurrent(api.selectedScrollSnap())

    api.on("select", () => {
      setCurrent(api.selectedScrollSnap())
    })
  }, [api])

  const getEmbedUrl = (videoId: string) => {
    return `https://www.youtube.com/embed/${videoId}?autoplay=1&loop=1&mute=1&playlist=${videoId}&controls=0&modestbranding=1&rel=0`
  }

  const currentVideo = videos[current] || videos[0]

  return (
    <section className="w-full py-16 px-4 sm:px-6 lg:px-8 relative z-10">
      <div className="container mx-auto max-w-5xl">
        <div className="text-center mb-12">
          <h2 className="text-3xl sm:text-4xl font-bold mb-4 text-foreground">{currentVideo.title}</h2>
          <p className="text-muted-foreground text-lg">
            {currentVideo.description}
          </p>
        </div>

        <Carousel setApi={setApi} className="w-full">
          <CarouselContent>
            {videos.map((video) => (
              <CarouselItem key={video.id}>
                <div className="relative w-full aspect-video rounded-lg overflow-hidden border border-border shadow-lg">
                  <iframe
                    src={getEmbedUrl(video.id)}
                    title={video.title}
                    className="absolute inset-0 w-full h-full"
                    allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
                    allowFullScreen
                  />
                </div>
              </CarouselItem>
            ))}
          </CarouselContent>
          <CarouselPrevious className="left-4" />
          <CarouselNext className="right-4" />
        </Carousel>
      </div>
    </section>
  )
}

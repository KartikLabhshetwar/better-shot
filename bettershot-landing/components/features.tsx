"use client"

import { motion, useInView } from "framer-motion"
import { useRef } from "react"
import { geist } from "@/lib/fonts"
import { cn } from "@/lib/utils"

const features = [
  {
    title: "How to Install Better Shot",
    description: "Follow these simple steps to install Better Shot on your Mac.",
    demoVideo: "GnQRUWiFx9Y",
  },
  {
    title: "Best Way to Use Better Shot",
    description: "Learn tips and tricks to get the most out of Better Shot.",
    demoVideo: "4I7TxGSNPT4",
  },
  // {
  //   title: "Annotation Tools",
  //   description: "Add shapes, arrows, text, and numbered labels. Customize colors, opacity, borders, and alignment for professional annotations.",
  //   demoVideo: "cnI-cgNeRLs",
  // },
  // {
  //   title: "Customizable Preferences",
  //   description: "Set default backgrounds, upload your own images, customize keyboard shortcuts, and configure all settings to match your workflow.",
  //   demoVideo: "GnQRUWiFx9Y",
  // },
]

export default function Features() {
  const ref = useRef(null)
  const isInView = useInView(ref, { once: true, amount: 0.2 })

  const getEmbedUrl = (videoId: string) => {
    return `https://www.youtube.com/embed/${videoId}?autoplay=1&loop=1&mute=1&playlist=${videoId}&controls=0&modestbranding=1&rel=0`
  }

  return (
    <section id="features" className="text-foreground relative overflow-hidden py-12 sm:py-24 md:py-32">
      <div className="bg-primary absolute -top-10 left-1/2 h-16 w-44 -translate-x-1/2 rounded-full opacity-40 blur-3xl select-none"></div>
      <div className="via-primary/50 absolute top-0 left-1/2 h-px w-3/5 -translate-x-1/2 bg-gradient-to-r from-transparent to-transparent transition-all ease-in-out"></div>
      <motion.div
        ref={ref}
        initial={{ opacity: 0, y: 50 }}
        animate={isInView ? { opacity: 1, y: 0 } : { opacity: 0, y: 50 }}
        transition={{ duration: 0.5, delay: 0 }}
        className="container mx-auto px-4 sm:px-6 lg:px-8"
      >
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={isInView ? { opacity: 1, y: 0 } : { opacity: 0, y: 20 }}
          transition={{ duration: 0.5, delay: 0.1 }}
          className="text-center mb-16 sm:mb-24"
        >
          <h2 className="from-foreground/60 via-foreground to-foreground/60 dark:from-muted-foreground/55 dark:via-foreground dark:to-muted-foreground/55 bg-gradient-to-r bg-clip-text text-4xl font-semibold tracking-tighter text-transparent md:text-[54px] md:leading-[60px]">
            Powerful Features
          </h2>
        </motion.div>
        <div className="space-y-24 sm:space-y-32">
          {features.map((feature, index) => {
            const isEven = index % 2 === 0
            
            return (
              <motion.div
                key={feature.title}
                initial={{ opacity: 0, y: 50 }}
                animate={isInView ? { opacity: 1, y: 0 } : { opacity: 0, y: 50 }}
                transition={{ duration: 0.5, delay: index * 0.2 }}
                className="grid grid-cols-1 lg:grid-cols-2 gap-8 lg:gap-12 items-center max-w-6xl mx-auto"
              >
                {isEven ? (
                  <>
                    <motion.div
                      initial={{ opacity: 0, x: -50 }}
                      animate={isInView ? { opacity: 1, x: 0 } : { opacity: 0, x: -50 }}
                      transition={{ duration: 0.5, delay: index * 0.2 + 0.1 }}
                      className="relative"
                    >
                      <div className="relative rounded-2xl border border-white/20 bg-white/5 p-1.5 shadow-lg shadow-black/20">
                        <div className="relative w-full aspect-video overflow-hidden rounded-xl bg-black">
                          <iframe
                            src={getEmbedUrl(feature.demoVideo)}
                            title={feature.title}
                            className="absolute inset-0 w-full h-full"
                            allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
                            allowFullScreen
                          />
                        </div>
                      </div>
                    </motion.div>

                    <motion.div
                      initial={{ opacity: 0, x: 50 }}
                      animate={isInView ? { opacity: 1, x: 0 } : { opacity: 0, x: 50 }}
                      transition={{ duration: 0.5, delay: index * 0.2 + 0.2 }}
                      className="space-y-4"
                    >
                      <h3 className="from-foreground/60 via-foreground to-foreground/60 dark:from-muted-foreground/55 dark:via-foreground dark:to-muted-foreground/55 bg-gradient-to-r bg-clip-text text-3xl sm:text-4xl font-semibold tracking-tighter text-transparent mb-4">{feature.title}</h3>
                      <p className="text-muted-foreground text-lg leading-relaxed">
                        {feature.description}
                      </p>
                    </motion.div>
                  </>
                ) : (
                  <>
                    <motion.div
                      initial={{ opacity: 0, x: -50 }}
                      animate={isInView ? { opacity: 1, x: 0 } : { opacity: 0, x: -50 }}
                      transition={{ duration: 0.5, delay: index * 0.2 + 0.1 }}
                      className="space-y-4"
                    >
                      <h3 className="from-foreground/60 via-foreground to-foreground/60 dark:from-muted-foreground/55 dark:via-foreground dark:to-muted-foreground/55 bg-gradient-to-r bg-clip-text text-3xl sm:text-4xl font-semibold tracking-tighter text-transparent mb-4">{feature.title}</h3>
                      <p className="text-muted-foreground text-lg leading-relaxed">
                        {feature.description}
                      </p>
                    </motion.div>

                    <motion.div
                      initial={{ opacity: 0, x: 50 }}
                      animate={isInView ? { opacity: 1, x: 0 } : { opacity: 0, x: 50 }}
                      transition={{ duration: 0.5, delay: index * 0.2 + 0.2 }}
                      className="relative"
                    >
                      <div className="relative rounded-2xl border border-white/20 bg-white/5 p-1.5 shadow-lg shadow-black/20">
                        <div className="relative w-full aspect-video overflow-hidden rounded-xl bg-black">
                          <iframe
                            src={getEmbedUrl(feature.demoVideo)}
                            title={feature.title}
                            className="absolute inset-0 w-full h-full"
                            allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
                            allowFullScreen
                          />
                        </div>
                      </div>
                    </motion.div>
                  </>
                )}
              </motion.div>
            )
          })}
        </div>
      </motion.div>
    </section>
  )
}

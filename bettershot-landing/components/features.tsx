"use client"

import { motion, useInView } from "framer-motion"
import { useRef } from "react"
import { geist } from "@/lib/fonts"
import { cn } from "@/lib/utils"
import { Camera, Image, Zap, Lock, Palette, Download } from "lucide-react"

const features = [
  {
    title: "Multiple Capture Modes",
    description: "Capture regions, fullscreen, or specific windows with pixel-perfect precision. Global hotkeys work from anywhere.",
    icon: Camera,
    color: "from-blue-500 to-cyan-500",
  },
  {
    title: "Powerful Image Editor",
    description: "Add beautiful backgrounds, gradients, blur effects, and adjust border radius. Make your screenshots stand out.",
    icon: Image,
    color: "from-purple-500 to-pink-500",
  },
  {
    title: "Lightning Fast",
    description: "Built with Rust and Tauri for native performance. Minimal resource usage compared to Electron apps.",
    icon: Zap,
    color: "from-yellow-500 to-orange-500",
  },
  {
    title: "Privacy First",
    description: "All processing happens locally on your machine. No cloud uploads, no data collection. Your screenshots stay yours.",
    icon: Lock,
    color: "from-green-500 to-emerald-500",
  },
  {
    title: "Beautiful Backgrounds",
    description: "Choose from curated wallpapers, Mac assets, mesh patterns, or create custom backgrounds with solid colors and gradients.",
    icon: Palette,
    color: "from-rose-500 to-red-500",
  },
  {
    title: "Easy Export",
    description: "Save to your chosen directory or copy directly to clipboard. High-quality export for presentations and documentation.",
    icon: Download,
    color: "from-indigo-500 to-blue-500",
  },
]

export default function Features() {
  const ref = useRef(null)
  const isInView = useInView(ref, { once: true, amount: 0.2 })

  return (
    <section id="features" className="text-foreground relative overflow-hidden py-12 sm:py-24 md:py-32">
      <div className="bg-primary absolute -top-10 left-1/2 h-16 w-44 -translate-x-1/2 rounded-full opacity-40 blur-3xl select-none"></div>
      <div className="via-primary/50 absolute top-0 left-1/2 h-px w-3/5 -translate-x-1/2 bg-gradient-to-r from-transparent to-transparent transition-all ease-in-out"></div>
      <motion.div
        ref={ref}
        initial={{ opacity: 0, y: 50 }}
        animate={isInView ? { opacity: 1, y: 0 } : { opacity: 0, y: 50 }}
        transition={{ duration: 0.5, delay: 0 }}
        className="container mx-auto flex flex-col items-center gap-6 sm:gap-12"
      >
        <h2
          className={cn(
            "via-foreground mb-8 bg-gradient-to-b from-zinc-800 to-zinc-700 bg-clip-text text-center text-4xl font-semibold tracking-tighter text-transparent md:text-[54px] md:leading-[60px]",
            geist.className,
          )}
        >
          Powerful Features
        </h2>

        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6 w-full max-w-6xl">
          {features.map((feature, index) => {
            const Icon = feature.icon
            return (
              <motion.div
                key={feature.title}
                initial={{ opacity: 0, y: 50 }}
                animate={isInView ? { opacity: 1, y: 0 } : { opacity: 0, y: 50 }}
                transition={{ duration: 0.5, delay: index * 0.1 }}
                whileHover={{ y: -5 }}
                className="group relative rounded-xl border border-white/10 bg-gradient-to-b from-white/5 to-white/[0.02] p-6 shadow-[0px_2px_0px_0px_rgba(255,255,255,0.1)_inset] hover:border-white/20 transition-all duration-300"
              >
                <div className={`absolute -top-5 -left-5 -z-10 h-20 w-20 rounded-full bg-gradient-to-br ${feature.color} opacity-20 blur-xl group-hover:opacity-30 transition-opacity`}></div>
                
                <div className={`inline-flex items-center justify-center w-12 h-12 rounded-lg bg-gradient-to-br ${feature.color} mb-4`}>
                  <Icon className="h-6 w-6 text-white" />
                </div>
                
                <h3 className="text-xl font-semibold mb-2 text-white">{feature.title}</h3>
                <p className="text-muted-foreground text-sm leading-relaxed">{feature.description}</p>
              </motion.div>
            )
          })}
          </div>
      </motion.div>
    </section>
  )
}

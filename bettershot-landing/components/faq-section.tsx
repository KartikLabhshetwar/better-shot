"use client"

import { useState } from "react"
import { Plus, Minus } from "lucide-react"
import { motion, AnimatePresence } from "framer-motion"

export function FAQSection() {
  const [openItems, setOpenItems] = useState<number[]>([])

  const toggleItem = (index: number) => {
    setOpenItems((prev) => (prev.includes(index) ? prev.filter((i) => i !== index) : [...prev, index]))
  }

  const faqs = [
    {
      question: "What is Better Shot?",
      answer:
        "Better Shot is a free, open-source screenshot tool for macOS. It's an alternative to CleanShot X that lets you capture, edit, and enhance screenshots with professional quality. All processing happens locally on your machine.",
    },
    {
      question: "Is Better Shot really free?",
      answer:
        "Yes! Better Shot is 100% free and open source. There are no subscriptions, no paywalls, and no hidden costs. You can download it, use it, and even modify the source code to suit your needs.",
    },
    {
      question: "What capture modes are available?",
      answer:
        "Better Shot supports three capture modes: Region Capture (⌘⇧2) to select any area, Fullscreen Capture (⌘⇧F) for your entire screen, and Window Capture (⌘⇧D) to capture a specific window. All modes work with global hotkeys from anywhere, and you can customize these shortcuts in Preferences.",
    },
    {
      question: "What editing features are included?",
      answer:
        "You can add beautiful backgrounds from a curated library, upload your own custom images, use solid colors or gradients, apply blur and noise effects, add customizable shadows with adjustable blur, offset, and opacity, and adjust border radius. The editor also includes annotation tools for adding shapes, arrows, text, and numbered labels. All edits are non-destructive and export at maximum quality.",
    },
    {
      question: "Can I customize keyboard shortcuts?",
      answer:
        "Yes! Better Shot includes a Preferences page where you can customize all keyboard shortcuts. You can edit existing shortcuts, add new ones, enable or disable them, and remove custom shortcuts. Changes are saved automatically and take effect immediately.",
    },
    {
      question: "Can I set a default background?",
      answer:
        "Absolutely! In Preferences, you can choose any background from the built-in library or upload your own images. Set one as your default background, and it will be used when you enable Auto-apply background mode for instant captures without opening the editor.",
    },
    {
      question: "What annotation tools are available?",
      answer:
        "Better Shot includes a full set of annotation tools: circles, rectangles, lines, arrows, text annotations, and auto-incrementing numbered labels. You can customize colors, opacity, borders, alignment, and font sizes. Select any annotation to edit its properties in the properties panel.",
    },
    {
      question: "Do I need special permissions?",
      answer:
        "Yes, Better Shot requires Screen Recording permission on macOS. This is required for the app to capture screenshots. You'll be prompted to grant this permission on first launch, and you can enable it in System Settings → Privacy & Security → Screen Recording.",
    },
    {
      question: "Can I build from source?",
      answer:
        "Absolutely! Better Shot is open source and available on GitHub. You can clone the repository, install dependencies with pnpm, and build using `pnpm tauri build`. See the README for detailed instructions.",
    },
  ]

  return (
    <section id="faq" className="relative overflow-hidden pb-120 pt-24">
      {/* Background blur effects */}
      <div className="bg-primary/20 absolute top-1/2 -right-20 z-[-1] h-64 w-64 rounded-full opacity-80 blur-3xl"></div>
      <div className="bg-primary/20 absolute top-1/2 -left-20 z-[-1] h-64 w-64 rounded-full opacity-80 blur-3xl"></div>

      <div className="z-10 container mx-auto px-4">
        <motion.div
          className="flex justify-center"
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.6 }}
          viewport={{ once: true }}
        >
          <div className="border-primary/40 text-primary inline-flex items-center gap-2 rounded-full border px-3 py-1 uppercase">
            <span>✶</span>
            <span className="text-sm">Faqs</span>
          </div>
        </motion.div>

        <motion.h2
          className="mx-auto mt-6 max-w-xl text-center text-4xl font-medium md:text-[54px] md:leading-[60px]"
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.6, delay: 0.2 }}
          viewport={{ once: true }}
        >
          Questions? We've got{" "}
          <span className="bg-gradient-to-b from-foreground via-rose-200 to-primary bg-clip-text text-transparent">
            answers
          </span>
        </motion.h2>

        <div className="mx-auto mt-12 flex max-w-xl flex-col gap-6">
          {faqs.map((faq, index) => (
            <motion.div
              key={index}
              className="from-secondary/40 to-secondary/10 rounded-2xl border border-white/10 bg-gradient-to-b p-6 shadow-[0px_2px_0px_0px_rgba(255,255,255,0.1)_inset] transition-all duration-300 hover:border-white/20 cursor-pointer"
              initial={{ opacity: 0, y: 20 }}
              whileInView={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.5, delay: index * 0.1 }}
              viewport={{ once: true }}
              whileHover={{ scale: 1.02 }}
              whileTap={{ scale: 0.98 }}
              onClick={() => toggleItem(index)}
              role="button"
              tabIndex={0}
              onKeyDown={(e) => {
                if (e.key === "Enter" || e.key === " ") {
                  e.preventDefault()
                  toggleItem(index)
                }
              }}
              {...(index === faqs.length - 1 && { "data-faq": faq.question })}
            >
              <div className="flex items-start justify-between">
                <h3 className="m-0 font-medium pr-4">{faq.question}</h3>
                <motion.div
                  animate={{ rotate: openItems.includes(index) ? 180 : 0 }}
                  transition={{ duration: 0.3, ease: "easeInOut" }}
                  className=""
                >
                  {openItems.includes(index) ? (
                    <Minus className="text-primary flex-shrink-0 transition duration-300" size={24} />
                  ) : (
                    <Plus className="text-primary flex-shrink-0 transition duration-300" size={24} />
                  )}
                </motion.div>
              </div>
              <AnimatePresence>
                {openItems.includes(index) && (
                  <motion.div
                    className="mt-4 text-muted-foreground leading-relaxed overflow-hidden"
                    initial={{ opacity: 0, height: 0, marginTop: 0 }}
                    animate={{ opacity: 1, height: "auto", marginTop: 16 }}
                    exit={{ opacity: 0, height: 0, marginTop: 0 }}
                    transition={{
                      duration: 0.4,
                      ease: "easeInOut",
                      opacity: { duration: 0.2 },
                    }}
                  >
                    {faq.answer}
                  </motion.div>
                )}
              </AnimatePresence>
            </motion.div>
          ))}
        </div>
      </div>
    </section>
  )
}

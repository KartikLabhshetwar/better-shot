import type { Metadata } from "next"
import Link from "next/link"
import { getLatestRelease } from "@/lib/downloads"
import { SiteNav } from "@/components/site-nav"
import { SiteFooter } from "@/components/site-footer"
import { Reveal } from "@/components/reveal"
import { CopyCommand } from "@/components/copy-command"
import { DownloadLink } from "@/components/download-link"

export const metadata: Metadata = {
  title: "Download Better Shot for macOS | Free screenshot and screen recorder",
  description:
    "Download Better Shot for macOS. Free and open source screenshots, screen recording, and video editing. Apple Silicon and Intel builds, or install with Homebrew.",
  alternates: { canonical: "/download" },
  openGraph: {
    title: "Download Better Shot for macOS",
    description:
      "Free and open source screenshots, screen recording, and video editing for macOS. Apple Silicon and Intel, or Homebrew.",
    url: "https://bettershot.site/download",
    type: "website",
  },
}

const steps = [
  {
    index: "01",
    title: "Grant permission once",
    body: "Screen recording permission on first capture. macOS never asks again. Input Monitoring only if you turn the keystroke overlay on.",
  },
  {
    index: "02",
    title: "Hit a shortcut",
    body: "Cmd Shift 4 for a region, Cmd Shift 2 to record. All six keys are remappable in Settings.",
  },
  {
    index: "03",
    title: "Edit and send",
    body: "Annotate, trim, caption, blur what should not ship, then copy, drag, export, or share a link from your own bucket.",
  },
]

const requirements = [
  { k: "Operating system", v: "macOS 14 Sonoma or later" },
  { k: "Architecture", v: "Apple Silicon and Intel" },
  { k: "Microphone capture", v: "macOS 15 or later" },
  { k: "Built with", v: "Swift 6 and SwiftUI, no Electron" },
  { k: "License", v: "BSD 3 Clause" },
  { k: "Price", v: "Free" },
]

const goodToKnow = [
  "Nothing is uploaded unless you explicitly click Share, and Share only exists once you connect your own R2 bucket.",
  "No telemetry, no analytics, no account system.",
  "BSD 3 Clause licensed. Commercial use is permitted and exports carry no watermark.",
  "Microphone capture needs macOS 15, which is where ScreenCaptureKit added it.",
]

const shell = "mx-auto max-w-[1100px] px-6"

export default async function DownloadPage() {
  const release = await getLatestRelease()

  return (
    <div className="min-h-screen w-full bg-white text-zinc-900">
      <SiteNav />

      <main id="main">
        <div className={shell}>
          <header className="pb-12 pt-28 sm:pt-32">
            <span className="text-[13px] font-medium uppercase tracking-widest text-zinc-400">
              Download &middot; v{release.version}
            </span>
            <h1 className="mt-4 max-w-[22ch] text-[clamp(38px,5.4vw,60px)] font-extrabold tracking-tight">
              Installed and capturing in under a minute
            </h1>
            <p className="mt-6 max-w-[56ch] text-[17px] leading-[28px] text-zinc-600">
              No signup screen, no license key, no onboarding tour. Pick one of the two routes
              below.
            </p>
          </header>

          <div className="h-px bg-zinc-200" />

          <Reveal className="my-14 grid gap-6 sm:grid-cols-2">
            <div className="rounded-2xl border border-zinc-200 px-8 py-9">
              <p className="text-[13px] font-medium uppercase tracking-widest text-zinc-400">Route one</p>
              <h2 className="mt-4 text-[28px] font-extrabold leading-[34px] tracking-tight">Homebrew</h2>
              <p className="mb-6 mt-4 text-[16px] leading-[28px] text-zinc-600">
                One command, and <code className="font-mono">brew upgrade</code> keeps it current.
              </p>
              <CopyCommand
                command="brew install --cask bettershot"
                className="w-full justify-between bg-zinc-50"
              />
            </div>
            <div className="rounded-2xl border border-zinc-200 px-8 py-9">
              <p className="text-[13px] font-medium uppercase tracking-widest text-zinc-400">Route two</p>
              <h2 className="mt-4 text-[28px] font-extrabold leading-[34px] tracking-tight">Direct DMG</h2>
              <p className="mb-6 mt-4 text-[16px] leading-[28px] text-zinc-600">
                Pick your architecture. Updates can be checked and installed from inside the app.
              </p>
              <div className="flex flex-wrap gap-3">
                <DownloadLink href={release.appleSilicon} label="Apple Silicon" primary />
                <DownloadLink href={release.intel} label="Intel" />
              </div>
              <p className="mt-6 flex flex-wrap gap-x-6 gap-y-2 text-[14px] text-zinc-400">
                <a
                  href="https://github.com/KartikLabhshetwar/better-shot/releases"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="outline-none transition-colors duration-150 hover:text-zinc-900"
                >
                  All releases
                </a>
                <Link
                  href="/changelog"
                  className="outline-none transition-colors duration-150 hover:text-zinc-900"
                >
                  What changed in {release.version}
                </Link>
              </p>
            </div>
          </Reveal>

          <div className="h-px bg-zinc-200" />

          <section className="py-14">
            <h2 className="mb-10 text-[clamp(28px,3.2vw,40px)] font-extrabold tracking-tight">Then three steps</h2>
            <div className="grid gap-8 sm:grid-cols-3 sm:gap-x-[clamp(24px,4vw,64px)]">
              {steps.map((step, i) => (
                <Reveal key={step.index} delay={i === 0 ? 0 : i === 1 ? 100 : 200}>
                  <p className="mb-4 font-sans text-[15px] font-semibold tabular-nums text-zinc-400">
                    {step.index}
                  </p>
                  <h3 className="text-[22px] font-extrabold leading-[26px] tracking-tight">{step.title}</h3>
                  <p className="mt-4 text-[16px] leading-[28px] text-zinc-600">{step.body}</p>
                </Reveal>
              ))}
            </div>
          </section>

          <div className="h-px bg-zinc-200" />

          <section className="grid gap-10 py-14 sm:grid-cols-2 sm:gap-x-[clamp(24px,5vw,80px)]">
            <div>
              <h2 className="mb-6 text-[24px] font-extrabold leading-[30px] tracking-tight">Requirements</h2>
              <ul>
                {requirements.map((req) => (
                  <li
                    key={req.k}
                    className="flex justify-between gap-6 border-t border-zinc-200 py-3.5 text-[15px] leading-[24px]"
                  >
                    <span className="text-zinc-400">{req.k}</span>
                    <span className="text-right font-medium">{req.v}</span>
                  </li>
                ))}
              </ul>
            </div>
            <div>
              <h2 className="mb-6 text-[24px] font-extrabold leading-[30px] tracking-tight">Good to know</h2>
              <ul className="grid gap-4">
                {goodToKnow.map((item) => (
                  <li key={item} className="text-[16px] leading-[28px] text-zinc-600">
                    {item}
                  </li>
                ))}
              </ul>
            </div>
          </section>
        </div>

        <section className="bg-zinc-50">
          <div className={`${shell} py-16 sm:py-20`}>
            <h2 className="max-w-[26ch] text-[clamp(28px,3.2vw,40px)] font-extrabold tracking-tight">
              Something broken? File it.
            </h2>
            <p className="mt-5 max-w-[46ch] text-[17px] leading-[28px] text-zinc-600">
              Issues and pull requests are read. The whole app is on GitHub.
            </p>
            <div className="mt-7 flex flex-wrap gap-3">
              <a
                href="https://github.com/KartikLabhshetwar/better-shot/issues"
                target="_blank"
                rel="noopener noreferrer"
                className="inline-flex items-center rounded-xl border border-zinc-200 px-5 py-3 text-[15px] font-semibold text-zinc-900 outline-none transition-colors duration-150 hover:border-zinc-400"
              >
                Report an issue
              </a>
              <a
                href="https://github.com/KartikLabhshetwar/better-shot"
                target="_blank"
                rel="noopener noreferrer"
                className="inline-flex items-center rounded-xl border border-zinc-200 px-5 py-3 text-[15px] font-semibold text-zinc-900 outline-none transition-colors duration-150 hover:border-zinc-400"
              >
                View source
              </a>
              <Link
                href="/changelog"
                className="inline-flex items-center rounded-xl border border-zinc-200 px-5 py-3 text-[15px] font-semibold text-zinc-900 outline-none transition-colors duration-150 hover:border-zinc-400"
              >
                Read the changelog
              </Link>
            </div>
          </div>
        </section>
      </main>

      <SiteFooter />
    </div>
  )
}

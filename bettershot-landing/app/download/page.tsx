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

const shell = "mx-auto max-w-[1240px] px-6"

export default async function DownloadPage() {
  const release = await getLatestRelease()

  return (
    <div className="min-h-screen w-full bg-canvas text-ink">
      <SiteNav />

      <main id="main">
        <div className={shell}>
          <header className="pb-12 pt-[72px]">
            <span className="micro block text-[13px] font-extrabold uppercase text-brand-700">
              Download · v{release.version}
            </span>
            <h1 className="display mt-3.5 -ml-[0.058em] max-w-[22ch] text-[clamp(38px,5.4vw,72px)]">
              Installed and capturing in under a minute
            </h1>
            <p className="mt-6 max-w-[56ch] text-[17px] leading-[28px] text-ink/80">
              No signup screen, no license key, no onboarding tour. Pick one of the two routes
              below.
            </p>
          </header>

          <hr className="rule" />

          <Reveal className="my-14 grid gap-0.5 bg-rule sm:grid-cols-2">
            <div className="bg-canvas px-8 py-9">
              <p className="micro text-[13px] font-extrabold uppercase text-brand-700">Route one</p>
              <h2 className="display-sm mt-4 text-[28px] leading-[34px]">Homebrew</h2>
              <p className="mb-6 mt-4 text-[16px] leading-[28px] text-ink/80">
                One command, and <code className="font-mono">brew upgrade</code> keeps it current.
              </p>
              <CopyCommand
                command="brew install --cask bettershot"
                className="w-full justify-between bg-surface"
              />
            </div>
            <div className="bg-canvas px-8 py-9">
              <p className="micro text-[13px] font-extrabold uppercase text-brand-700">Route two</p>
              <h2 className="display-sm mt-4 text-[28px] leading-[34px]">Direct DMG</h2>
              <p className="mb-6 mt-4 text-[16px] leading-[28px] text-ink/80">
                Pick your architecture. Updates can be checked and installed from inside the app.
              </p>
              <div className="flex flex-wrap gap-3">
                <DownloadLink href={release.appleSilicon} label="Apple Silicon" primary />
                <DownloadLink href={release.intel} label="Intel" />
              </div>
              <p className="mt-6 flex flex-wrap gap-x-6 gap-y-2 text-[14px] text-ink/70">
                <a
                  href="https://github.com/KartikLabhshetwar/better-shot/releases"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="outline-none transition-colors duration-150 hover:text-ink"
                >
                  All releases
                </a>
                <Link
                  href="/changelog"
                  className="outline-none transition-colors duration-150 hover:text-ink"
                >
                  What changed in {release.version}
                </Link>
              </p>
            </div>
          </Reveal>

          <hr className="rule" />

          <section className="py-14">
            <h2 className="display mb-10 text-[clamp(28px,3.2vw,40px)]">Then three steps</h2>
            <div className="grid gap-8 sm:grid-cols-3 sm:gap-x-[clamp(24px,4vw,64px)]">
              {steps.map((step, i) => (
                <Reveal key={step.index} delay={i === 0 ? 0 : i === 1 ? 100 : 200}>
                  <p className="mb-4 font-sans text-[15px] font-extrabold tabular-nums">
                    {step.index}
                  </p>
                  <h3 className="text-[22px] font-extrabold leading-[26px]">{step.title}</h3>
                  <p className="mt-4 text-[16px] leading-[28px] text-ink/80">{step.body}</p>
                </Reveal>
              ))}
            </div>
          </section>

          <hr className="rule" />

          <section className="grid gap-10 py-14 sm:grid-cols-2 sm:gap-x-[clamp(24px,5vw,80px)]">
            <div>
              <h2 className="mb-6 text-[24px] font-extrabold leading-[30px]">Requirements</h2>
              <ul>
                {requirements.map((req) => (
                  <li
                    key={req.k}
                    className="flex justify-between gap-6 border-t border-rule py-3.5 text-[15px] leading-[24px]"
                  >
                    <span className="text-ink/70">{req.k}</span>
                    <span className="text-right font-medium">{req.v}</span>
                  </li>
                ))}
              </ul>
            </div>
            <div>
              <h2 className="mb-6 text-[24px] font-extrabold leading-[30px]">Good to know</h2>
              <ul className="grid gap-4">
                {goodToKnow.map((item) => (
                  <li key={item} className="text-[16px] leading-[28px] text-ink/80">
                    {item}
                  </li>
                ))}
              </ul>
            </div>
          </section>
        </div>

        <section className="bg-brand text-canvas">
          <div className={`${shell} py-[72px]`}>
            <h2 className="display -ml-[0.058em] max-w-[26ch] text-[clamp(30px,4vw,52px)]">
              Something broken? File it.
            </h2>
            <p className="mt-5 max-w-[46ch] text-[17px] leading-[28px]">
              Issues and pull requests are read. The whole app is on GitHub.
            </p>
            <div className="mt-7 flex flex-wrap gap-3">
              <a
                href="https://github.com/KartikLabhshetwar/better-shot/issues"
                target="_blank"
                rel="noopener noreferrer"
                className="inline-flex items-center border border-canvas/55 px-5 py-3 text-[15px] font-semibold outline-none transition-colors duration-150 hover:border-canvas"
              >
                Report an issue
              </a>
              <a
                href="https://github.com/KartikLabhshetwar/better-shot"
                target="_blank"
                rel="noopener noreferrer"
                className="inline-flex items-center border border-canvas/55 px-5 py-3 text-[15px] font-semibold outline-none transition-colors duration-150 hover:border-canvas"
              >
                View source
              </a>
              <Link
                href="/changelog"
                className="inline-flex items-center border border-canvas/55 px-5 py-3 text-[15px] font-semibold outline-none transition-colors duration-150 hover:border-canvas"
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

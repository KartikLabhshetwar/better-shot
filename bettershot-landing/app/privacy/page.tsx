import type { Metadata } from "next"
import { SiteNav } from "@/components/site-nav"
import { SiteFooter } from "@/components/site-footer"

export const metadata: Metadata = {
  title: "Privacy Policy | Better Shot",
  description:
    "Better Shot collects nothing. No account, no telemetry, no uploads. What the app stores locally, what the website measures, and what happens when you use share links.",
  alternates: { canonical: "/privacy" },
}

const sections = [
  {
    id: "short",
    title: "The short version",
    body: [
      "Better Shot is a free, open source screenshot and screen recording app for macOS. The app has no account system, no telemetry, and no analytics. Nothing you capture is sent anywhere unless you explicitly click Share, and even then it goes to storage you own.",
    ],
  },
  {
    id: "captures",
    title: "What the app stores",
    body: [
      "Screenshots and recordings are written to the save folder you choose. Capture history, your preferences, and your default effects are stored locally in Application Support and UserDefaults. History keeps the 100 most recent captures by default and can be changed or cleared in Settings.",
      "If you configure share links, your Cloudflare R2 access key ID and secret access key are stored in the macOS Keychain. Non-secret configuration (account ID, bucket name, public base URL) lives in UserDefaults.",
    ],
  },
  {
    id: "processing",
    title: "On device processing",
    body: [
      "Editing, annotation, redaction, cropping, transcription, and export all run locally. Caption transcription uses your Mac's own speech recognition where it is supported, so the audio does not leave the machine.",
    ],
  },
  {
    id: "sharing",
    title: "Share links",
    body: [
      "Share links are opt-in and off by default. When enabled, the app uploads the file directly from your Mac to your own Cloudflare R2 bucket over a signed request. There is no proxy, no relay, and no Better Shot server in the path. We never see the file, the link, or the bucket, and we cannot delete or access anything you upload. Deleting a shared capture means deleting the object from your own bucket.",
    ],
  },
  {
    id: "permissions",
    title: "Screen, microphone, and camera access",
    body: [
      "macOS asks for screen recording permission before the first capture, and for microphone or camera permission only if you turn those on in the recording bar. All three streams are processed on-device and written into your recording. None of them are transmitted.",
      "Input Monitoring is requested only if you enable the keystroke overlay, and keystroke capture stays off until you do. Accessibility permission is used for global keyboard shortcuts. All of these are granted by you in System Settings and can be revoked there.",
    ],
  },
  {
    id: "site",
    title: "Website analytics",
    body: [
      "This website uses Umami, a privacy-focused analytics tool, to count page views and downloads. It sets no cookies, uses no cross-site identifiers, and collects no personal information. The app itself contains no analytics of any kind.",
    ],
  },
  {
    id: "third-parties",
    title: "Third parties",
    body: [
      "The app bundles no third-party SDKs. Its only outbound network calls are the GitHub update check and, if you enable them, share uploads to your own bucket. Better Shot is distributed through GitHub Releases and Homebrew, which apply their own privacy policies when you download from them.",
    ],
  },
  {
    id: "verify",
    title: "Verify it yourself",
    body: [
      "Better Shot is open source under the BSD 3 Clause license. Every claim on this page can be checked against the source code on GitHub. If this policy changes, the change ships with a release and is recorded in the changelog.",
    ],
  },
]

export default function PrivacyPolicy() {
  return (
    <div className="min-h-screen w-full bg-canvas text-ink">
      <SiteNav />

      <main id="main">
        <div className="mx-auto max-w-[1240px] px-6">
          <header className="pb-10 pt-[72px]">
            <span className="micro block text-[13px] font-extrabold uppercase text-brand-700">
              Privacy · Updated August 2026
            </span>
            <h1 className="display mt-3.5 -ml-[0.058em] max-w-[24ch] text-[clamp(38px,5.4vw,68px)]">
              Better Shot does not collect anything
            </h1>
            <p className="mt-6 max-w-[56ch] text-[18px] leading-[30px] text-ink/80">
              There is no account system, no telemetry, and no analytics inside the app. The long
              version follows, section by section.
            </p>
          </header>

          <hr className="rule" />

          <div className="grid items-start gap-x-[clamp(24px,5vw,80px)] lg:grid-cols-[200px_minmax(0,1fr)]">
            <nav aria-label="Sections" className="hidden gap-2.5 py-12 lg:sticky lg:top-20 lg:grid">
              <p className="micro mb-1.5 text-[13px] font-extrabold uppercase text-ink/70">
                Sections
              </p>
              {sections.map((section) => (
                <a
                  key={section.id}
                  href={`#${section.id}`}
                  className="text-[14px] leading-[22px] text-ink outline-none transition-colors duration-150 hover:text-brand-700"
                >
                  {section.title}
                </a>
              ))}
            </nav>

            <article className="max-w-[68ch] pb-[72px] pt-12 lg:border-l-2 lg:border-rule lg:pl-[clamp(20px,4vw,56px)]">
              {sections.map((section) => (
                <section key={section.id} id={section.id} className="mb-11 scroll-mt-20">
                  <h2 className="mb-4 text-[26px] font-extrabold leading-[32px]">{section.title}</h2>
                  {section.body.map((paragraph, i) => (
                    <p key={i} className="mb-4 text-[17px] leading-[30px] text-ink/80">
                      {paragraph}
                    </p>
                  ))}
                </section>
              ))}
              <p className="text-[15px] leading-[26px] text-ink/70">
                Questions about any of this belong in an{" "}
                <a
                  href="https://github.com/KartikLabhshetwar/better-shot/issues"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-brand-700 underline underline-offset-2 outline-none transition-colors duration-150 hover:text-brand"
                >
                  issue on GitHub
                </a>
                , where the answer is public. You can also reach out on{" "}
                <a
                  href="https://x.com/code_kartik"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-brand-700 underline underline-offset-2 outline-none transition-colors duration-150 hover:text-brand"
                >
                  X
                </a>
                .
              </p>
            </article>
          </div>
        </div>
      </main>

      <SiteFooter />
    </div>
  )
}

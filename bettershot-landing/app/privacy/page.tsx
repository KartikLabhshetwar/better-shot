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
    title: "The short version",
    body: [
      "Better Shot is a free, open-source screenshot and screen recording app for macOS. The app has no account system, no telemetry, and no analytics. Nothing you capture is sent anywhere unless you explicitly click Share, and even then it goes to storage you own.",
    ],
  },
  {
    title: "What the app stores",
    body: [
      "Screenshots and recordings are written to the save folder you choose. Capture history, your preferences, and your default effects are stored locally in Application Support and UserDefaults. History keeps the 100 most recent captures by default and can be changed or cleared in Settings.",
      "If you configure share links, your Cloudflare R2 access key ID and secret access key are stored in the macOS Keychain. Non-secret configuration (account ID, bucket name, public base URL) lives in UserDefaults.",
    ],
  },
  {
    title: "Share links",
    body: [
      "Share links are opt-in and off by default. When enabled, the app uploads the file directly from your Mac to your own Cloudflare R2 bucket over a signed request. There is no proxy, no relay, and no Better Shot server in the path. We never see the file, the link, or the bucket, and we cannot delete or access anything you upload. Deleting a shared capture means deleting the object from your own bucket.",
    ],
  },
  {
    title: "Screen, microphone, and camera access",
    body: [
      "macOS asks for screen recording permission before the first capture, and for microphone or camera permission only if you turn those on in the recording bar. All three streams are processed on-device and written into your recording. None of them are transmitted.",
    ],
  },
  {
    title: "Website analytics",
    body: [
      "This website uses Umami, a privacy-focused analytics tool, to count page views and downloads. It sets no cookies, uses no cross-site identifiers, and collects no personal information. The app itself contains no analytics of any kind.",
    ],
  },
  {
    title: "Third parties",
    body: [
      "The app bundles no third-party SDKs. Its only outbound network calls are the GitHub update check and, if you enable them, share uploads to your own bucket. Better Shot is distributed through GitHub Releases and Homebrew, which apply their own privacy policies when you download from them.",
    ],
  },
  {
    title: "Verify it yourself",
    body: [
      "Better Shot is open source under the BSD 3-Clause license. Every claim on this page can be checked against the source code on GitHub.",
    ],
  },
]

export default function PrivacyPolicy() {
  return (
    <div className="min-h-screen w-full bg-canvas text-ink selection:bg-brand/20">
      <SiteNav />

      <main className="pt-14">
        <div className="max-w-[680px] mx-auto px-5 sm:px-6 pt-20 pb-24">
          <p className="inline-flex items-center gap-2 text-[11px] font-semibold uppercase tracking-[0.12em] text-brand mb-4">
            <span className="h-1 w-1 rounded-full bg-brand" />
            Privacy
          </p>
          <h1 className="text-[34px] sm:text-[42px] font-bold tracking-[-0.035em] text-ink leading-[1.1] mb-3">
            Privacy Policy
          </h1>
          <p className="text-[13px] text-ink/30 mb-12 font-mono">Last updated: August 24, 2026</p>

          <div className="space-y-10">
            {sections.map((section) => (
              <section key={section.title}>
                <h2 className="text-[17px] font-bold tracking-[-0.02em] text-ink mb-3">
                  {section.title}
                </h2>
                {section.body.map((paragraph, i) => (
                  <p key={i} className="text-[15px] leading-[1.8] text-ink/50 mb-3 last:mb-0">
                    {paragraph}
                  </p>
                ))}
              </section>
            ))}

            <section>
              <h2 className="text-[17px] font-bold tracking-[-0.02em] text-ink mb-3">Contact</h2>
              <p className="text-[15px] leading-[1.8] text-ink/50">
                Questions about this policy? Reach out on{" "}
                <a
                  href="https://x.com/code_kartik"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-ink/75 underline decoration-ink/20 underline-offset-2 hover:decoration-ink/60 transition-colors"
                >
                  Twitter
                </a>{" "}
                or open an issue on{" "}
                <a
                  href="https://github.com/KartikLabhshetwar/better-shot/issues"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-ink/75 underline decoration-ink/20 underline-offset-2 hover:decoration-ink/60 transition-colors"
                >
                  GitHub
                </a>
                .
              </p>
            </section>
          </div>
        </div>
      </main>

      <SiteFooter />
    </div>
  )
}

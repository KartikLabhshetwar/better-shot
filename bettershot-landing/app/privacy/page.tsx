import type { Metadata } from "next"
import Link from "next/link"

export const metadata: Metadata = {
  title: "Privacy Policy - Better Shot",
  description: "Privacy policy for Better Shot, the free open-source screenshot tool for macOS.",
  alternates: {
    canonical: "/privacy",
  },
}

export default function PrivacyPolicy() {
  return (
    <div className="min-h-screen bg-[#0a0a0a] text-white/80">
      <header className="border-b border-white/[0.06]">
        <div className="max-w-[720px] mx-auto px-6 h-14 flex items-center">
          <Link href="/" className="flex items-center gap-2.5">
            <img src="/icon.png" alt="Better Shot" className="w-6 h-6" />
            <span className="text-[15px] font-medium text-white/90">Better Shot</span>
          </Link>
        </div>
      </header>

      <main className="max-w-[720px] mx-auto px-6 py-16">
        <h1 className="text-3xl font-semibold tracking-tight text-white mb-2">
          Privacy Policy
        </h1>
        <p className="text-[13px] text-white/30 mb-12">
          Last updated: June 2, 2026
        </p>

        <div className="space-y-10 text-[15px] leading-relaxed text-white/50">
          <section>
            <h2 className="text-lg font-medium text-white/80 mb-3">Overview</h2>
            <p>
              Better Shot is a free, open-source screenshot tool for macOS. We are committed
              to protecting your privacy. This policy explains what data we collect and how
              we use it.
            </p>
          </section>

          <section>
            <h2 className="text-lg font-medium text-white/80 mb-3">Data Collection</h2>
            <p className="mb-3">
              <strong className="text-white/70">Better Shot does not collect, store, or transmit
              any personal data.</strong> All screenshots and annotations are processed locally
              on your device and never leave your computer.
            </p>
            <p>
              The application does not require an account, login, or any form of registration.
            </p>
          </section>

          <section>
            <h2 className="text-lg font-medium text-white/80 mb-3">Website Analytics</h2>
            <p>
              This website (bettershot.site) uses Umami, a privacy-focused analytics tool,
              to collect anonymous usage statistics such as page views and download counts.
              No personal information, cookies, or tracking identifiers are used. All data
              is aggregated and cannot be traced to individual users.
            </p>
          </section>

          <section>
            <h2 className="text-lg font-medium text-white/80 mb-3">Third-Party Services</h2>
            <p>
              Better Shot does not integrate with any third-party services that collect user
              data. The application is distributed via GitHub Releases and Homebrew.
            </p>
          </section>

          <section>
            <h2 className="text-lg font-medium text-white/80 mb-3">Open Source</h2>
            <p>
              Better Shot is open source under the MIT License. You can inspect the full
              source code on{" "}
              <a
                href="https://github.com/KartikLabhshetwar/better-shot"
                target="_blank"
                rel="noopener noreferrer"
                className="text-white/70 underline underline-offset-4 hover:text-white/90 transition-colors"
              >
                GitHub
              </a>{" "}
              to verify these claims.
            </p>
          </section>

          <section>
            <h2 className="text-lg font-medium text-white/80 mb-3">Contact</h2>
            <p>
              If you have questions about this privacy policy, you can reach out via{" "}
              <a
                href="https://x.com/code_kartik"
                target="_blank"
                rel="noopener noreferrer"
                className="text-white/70 underline underline-offset-4 hover:text-white/90 transition-colors"
              >
                Twitter
              </a>{" "}
              or open an issue on{" "}
              <a
                href="https://github.com/KartikLabhshetwar/better-shot/issues"
                target="_blank"
                rel="noopener noreferrer"
                className="text-white/70 underline underline-offset-4 hover:text-white/90 transition-colors"
              >
                GitHub
              </a>
              .
            </p>
          </section>
        </div>

        <div className="mt-16 pt-6 border-t border-white/[0.06]">
          <Link
            href="/"
            className="text-[13px] text-white/30 hover:text-white/50 transition-colors"
          >
            &larr; Back to home
          </Link>
        </div>
      </main>
    </div>
  )
}

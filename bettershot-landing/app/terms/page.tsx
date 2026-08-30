import type { Metadata } from "next"
import { SiteNav } from "@/components/site-nav"
import { SiteFooter } from "@/components/site-footer"

export const metadata: Metadata = {
  title: "Terms of Use | Better Shot",
  description:
    "The terms that cover Better Shot, the free open source alternative to Loom and CleanShot X for macOS, and the bettershot.site website.",
  alternates: { canonical: "/terms" },
}

const sections = [
  {
    id: "use",
    title: "What you may do",
    body: [
      "Better Shot is free software released under the BSD 3 Clause license. Use it for personal, client, and commercial work. Modify it, redistribute it, and ship it inside your own product, subject to the license's attribution requirement.",
      "There is no watermark on exports and no restriction on how many people see what you make with it. There is no account to create, nothing to pay, and nothing to cancel.",
    ],
  },
  {
    id: "license",
    title: "The license governs the software",
    body: [
      "The LICENSE file in the repository is the binding agreement for the app itself. If anything on this page conflicts with it, the LICENSE file wins.",
      "Redistribution in source or binary form must keep the copyright notice, the list of conditions, and the disclaimer. The Better Shot name and the author's name may not be used to endorse a derived product without permission.",
    ],
  },
  {
    id: "warranty",
    title: "No warranty",
    body: [
      "The software is provided as is, without warranty of any kind. Screen capture touches recording permissions, display drivers, and video encoding, and it can fail in ways that lose a recording. Crash-safe fragmented MP4 writes reduce that risk but do not eliminate it. Keep your own backups of anything that matters. The authors and contributors are not liable for any damages arising from use of the software.",
    ],
  },
  {
    id: "content",
    title: "What you capture is yours",
    body: [
      "Better Shot has no server. Captures are written to your Mac (or held in the screenshot deck until saved), and share links upload directly from your Mac to a Cloudflare R2 bucket you own and control. We do not host, moderate, index, or have any ability to access what you capture or share.",
      "You are responsible for what you record and share, including consent, confidentiality obligations, and anything visible on screen. Redaction masks (blur, pixelate, spotlight) destroy their pixels on export, but checking the export before you send it is still your job.",
    ],
  },
  {
    id: "storage",
    title: "Your storage, your terms",
    body: [
      "If you connect a Cloudflare R2 bucket, that bucket is yours: its costs, its access rules, and its retention are between you and Cloudflare. Better Shot only signs and sends the upload you ask for, is not a party to that relationship, cannot recover your objects, and cannot restore a bucket you delete.",
    ],
  },
  {
    id: "updates",
    title: "Updates and availability",
    body: [
      "The app checks GitHub for new releases and can install them. Releases are published when they are ready, with no schedule and no guarantee that any feature will keep working the same way, or at all, in a later version. The website and its downloads are provided without any uptime commitment.",
    ],
  },
  {
    id: "contributions",
    title: "Contributions",
    body: [
      "Pull requests and issues are welcome. Anything you contribute to the repository is licensed under the same BSD 3 Clause license as the rest of the project.",
    ],
  },
  {
    id: "site",
    title: "This website",
    body: [
      "Pricing quoted for other products reflects what those vendors published in August 2026 and may have changed since. Nothing here is an offer, a guarantee of availability, or a commitment to a future feature.",
    ],
  },
  {
    id: "changes",
    title: "Changes",
    body: [
      "These terms may be updated alongside a release. The license itself governs in any conflict, and its text in the repository is authoritative and changes only through a commit you can read.",
    ],
  },
]

export default function TermsOfUse() {
  return (
    <div className="min-h-screen w-full bg-white text-zinc-900">
      <SiteNav />

      <main id="main">
        <div className="mx-auto max-w-[680px] px-6">
          <header className="pb-10 pt-28 sm:pt-36">
            <p className="text-[13px] font-medium uppercase tracking-widest text-zinc-400">
              Terms &middot; Updated August 2026
            </p>
            <h1 className="mt-4 text-[clamp(2rem,5vw,3rem)] leading-[1.1] tracking-tight">
              The license is the agreement
            </h1>
            <p className="mt-4 max-w-lg text-[17px] leading-relaxed text-zinc-500">
              Better Shot is distributed under the BSD 3 Clause license. These terms restate what
              that means in practice and cover the website.
            </p>
          </header>

          <article>
            {sections.map((section) => (
              <section
                key={section.id}
                id={section.id}
                className="scroll-mt-20 border-t border-zinc-100 py-8"
              >
                <h2 className="mb-4 text-[20px] leading-[26px] tracking-tight">{section.title}</h2>
                {section.body.map((paragraph, i) => (
                  <p key={i} className="mb-4 text-[16px] leading-[28px] text-zinc-500 last:mb-0">
                    {paragraph}
                  </p>
                ))}
              </section>
            ))}

            <div className="border-t border-zinc-100 py-8">
              <p className="text-[14px] leading-[24px] text-zinc-400">
                Questions about any of this belong in an{" "}
                <a
                  href="https://github.com/KartikLabhshetwar/better-shot/issues"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-brand-700 underline underline-offset-2 transition-colors hover:text-brand"
                >
                  issue on GitHub
                </a>
                , where the answer is public.
              </p>
            </div>
          </article>
        </div>
      </main>

      <SiteFooter />
    </div>
  )
}

import type { Metadata } from "next"
import Link from "next/link"
import { SiteNav } from "@/components/site-nav"
import { SiteFooter } from "@/components/site-footer"
import { formatPostDate, posts } from "@/lib/blog"

export const metadata: Metadata = {
  title: "Blog | Better Shot",
  description:
    "Guides and comparisons on screen capture for macOS: CleanShot X, Loom, and CapCut alternatives, screen recording workflows, and local first sharing.",
  alternates: { canonical: "/blog" },
  openGraph: {
    title: "Blog | Better Shot",
    description: "Guides and comparisons on screen capture and screen recording for macOS.",
    url: "https://bettershot.site/blog",
    type: "website",
  },
}

export default function BlogIndex() {
  return (
    <div className="min-h-screen w-full bg-canvas text-ink">
      <SiteNav />

      <main id="main">
        <div className="mx-auto max-w-[1240px] px-6">
          <header className="pb-12 pt-[72px]">
            <span className="micro block text-[13px] font-extrabold uppercase text-brand-700">
              Blog
            </span>
            <h1 className="display mt-3.5 -ml-[0.058em] text-[clamp(38px,5.4vw,72px)]">
              Screen capture, written down
            </h1>
            <p className="mt-6 max-w-[54ch] text-[17px] leading-[28px] text-ink/80">
              Comparisons and workflow notes for people who take a lot of screenshots and record a
              lot of screens.
            </p>
          </header>

          <hr className="rule" />

          {posts.map((post, index) => (
            <Link
              key={post.slug}
              href={`/blog/${post.slug}`}
              className="group grid items-start gap-6 border-b-2 border-rule py-[42px] text-ink lg:grid-cols-[88px_minmax(0,1fr)] lg:gap-x-[clamp(24px,4vw,64px)]"
            >
              <p className="text-[15px] font-extrabold leading-[24px] tabular-nums">
                {String(index + 1).padStart(2, "0")}
              </p>
              <div>
                <div className="flex flex-wrap items-center gap-x-4 gap-y-2.5">
                  <span className="inline-flex items-center bg-brand-100 px-2.5 py-[3px] text-[11px] tracking-[0.02em] text-brand-800">
                    {post.tag}
                  </span>
                  <span className="micro text-[13px] uppercase text-ink/70">
                    {formatPostDate(post.date)} · {post.readingTime}
                  </span>
                </div>
                <h2 className="display-sm mt-4 max-w-[30ch] text-[clamp(24px,2.6vw,34px)]">
                  {post.headline}
                </h2>
                <p className="mt-4 max-w-[60ch] text-[16px] leading-[28px] text-ink/80">
                  {post.description}
                </p>
                <p className="mt-5 text-[15px] font-semibold text-brand-700 transition-colors duration-150 group-hover:text-brand">
                  Read post →
                </p>
              </div>
            </Link>
          ))}

          <section className="pb-[72px] pt-12">
            <p className="max-w-[54ch] text-[15px] leading-[26px] text-ink/70">
              More posts are on the way: recording a walkthrough people finish, redacting a demo
              before it ships, and setting up R2 share links on your own domain.
            </p>
          </section>
        </div>
      </main>

      <SiteFooter />
    </div>
  )
}

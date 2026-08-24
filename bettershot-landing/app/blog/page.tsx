import type { Metadata } from "next"
import Link from "next/link"
import { ArrowRight } from "lucide-react"
import { SiteNav } from "@/components/site-nav"
import { SiteFooter } from "@/components/site-footer"
import { formatPostDate, posts } from "@/lib/blog"

export const metadata: Metadata = {
  title: "Blog | Better Shot",
  description:
    "Guides and comparisons on screen capture for macOS: CleanShot X, Loom, and CapCut alternatives, screen recording workflows, and local-first sharing.",
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
    <div className="min-h-screen w-full bg-canvas text-ink selection:bg-brand/20">
      <SiteNav />

      <main className="pt-14">
        <div className="max-w-[760px] mx-auto px-5 sm:px-6 pt-20 pb-24">
          <p className="inline-flex items-center gap-2 text-[11px] font-semibold uppercase tracking-[0.12em] text-brand mb-4">
            <span className="h-1 w-1 rounded-full bg-brand" />
            Blog
          </p>
          <h1 className="text-[34px] sm:text-[44px] font-bold tracking-[-0.035em] text-ink leading-[1.1] mb-4">
            Screen capture, written down
          </h1>
          <p className="text-[16px] leading-[1.7] text-ink/45 max-w-[520px] mb-14">
            Comparisons and workflow notes for people who take a lot of screenshots and record a lot
            of screens.
          </p>

          <div className="space-y-4">
            {posts.map((post) => (
              <Link
                key={post.slug}
                href={`/blog/${post.slug}`}
                className="group block rounded-2xl border border-ink/[0.07] bg-white p-6 sm:p-8 hover:border-ink/[0.14] transition-colors"
              >
                <div className="flex items-center gap-3 mb-3">
                  <span className="inline-flex items-center h-[20px] px-2 rounded-md bg-brand/12 text-[10.5px] font-semibold text-brand tracking-wide uppercase">
                    {post.tag}
                  </span>
                  <span className="text-[12px] text-ink/30 font-mono">
                    {formatPostDate(post.date)}
                  </span>
                  <span className="text-[12px] text-ink/25">{post.readingTime}</span>
                </div>
                <h2 className="text-[21px] sm:text-[24px] font-bold tracking-[-0.025em] text-ink leading-[1.25] mb-2.5">
                  {post.headline}
                </h2>
                <p className="text-[14.5px] leading-[1.7] text-ink/45 mb-5">{post.description}</p>
                <span className="inline-flex items-center gap-1.5 text-[13px] font-medium text-ink/60 group-hover:text-ink transition-colors">
                  Read post
                  <ArrowRight className="h-3.5 w-3.5 group-hover:translate-x-0.5 transition-transform" />
                </span>
              </Link>
            ))}
          </div>
        </div>
      </main>

      <SiteFooter />
    </div>
  )
}

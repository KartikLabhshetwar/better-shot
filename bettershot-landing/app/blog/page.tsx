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
    <div className="min-h-screen w-full bg-white text-zinc-900">
      <SiteNav />

      <main id="main">
        <div className="mx-auto max-w-[1100px] px-6">
          <header className="pb-12 pt-28 sm:pt-32">
            <span className="text-[13px] font-medium uppercase tracking-widest text-zinc-400">
              Blog
            </span>
            <h1 className="mt-4 text-[clamp(38px,5.4vw,60px)] font-extrabold tracking-tight">
              Screen capture, written down
            </h1>
            <p className="mt-6 max-w-[54ch] text-[17px] leading-[28px] text-zinc-500">
              Comparisons and workflow notes for people who take a lot of screenshots and record a
              lot of screens.
            </p>
          </header>

          <div className="space-y-0">
            {posts.map((post) => (
              <Link
                key={post.slug}
                href={`/blog/${post.slug}`}
                className="group block border-t border-zinc-200 py-8 sm:py-10"
              >
                <div className="flex flex-wrap items-center gap-x-3 gap-y-2">
                  <span className="rounded-full bg-brand-100 px-3 py-1 text-[12px] font-medium text-brand-700">
                    {post.tag}
                  </span>
                  <span className="text-[13px] text-zinc-400">
                    {formatPostDate(post.date)} &middot; {post.readingTime}
                  </span>
                </div>
                <h2 className="mt-3 max-w-[36ch] text-[clamp(22px,2.4vw,30px)] font-extrabold tracking-tight">
                  {post.headline}
                </h2>
                <p className="mt-3 max-w-[60ch] text-[16px] leading-[28px] text-zinc-500">
                  {post.description}
                </p>
                <p className="mt-4 text-[15px] font-semibold text-brand transition-colors duration-150 group-hover:text-brand-700">
                  Read post &rarr;
                </p>
              </Link>
            ))}
          </div>

          <section className="border-t border-zinc-200 pb-16 pt-10">
            <p className="max-w-[54ch] text-[15px] leading-[26px] text-zinc-400">
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

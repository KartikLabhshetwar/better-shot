import Image from "next/image"
import Link from "next/link"

export default function ShareNotFound() {
  return (
    <div className="flex min-h-dvh flex-col items-center justify-center gap-6 bg-canvas px-6 text-center text-ink">
      <Image src="/logo.png" alt="" width={44} height={44} className="rounded-xl opacity-80" />
      <div className="space-y-3">
        <h1 className="text-2xl font-bold tracking-tight">This link is unavailable</h1>
        <p className="max-w-[420px] text-sm leading-relaxed text-ink/65">
          The capture may have been deleted, the link may be incomplete, or it was never shared
          publicly.
        </p>
      </div>
      <Link
        href="/"
        className="inline-flex items-center rounded-xl bg-ink px-4 py-3 text-sm font-semibold text-canvas outline-none duration-300 ease-[cubic-bezier(0.32,0.72,0,1)] hover:bg-ink/85 focus-visible:ring-2 focus-visible:ring-brand/60 focus-visible:ring-offset-2 focus-visible:ring-offset-canvas active:scale-[0.98]"
      >
        Get Better Shot
      </Link>
    </div>
  )
}

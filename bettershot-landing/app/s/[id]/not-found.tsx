import Image from "next/image"
import Link from "next/link"

export default function ShareNotFound() {
  return (
    <div className="flex min-h-dvh flex-col items-center justify-center gap-6 bg-white px-6 text-center text-zinc-900">
      <Image src="/logo.png" alt="" width={44} height={44} className="rounded-xl opacity-80" />
      <div className="space-y-3">
        <h1 className="text-2xl tracking-tight">This link is unavailable</h1>
        <p className="max-w-[420px] text-sm leading-relaxed text-zinc-500">
          The capture may have been deleted, the link may be incomplete, or it was never shared
          publicly.
        </p>
      </div>
      <Link
        href="/"
        className="inline-flex items-center rounded-xl bg-brand px-4 py-3 text-sm font-semibold text-white outline-none transition-colors duration-150 hover:bg-brand-600 focus-visible:ring-2 focus-visible:ring-brand/60 active:scale-[0.98]"
      >
        Get Better Shot
      </Link>
    </div>
  )
}

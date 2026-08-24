import Image from "next/image"
import Link from "next/link"

export default function ShareNotFound() {
  return (
    <div className="flex min-h-dvh flex-col items-center justify-center gap-5 bg-[#08080a] px-6 text-center text-white">
      <Image src="/logo.png" alt="" width={44} height={44} className="rounded-xl opacity-80" />
      <div className="space-y-2">
        <h1 className="text-xl font-semibold tracking-tight">This link is unavailable</h1>
        <p className="max-w-sm text-pretty text-sm text-white/50">
          The capture may have been deleted, the link may be incomplete, or it was never shared
          publicly.
        </p>
      </div>
      <Link
        href="/"
        className="inline-flex h-9 items-center rounded-lg bg-white px-4 text-sm font-semibold text-black transition-transform duration-150 ease-out hover:scale-[1.03] active:scale-[0.97] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/70 focus-visible:ring-offset-2 focus-visible:ring-offset-[#08080a] motion-reduce:transition-none motion-reduce:hover:scale-100"
      >
        Get Better Shot
      </Link>
    </div>
  )
}

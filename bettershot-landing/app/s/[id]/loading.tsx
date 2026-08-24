export default function ShareLoading() {
  return (
    <div className="flex min-h-dvh flex-col bg-[#08080a]">
      <header className="border-b border-white/5">
        <div className="mx-auto flex h-14 w-full max-w-6xl items-center gap-3 px-4 sm:px-6">
          <div className="size-6 animate-pulse rounded-md bg-white/10" />
          <div className="h-3.5 w-28 animate-pulse rounded bg-white/10" />
          <div className="flex-1" />
          <div className="h-8 w-20 animate-pulse rounded-lg bg-white/10" />
          <div className="h-8 w-24 animate-pulse rounded-lg bg-white/10" />
        </div>
      </header>

      <main className="mx-auto w-full max-w-6xl flex-1 px-4 pb-10 pt-6 sm:px-6 sm:pt-10">
        <div className="mb-4 space-y-2">
          <div className="h-6 w-64 max-w-full animate-pulse rounded bg-white/10" />
          <div className="h-3 w-44 animate-pulse rounded bg-white/5" />
        </div>
        <div className="aspect-video w-full animate-pulse rounded-2xl bg-white/[0.06] ring-1 ring-white/10" />
      </main>
    </div>
  )
}

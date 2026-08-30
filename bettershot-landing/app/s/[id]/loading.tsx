export default function ShareLoading() {
  return (
    <div className="flex min-h-dvh flex-col bg-white">
      <header className="border-b border-zinc-200">
        <div className="mx-auto flex h-14 w-full max-w-[1100px] items-center gap-3 px-6">
          <div className="h-6 w-6 animate-pulse rounded-md bg-zinc-100" />
          <div className="h-4 w-24 animate-pulse rounded-sm bg-zinc-100" />
          <div className="flex-1" />
          <div className="h-8 w-20 animate-pulse rounded-xl bg-zinc-100" />
          <div className="h-8 w-24 animate-pulse rounded-xl bg-zinc-100" />
        </div>
      </header>

      <main className="mx-auto w-full max-w-[1100px] flex-1 px-6 pb-12 pt-8">
        <div className="mb-6 space-y-2">
          <div className="h-6 w-64 max-w-full animate-pulse rounded-sm bg-zinc-100" />
          <div className="h-3 w-40 animate-pulse rounded-sm bg-zinc-50" />
        </div>
        <div className="aspect-video w-full animate-pulse rounded-2xl bg-zinc-50 ring-1 ring-zinc-200" />
      </main>
    </div>
  )
}

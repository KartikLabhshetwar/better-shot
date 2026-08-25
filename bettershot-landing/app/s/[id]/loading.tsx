export default function ShareLoading() {
  return (
    <div className="flex min-h-dvh flex-col bg-canvas">
      <header className="border-b border-ink/[0.06]">
        <div className="mx-auto flex h-16 w-full max-w-[1080px] items-center gap-3 px-6">
          <div className="h-6 w-6 animate-pulse rounded-md bg-ink/10" />
          <div className="h-4 w-24 animate-pulse rounded-sm bg-ink/10" />
          <div className="flex-1" />
          <div className="h-8 w-20 animate-pulse rounded-lg bg-ink/10" />
          <div className="h-8 w-24 animate-pulse rounded-lg bg-ink/10" />
        </div>
      </header>

      <main className="mx-auto w-full max-w-[1080px] flex-1 px-6 pb-12 pt-8">
        <div className="mb-6 space-y-2">
          <div className="h-6 w-64 max-w-full animate-pulse rounded-sm bg-ink/10" />
          <div className="h-3 w-40 animate-pulse rounded-sm bg-ink/5" />
        </div>
        <div className="aspect-video w-full animate-pulse rounded-2xl bg-ink/[0.06] ring-1 ring-ink/10" />
      </main>
    </div>
  )
}

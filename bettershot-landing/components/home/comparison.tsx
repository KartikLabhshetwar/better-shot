import Link from "next/link"
import { SectionLabel } from "@/components/section"

type Cell = boolean | "partial" | string

const products = ["Better Shot", "CleanShot X", "Loom", "CapCut"]

const rows: { label: string; cells: Cell[] }[] = [
  { label: "Price", cells: ["Free", "$29 + $8/mo", "$18/seat/mo", "$19.99/mo"] },
  { label: "Open source", cells: [true, false, false, false] },
  { label: "Works fully offline", cells: [true, "partial", false, "partial"] },
  { label: "Screenshot capture", cells: [true, true, false, false] },
  { label: "Screen recording", cells: [true, true, true, true] },
  { label: "Cursor auto-zoom", cells: [true, false, false, "partial"] },
  { label: "Cursor smoothing", cells: [true, false, false, false] },
  { label: "Face cam bubble", cells: [true, false, true, true] },
  { label: "On device captions", cells: [true, false, "partial", "partial"] },
  { label: "Keystroke overlay", cells: [true, false, false, false] },
  { label: "Blur and masks", cells: [true, "partial", false, "partial"] },
  { label: "3D tilt", cells: [true, false, false, true] },
  { label: "Trimming and speed", cells: [true, "partial", "partial", true] },
  { label: "Backgrounds", cells: [true, true, false, true] },
  { label: "Share links", cells: ["Your R2 bucket", "Their cloud", "Their cloud", "Their cloud"] },
  { label: "Account required", cells: [false, "partial", true, true] },
  { label: "No watermark", cells: [true, true, "partial", "partial"] },
]

function CellValue({ value }: { value: Cell }) {
  if (typeof value === "string" && value !== "partial") return <>{value}</>
  if (value === true) {
    return (
      <>
        <svg className="size-4 text-brand" viewBox="0 0 16 16" fill="currentColor" aria-hidden="true">
          <path d="M8 1a7 7 0 1 1 0 14A7 7 0 0 1 8 1Zm3.02 4.72a.75.75 0 0 0-1.06.02L7.4 8.42 6.02 7.1a.75.75 0 1 0-1.04 1.08l1.9 1.83a.75.75 0 0 0 1.05-.01l3.07-3.22a.75.75 0 0 0-.02-1.06h.04Z" />
        </svg>
        <span className="sr-only">Yes</span>
      </>
    )
  }
  if (value === false) {
    return (
      <>
        <span className="text-[13px] text-zinc-300" aria-hidden>—</span>
        <span className="sr-only">No</span>
      </>
    )
  }
  return (
    <>
      <svg className="size-4 text-zinc-400" viewBox="0 0 16 16" fill="currentColor" aria-hidden="true">
        <circle cx="8" cy="8" r="7" fill="none" stroke="currentColor" strokeWidth="1.5" />
        <circle cx="8" cy="8" r="2" />
      </svg>
      <span className="sr-only">With limits</span>
    </>
  )
}

function MobileCard({ product, index }: { product: string; index: number }) {
  const isBetterShot = index === 0
  return (
    <div className={`rounded-2xl border p-5 ${isBetterShot ? "border-brand/20 bg-brand/[0.02]" : "border-zinc-200"}`}>
      <h3 className={`text-[15px] font-semibold ${isBetterShot ? "text-brand" : "text-zinc-900"}`}>
        {product}
      </h3>
      <p className={`mt-0.5 text-[13px] ${isBetterShot ? "text-brand" : "text-zinc-500"}`}>
        {rows[0].cells[index] as string}
      </p>
      <div className="mt-4 space-y-2.5">
        {rows.slice(1).map((row) => (
          <div key={row.label} className="flex items-center justify-between gap-3">
            <span className="text-[13px] text-zinc-600">{row.label}</span>
            <span className="flex shrink-0 items-center">
              {typeof row.cells[index] === "string" && row.cells[index] !== "partial" ? (
                <span className={`text-[12px] ${isBetterShot ? "text-brand" : "text-zinc-500"}`}>
                  {row.cells[index] as string}
                </span>
              ) : (
                <CellValue value={row.cells[index]} />
              )}
            </span>
          </div>
        ))}
      </div>
    </div>
  )
}

export function Comparison() {
  return (
    <section
      id="compare"
      className="mx-auto max-w-[1100px] scroll-mt-20 px-6 py-14 sm:py-20"
    >
      <SectionLabel className="mb-3.5">Comparison</SectionLabel>
      <h2 className="max-w-[26ch] text-[28px] tracking-tight sm:text-[32px]">
        One app instead of three subscriptions
      </h2>
      <p className="mt-6 max-w-[60ch] text-[16px] leading-[28px] text-zinc-500">
        Most people run CleanShot X for screenshots, Loom for walkthroughs, and CapCut when the
        recording needs an edit. Better Shot covers that path on your own machine.
      </p>

      <div className="mt-8 hidden md:block">
        <table className="w-full border-collapse text-[14px]">
          <thead>
            <tr>
              <th className="w-[34%] border-b border-zinc-200 px-3 py-2.5 text-left text-[11px] font-semibold uppercase tracking-wider text-zinc-400">
                Feature
              </th>
              {products.map((product, i) => (
                <th
                  key={product}
                  className={`whitespace-nowrap border-b border-zinc-200 px-3 py-2.5 text-left text-[11px] font-semibold uppercase tracking-wider ${
                    i === 0 ? "text-brand" : "text-zinc-400"
                  }`}
                >
                  {product}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {rows.map((row) => (
              <tr key={row.label} className="transition-colors hover:bg-zinc-50">
                <td className="border-b border-zinc-100 px-3 py-2.5 font-medium text-zinc-900">{row.label}</td>
                {row.cells.map((cell, i) => (
                  <td
                    key={products[i]}
                    className={`border-b border-zinc-100 px-3 py-2.5 ${
                      i === 0 ? "text-brand" : "text-zinc-500"
                    }`}
                  >
                    <CellValue value={cell} />
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <div className="mt-8 grid gap-4 md:hidden">
        {products.map((product, i) => (
          <MobileCard key={product} product={product} index={i} />
        ))}
      </div>

      <p className="mt-4 hidden text-[13px] leading-[22px] text-zinc-400 md:block">
        Competitor pricing as published in August 2026.
      </p>
      <p className="mt-6">
        <Link
          href="/blog/cleanshot-x-capcut-loom-alternative"
          className="text-[15px] font-semibold text-brand-700 outline-none transition-colors duration-150 hover:text-brand"
        >
          Read the full comparison &rarr;
        </Link>
      </p>
    </section>
  )
}

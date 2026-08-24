import Link from "next/link"
import { ArrowUpRight, Check, Minus, X } from "lucide-react"
import { SectionLabel } from "@/components/home/faq"

type Cell = boolean | "partial" | string

const products = ["Better Shot", "CleanShot X", "Loom", "CapCut"]

const rows: { label: string; cells: Cell[] }[] = [
  { label: "Price", cells: ["Free", "$29 + $8/mo cloud", "$18/seat/mo", "$19.99/mo Pro"] },
  { label: "Open source", cells: [true, false, false, false] },
  { label: "Works fully offline", cells: [true, "partial", false, "partial"] },
  { label: "Screenshot capture & annotation", cells: [true, true, false, false] },
  { label: "Screen recording", cells: [true, true, true, "partial"] },
  { label: "Cursor auto-zoom", cells: [true, false, false, "partial"] },
  { label: "Face cam bubble", cells: [true, false, true, true] },
  { label: "Video trimming & speed", cells: [true, "partial", "partial", true] },
  { label: "Backgrounds & beautify", cells: [true, true, false, true] },
  { label: "Share links", cells: ["Your own R2 bucket", "Their cloud", "Their cloud", "Their cloud"] },
  { label: "Account required", cells: [false, "partial", true, true] },
  { label: "No watermark", cells: [true, true, true, "partial"] },
]

function CellValue({ value, highlight }: { value: Cell; highlight: boolean }) {
  if (value === true)
    return (
      <Check
        className={`h-[17px] w-[17px] mx-auto ${highlight ? "text-emerald-600" : "text-ink/45"}`}
        aria-label="Yes"
      />
    )
  if (value === false)
    return <X className="h-[17px] w-[17px] mx-auto text-ink/20" aria-label="No" />
  if (value === "partial")
    return <Minus className="h-[17px] w-[17px] mx-auto text-amber-500/70" aria-label="Partial" />
  return (
    <span className={`text-[12.5px] ${highlight ? "text-ink/80 font-medium" : "text-ink/45"}`}>
      {value}
    </span>
  )
}

export function Comparison() {
  return (
    <section
      id="compare"
      className="border-t border-ink/[0.06] bg-ink/[0.015] py-20 sm:py-28 scroll-mt-14"
    >
      <div className="max-w-[960px] mx-auto px-5 sm:px-6">
        <SectionLabel>Comparison</SectionLabel>
        <h2 className="text-[28px] sm:text-[36px] font-bold tracking-[-0.03em] text-ink mb-3 max-w-[560px]">
          One app instead of three subscriptions
        </h2>
        <p className="text-[15px] leading-[1.7] text-ink/45 mb-10 max-w-[560px]">
          Most people run CleanShot X for screenshots, Loom for quick walkthroughs, and CapCut when
          the recording needs an edit. Better Shot covers that whole path, on your own machine.
        </p>

        <div className="overflow-x-auto -mx-5 sm:mx-0 px-5 sm:px-0">
          <table className="w-full min-w-[640px] border-separate border-spacing-0 bg-white rounded-2xl border border-ink/[0.07] overflow-hidden shadow-[0_1px_2px_rgba(0,0,0,0.03)]">
            <thead>
              <tr>
                <th className="text-left text-[11px] font-semibold uppercase tracking-wider text-ink/30 px-5 py-4 border-b border-ink/[0.07]">
                  Feature
                </th>
                {products.map((product, i) => (
                  <th
                    key={product}
                    className={`text-center text-[12.5px] font-semibold px-4 py-4 border-b border-ink/[0.07] whitespace-nowrap ${
                      i === 0 ? "text-ink bg-brand/[0.07]" : "text-ink/45"
                    }`}
                  >
                    {product}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {rows.map((row, rowIndex) => (
                <tr key={row.label}>
                  <td
                    className={`text-[13.5px] text-ink/65 px-5 py-3.5 ${
                      rowIndex === rows.length - 1 ? "" : "border-b border-ink/[0.05]"
                    }`}
                  >
                    {row.label}
                  </td>
                  {row.cells.map((cell, i) => (
                    <td
                      key={i}
                      className={`text-center px-4 py-3.5 ${
                        rowIndex === rows.length - 1 ? "" : "border-b border-ink/[0.05]"
                      } ${i === 0 ? "bg-brand/[0.05]" : ""}`}
                    >
                      <CellValue value={cell} highlight={i === 0} />
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        <div className="flex flex-col sm:flex-row sm:items-center gap-3 sm:gap-6 mt-6">
          <p className="text-[11.5px] text-ink/30">
            Competitor pricing as published in August 2026. Partial (
            <Minus className="inline h-3 w-3 text-amber-500/70 align-[-1px]" />) means the feature
            exists with meaningful limits.
          </p>
          <Link
            href="/blog/cleanshot-x-capcut-loom-alternative"
            className="inline-flex items-center gap-1 text-[13px] font-medium text-ink/70 hover:text-ink transition-colors shrink-0"
          >
            Read the full comparison
            <ArrowUpRight className="h-3.5 w-3.5" />
          </Link>
        </div>
      </div>
    </section>
  )
}

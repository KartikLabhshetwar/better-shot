import Link from "next/link"
import { SectionLabel } from "@/components/section"

type Cell = boolean | "partial" | string

const products = ["Better Shot", "CleanShot X", "Loom", "CapCut"]

const rows: { label: string; cells: Cell[] }[] = [
  { label: "Price", cells: ["Free", "$29 + $8/mo", "$18/seat/mo", "$19.99/mo"] },
  { label: "Open source", cells: [true, false, false, false] },
  { label: "Works fully offline", cells: [true, "partial", false, "partial"] },
  { label: "Screenshot capture and annotation", cells: [true, true, false, false] },
  { label: "Screen recording", cells: [true, true, true, true] },
  { label: "Cursor auto-zoom", cells: [true, false, false, "partial"] },
  { label: "Drawn cursor smoothing", cells: [true, false, false, false] },
  { label: "Face cam bubble", cells: [true, false, true, true] },
  { label: "On device captions", cells: [true, false, "partial", "partial"] },
  { label: "Keystroke overlay", cells: [true, false, false, false] },
  { label: "Blur and spotlight masks", cells: [true, "partial", false, "partial"] },
  { label: "Transitions and 3D tilt", cells: [true, false, false, true] },
  { label: "Video trimming and speed", cells: [true, "partial", "partial", true] },
  { label: "Backgrounds and beautify", cells: [true, true, false, true] },
  {
    label: "Share links",
    cells: ["Your R2 bucket", "Their cloud", "Their cloud", "Their cloud"],
  },
  { label: "Account required", cells: [false, "partial", true, true] },
  { label: "No watermark", cells: [true, true, "partial", "partial"] },
]

const glyph = { yes: "■", partial: "□", no: "—" } as const

function CellValue({ value }: { value: Cell }) {
  if (typeof value === "string" && value !== "partial") return <>{value}</>
  const key = value === true ? "yes" : value === false ? "no" : "partial"
  const label = value === true ? "Yes" : value === false ? "No" : "With meaningful limits"
  return (
    <>
      <span aria-hidden className="font-sans">
        {glyph[key]}
      </span>
      <span className="sr-only">{label}</span>
    </>
  )
}

export function Comparison() {
  return (
    <section
      id="compare"
      className="mx-auto max-w-[1240px] scroll-mt-20 border-t-2 border-rule px-6 py-14"
    >
      <SectionLabel className="mb-3.5">Comparison</SectionLabel>
      <h2 className="display -ml-[0.04em] max-w-[26ch] text-[clamp(30px,3.4vw,44px)]">
        One app instead of three subscriptions
      </h2>
      <p className="mt-6 max-w-[60ch] text-[16px] leading-[28px] text-ink/80">
        Most people run CleanShot X for screenshots, Loom for walkthroughs, and CapCut when the
        recording needs an edit. Better Shot covers that path on your own machine.
      </p>

      <div className="-mx-6 mt-8 overflow-x-auto px-6 sm:mx-0 sm:px-0">
        <table className="w-full min-w-[720px] border-collapse text-[14px]">
          <thead>
            <tr>
              <th className="micro w-[34%] border-b-2 border-rule px-2 py-2 text-left text-[11px] font-semibold uppercase text-ink/60">
                Feature
              </th>
              {products.map((product) => (
                <th
                  key={product}
                  className="micro whitespace-nowrap border-b-2 border-rule px-2 py-2 text-left text-[11px] font-semibold uppercase text-ink/60"
                >
                  {product}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {rows.map((row) => (
              <tr key={row.label}>
                <td className="border-b border-rule px-2 py-2 font-medium">{row.label}</td>
                {row.cells.map((cell, i) => (
                  <td
                    key={products[i]}
                    className={`border-b border-rule px-2 py-2 ${
                      i === 0 ? "text-brand" : "text-ink/70"
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

      <p className="mt-4 text-[13px] leading-[22px] text-ink/70">
        <span aria-hidden>■</span> yes &nbsp; <span aria-hidden>□</span> with meaningful limits
        &nbsp; <span aria-hidden>—</span> no. Competitor pricing as published in August 2026.
      </p>
      <p className="mt-6">
        <Link
          href="/blog/cleanshot-x-capcut-loom-alternative"
          className="text-[15px] font-semibold text-brand-700 outline-none transition-colors duration-150 hover:text-brand"
        >
          Read the full comparison →
        </Link>
      </p>
    </section>
  )
}

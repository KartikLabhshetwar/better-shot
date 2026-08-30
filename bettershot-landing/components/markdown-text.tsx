import { Fragment } from "react"

const pattern = /(\[[^\]]+\]\([^)]+\))|(\*\*[^*]+\*\*)|(`[^`]+`)/g

export function MarkdownText({ children }: { children: string }) {
  const parts = children.split(pattern).filter(Boolean)

  return (
    <>
      {parts.map((part, i) => {
        const link = part.match(/^\[([^\]]+)\]\(([^)]+)\)$/)
        if (link) {
          return (
            <a
              key={i}
              href={link[2]}
              target="_blank"
              rel="noopener noreferrer"
              className="text-zinc-600 underline decoration-zinc-300 underline-offset-2 transition-colors hover:decoration-zinc-500"
            >
              {link[1]}
            </a>
          )
        }
        if (part.startsWith("**") && part.endsWith("**")) {
          return (
            <strong key={i} className="font-semibold text-zinc-700">
              {part.slice(2, -2)}
            </strong>
          )
        }
        if (part.startsWith("`") && part.endsWith("`")) {
          return (
            <code
              key={i}
              className="rounded bg-zinc-100 px-1 py-[1px] font-mono text-[0.92em] text-zinc-600"
            >
              {part.slice(1, -1)}
            </code>
          )
        }
        return <Fragment key={i}>{part}</Fragment>
      })}
    </>
  )
}

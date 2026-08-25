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
              className="text-ink/70 underline decoration-ink/20 underline-offset-2 hover:decoration-ink/60 transition-colors"
            >
              {link[1]}
            </a>
          )
        }
        if (part.startsWith("**") && part.endsWith("**")) {
          return (
            <strong key={i} className="font-semibold text-ink/80">
              {part.slice(2, -2)}
            </strong>
          )
        }
        if (part.startsWith("`") && part.endsWith("`")) {
          return (
            <code
              key={i}
              className="font-mono text-[0.92em] text-ink/70 bg-ink/[0.05] rounded px-1 py-[1px]"
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

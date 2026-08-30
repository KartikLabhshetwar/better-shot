"use client"

import { useEffect, useRef, useState } from "react"

interface CountUpProps {
  value: string
  className?: string
}

function parseValue(raw: string): { prefix: string; num: number; suffix: string } | null {
  const match = raw.match(/^([^0-9]*)([0-9]+(?:\.[0-9]+)?)(.*)$/)
  if (!match) return null
  return { prefix: match[1], num: parseFloat(match[2]), suffix: match[3] }
}

export function CountUp({ value, className }: CountUpProps) {
  const parsed = parseValue(value)
  const [display, setDisplay] = useState(value)
  const ref = useRef<HTMLSpanElement>(null)
  const hasAnimated = useRef(false)

  useEffect(() => {
    if (!parsed || hasAnimated.current) return
    const el = ref.current
    if (!el) return

    const observer = new IntersectionObserver(
      ([entry]) => {
        if (!entry.isIntersecting || hasAnimated.current) return
        hasAnimated.current = true
        observer.disconnect()

        const duration = 1200
        const start = performance.now()
        const target = parsed.num
        const hasDecimal = value.includes(".")
        const decimalPlaces = hasDecimal ? (value.split(".")[1]?.match(/^[0-9]+/)?.[0]?.length ?? 0) : 0

        function frame(now: number) {
          const elapsed = now - start
          const progress = Math.min(elapsed / duration, 1)
          const eased = 1 - Math.pow(1 - progress, 3)
          const current = eased * target

          if (hasDecimal) {
            setDisplay(`${parsed.prefix}${current.toFixed(decimalPlaces)}${parsed.suffix}`)
          } else {
            setDisplay(`${parsed.prefix}${Math.round(current)}${parsed.suffix}`)
          }

          if (progress < 1) requestAnimationFrame(frame)
        }

        requestAnimationFrame(frame)
      },
      { threshold: 0.3 },
    )

    observer.observe(el)
    return () => observer.disconnect()
  }, [parsed, value])

  return (
    <span ref={ref} className={className}>
      {display}
    </span>
  )
}

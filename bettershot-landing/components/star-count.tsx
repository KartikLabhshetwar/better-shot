"use client"

import { useState, useEffect } from "react"

export function StarCount() {
  const [count, setCount] = useState<number | null>(null)

  useEffect(() => {
    fetch("https://api.github.com/repos/KartikLabhshetwar/better-shot")
      .then((r) => (r.ok ? r.json() : null))
      .then((d) => { if (d?.stargazers_count) setCount(d.stargazers_count) })
      .catch(() => {})
  }, [])

  return <>{count ? `${count} stars` : "GitHub"}</>
}

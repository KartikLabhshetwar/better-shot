import { z } from "zod"

export const SHARE_MANIFEST_VERSION = 1

const shareManifestSchema = z.object({
  version: z.number().int().positive(),
  id: z.string().min(1).max(128),
  kind: z.enum(["video", "image"]),
  title: z.string().max(200).optional(),
  media: z.string().min(1).max(300),
  poster: z.string().min(1).max(300).optional(),
  mimeType: z.string().max(120).optional(),
  width: z.number().int().positive().max(30000).optional(),
  height: z.number().int().positive().max(30000).optional(),
  durationSeconds: z.number().nonnegative().max(86400).optional(),
  byteSize: z.number().int().nonnegative().optional(),
  createdAt: z.string().max(64).optional(),
  authorName: z.string().max(120).optional(),
  appVersion: z.string().max(40).optional(),
})

export type ShareManifest = z.infer<typeof shareManifestSchema>

export interface ResolvedShare {
  manifest: ShareManifest
  mediaUrl: string
  posterUrl: string | null
}

const BLOCKED_HOSTNAMES = new Set([
  "localhost",
  "localhost.localdomain",
  "metadata.google.internal",
  "instance-data",
])

const MANIFEST_BYTE_LIMIT = 64 * 1024
const MANIFEST_TIMEOUT_MS = 6000

function isBlockedHost(hostname: string): boolean {
  const host = hostname.toLowerCase().replace(/^\[|\]$/g, "")
  if (BLOCKED_HOSTNAMES.has(host)) return true
  if (host.endsWith(".localhost") || host.endsWith(".internal")) return true
  if (host === "::1" || host === "0.0.0.0") return true

  const ipv4 = host.match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/)
  if (ipv4) {
    const [a, b] = ipv4.slice(1).map(Number)
    if (a === 10 || a === 127 || a === 0) return true
    if (a === 169 && b === 254) return true
    if (a === 172 && b >= 16 && b <= 31) return true
    if (a === 192 && b === 168) return true
    if (a >= 224) return true
  }

  if (host.startsWith("fc") || host.startsWith("fd") || host.startsWith("fe80:")) return true

  return false
}

export function decodeOrigin(encoded: string | undefined): URL | null {
  if (!encoded) return null

  let raw: string
  try {
    const padded = encoded.replace(/-/g, "+").replace(/_/g, "/")
    raw = Buffer.from(padded, "base64").toString("utf-8")
  } catch {
    return null
  }

  let url: URL
  try {
    url = new URL(raw)
  } catch {
    return null
  }

  if (url.protocol !== "https:") return null
  if (isBlockedHost(url.hostname)) return null
  if (url.username || url.password) return null

  return url
}

export function encodeOrigin(origin: string): string {
  return Buffer.from(origin, "utf-8")
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "")
}

function joinPath(origin: URL, ...segments: string[]): string {
  const base = origin.toString().replace(/\/+$/, "")
  const tail = segments
    .map((segment) => segment.replace(/^\/+|\/+$/g, ""))
    .filter(Boolean)
    .join("/")
  return `${base}/${tail}`
}

export function manifestUrl(origin: URL, id: string): string {
  return joinPath(origin, "s", id, "meta.json")
}

export async function resolveShare(
  id: string,
  encodedOrigin: string | undefined
): Promise<ResolvedShare | null> {
  const origin = decodeOrigin(encodedOrigin)
  if (!origin) return null
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(id)) return null

  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(), MANIFEST_TIMEOUT_MS)

  try {
    const response = await fetch(manifestUrl(origin, id), {
      signal: controller.signal,
      redirect: "error",
      next: { revalidate: 60 },
    })
    if (!response.ok) return null

    const length = Number(response.headers.get("content-length") ?? 0)
    if (length > MANIFEST_BYTE_LIMIT) return null

    const text = await response.text()
    if (text.length > MANIFEST_BYTE_LIMIT) return null

    const parsed = shareManifestSchema.safeParse(JSON.parse(text))
    if (!parsed.success) return null
    if (parsed.data.id !== id) return null

    return {
      manifest: parsed.data,
      mediaUrl: joinPath(origin, "s", id, parsed.data.media),
      posterUrl: parsed.data.poster ? joinPath(origin, "s", id, parsed.data.poster) : null,
    }
  } catch {
    return null
  } finally {
    clearTimeout(timeout)
  }
}

export function formatDuration(seconds: number): string {
  if (!Number.isFinite(seconds) || seconds < 0) return "0:00"
  const total = Math.floor(seconds)
  const hours = Math.floor(total / 3600)
  const minutes = Math.floor((total % 3600) / 60)
  const secs = total % 60
  if (hours > 0) {
    return `${hours}:${String(minutes).padStart(2, "0")}:${String(secs).padStart(2, "0")}`
  }
  return `${minutes}:${String(secs).padStart(2, "0")}`
}

export function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`
  const units = ["KB", "MB", "GB"]
  let value = bytes / 1024
  let unit = 0
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024
    unit += 1
  }
  return `${value.toFixed(value >= 10 ? 0 : 1)} ${units[unit]}`
}

export function formatRelativeTime(iso: string): string {
  const then = new Date(iso).getTime()
  if (Number.isNaN(then)) return ""
  const seconds = Math.round((Date.now() - then) / 1000)
  if (seconds < 60) return "just now"

  const table: [number, Intl.RelativeTimeFormatUnit][] = [
    [60, "minute"],
    [3600, "hour"],
    [86400, "day"],
    [604800, "week"],
    [2592000, "month"],
    [31536000, "year"],
  ]

  const formatter = new Intl.RelativeTimeFormat("en", { numeric: "auto" })
  let divisor = 60
  for (let i = table.length - 1; i >= 0; i -= 1) {
    if (seconds >= table[i][0]) {
      divisor = table[i][0]
      return formatter.format(-Math.round(seconds / divisor), table[i][1])
    }
  }
  return formatter.format(-Math.round(seconds / divisor), "minute")
}

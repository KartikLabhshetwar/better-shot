import type { NextRequest } from "next/server"
import { resolveShare } from "@/lib/share"

interface RouteContext {
  params: Promise<{ id: string }>
}

function contentDisposition(filename: string): string {
  const ascii = filename.replace(/[^\x20-\x7e]/g, "_").replace(/["\\]/g, "_")
  return `attachment; filename="${ascii}"; filename*=UTF-8''${encodeURIComponent(filename)}`
}

export async function GET(request: NextRequest, { params }: RouteContext) {
  const { id } = await params
  const share = await resolveShare(id, request.nextUrl.searchParams.get("b") ?? undefined)
  if (!share) return new Response("Not found", { status: 404 })

  let upstream: Response
  try {
    upstream = await fetch(share.mediaUrl, { redirect: "error", cache: "no-store" })
  } catch {
    return new Response("Upstream unavailable", { status: 502 })
  }

  if (!upstream.ok || !upstream.body) {
    return new Response("Upstream unavailable", { status: 502 })
  }

  const headers = new Headers()
  headers.set(
    "Content-Type",
    share.manifest.mimeType ?? upstream.headers.get("content-type") ?? "application/octet-stream"
  )
  headers.set("Content-Disposition", contentDisposition(share.manifest.media))
  headers.set("Cache-Control", "private, no-store")
  headers.set("X-Content-Type-Options", "nosniff")
  const length = upstream.headers.get("content-length")
  if (length) headers.set("Content-Length", length)

  return new Response(upstream.body, { headers })
}

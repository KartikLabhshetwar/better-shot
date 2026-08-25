import type { Metadata } from "next"
import { notFound } from "next/navigation"
import { ShareView } from "@/components/share/share-view"
import { formatDuration, resolveShare } from "@/lib/share"

interface SharePageProps {
  params: Promise<{ id: string }>
  searchParams: Promise<Record<string, string | string[] | undefined>>
}

function firstValue(value: string | string[] | undefined): string | undefined {
  return Array.isArray(value) ? value[0] : value
}

export async function generateMetadata({
  params,
  searchParams,
}: SharePageProps): Promise<Metadata> {
  const { id } = await params
  const share = await resolveShare(id, firstValue((await searchParams).b))

  if (!share) {
    return {
      title: "Link unavailable | Better Shot",
      robots: { index: false, follow: false },
    }
  }

  const { manifest, mediaUrl, posterUrl } = share
  const isVideo = manifest.kind === "video"
  const title = manifest.title?.trim() || (isVideo ? "Untitled recording" : "Untitled screenshot")
  const description = isVideo
    ? `Watch this ${manifest.durationSeconds ? formatDuration(manifest.durationSeconds) : ""} recording, captured with Better Shot.`.replace(
        /\s+/g,
        " "
      )
    : "View this screenshot, captured with Better Shot."

  return {
    title: `${title} | Better Shot`,
    description,
    robots: { index: false, follow: false },
    openGraph: {
      type: isVideo ? "video.other" : "article",
      title,
      description,
      siteName: "Better Shot",
      images: posterUrl
        ? [{ url: posterUrl, width: manifest.width, height: manifest.height, alt: title }]
        : isVideo
          ? undefined
          : [{ url: mediaUrl, width: manifest.width, height: manifest.height, alt: title }],
      videos: isVideo
        ? [
            {
              url: mediaUrl,
              secureUrl: mediaUrl,
              type: manifest.mimeType ?? "video/mp4",
              width: manifest.width,
              height: manifest.height,
            },
          ]
        : undefined,
    },
    twitter: {
      card: isVideo ? "player" : "summary_large_image",
      title,
      description,
      images: posterUrl ?? (isVideo ? undefined : mediaUrl),
      players: isVideo
        ? [
            {
              playerUrl: mediaUrl,
              streamUrl: mediaUrl,
              width: manifest.width ?? 1280,
              height: manifest.height ?? 720,
            },
          ]
        : undefined,
    },
  }
}

export default async function SharePage({ params, searchParams }: SharePageProps) {
  const { id } = await params
  const share = await resolveShare(id, firstValue((await searchParams).b))
  if (!share) notFound()

  return <ShareView share={share} />
}

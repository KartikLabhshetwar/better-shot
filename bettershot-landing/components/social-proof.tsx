import { GitHubIcon } from "@/components/github-icon"

const REPO = "KartikLabhshetwar/better-shot"
const AVATAR_COUNT = 8

interface GitHubUser {
  login: string
  avatar_url: string
  type: string
}

async function getContributors(): Promise<string[]> {
  try {
    const res = await fetch(
      `https://api.github.com/repos/${REPO}/contributors?per_page=${AVATAR_COUNT + 2}`,
      { next: { revalidate: 3600 }, headers: { Accept: "application/vnd.github+json" } },
    )
    if (!res.ok) return []
    const data: GitHubUser[] = await res.json()
    return data
      .filter((u) => u.type === "User")
      .slice(0, AVATAR_COUNT)
      .map((u) => `${u.avatar_url}&s=64`)
  } catch {
    return []
  }
}

async function getDownloadCount(): Promise<number> {
  try {
    const res = await fetch(
      `https://api.github.com/repos/${REPO}/releases?per_page=100`,
      { next: { revalidate: 300 }, headers: { Accept: "application/vnd.github+json" } },
    )
    if (!res.ok) return 0
    const releases: { assets: { download_count: number }[] }[] = await res.json()
    return releases.reduce(
      (sum, r) => sum + r.assets.reduce((s, a) => s + a.download_count, 0),
      0,
    )
  } catch {
    return 0
  }
}

function formatCount(n: number): string {
  if (n >= 1000) return `${(n / 1000).toFixed(1).replace(/\.0$/, "")}K`
  return String(n)
}

export async function SocialProof() {
  const [avatars, downloads] = await Promise.all([getContributors(), getDownloadCount()])
  const count = downloads > 0 ? formatCount(downloads) : "14K"

  return (
    <div className="flex flex-col items-center gap-4 sm:flex-row sm:gap-5">
      {avatars.length > 0 && (
        <div className="flex -space-x-2.5">
          {avatars.map((url, i) => (
            <img
              key={i}
              src={url}
              alt=""
              width={36}
              height={36}
              className="size-9 rounded-full border-2 border-white object-cover"
            />
          ))}
        </div>
      )}
      <div className="flex flex-col items-center gap-0.5 sm:items-start">
        <div className="flex items-center gap-2">
          <span className="text-amber-400">&#9733;&#9733;&#9733;&#9733;&#9733;</span>
          <span className="text-[14px] font-medium text-zinc-900">
            Loved by {count}+ users
          </span>
        </div>
        <span className="text-[13px] text-zinc-500">
          Open source &middot; 25 MB &middot;{" "}
          <a
            href={`https://github.com/${REPO}`}
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex items-center gap-1 text-brand transition-colors hover:text-brand-700"
          >
            <GitHubIcon className="size-3" />
            Star on GitHub
          </a>
        </span>
      </div>
    </div>
  )
}

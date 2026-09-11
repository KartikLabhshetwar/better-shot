const REPO = "KartikLabhshetwar/better-shot"
const AVATAR_COUNT = 8

interface GitHubUser {
  login: string
  avatar_url: string
  type: string
}

async function getContributors(): Promise<GitHubUser[]> {
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
  } catch {
    return []
  }
}

function formatCount(n: number): string {
  if (n >= 1000) return `${(n / 1000).toFixed(1).replace(/\.0$/, "")}K`
  return String(n)
}

export async function SocialProof({ downloads }: { downloads: number }) {
  const avatars = await getContributors()

  return (
    <div className="flex flex-col items-center gap-4 sm:flex-row sm:gap-5">
      {avatars.length > 0 && (
        <div className="flex -space-x-2.5">
          {avatars.map((user) => (
            <img
              key={user.login}
              src={`${user.avatar_url}&s=80`}
              alt={`${user.login}, BetterShot contributor`}
              width={40}
              height={40}
              className="size-10 rounded-full border-2 border-white object-cover"
            />
          ))}
        </div>
      )}
      <div className="flex flex-col items-center gap-0.5 sm:items-start">
        <div className="flex items-center gap-2">
          <span className="text-[14px] font-medium text-zinc-900">
            {downloads > 0 ? `${formatCount(downloads)}+ downloads` : "Built with our community"}
          </span>
        </div>
        <span className="text-[13px] text-zinc-500">
          Free, open source, and built together.
        </span>
      </div>
    </div>
  )
}

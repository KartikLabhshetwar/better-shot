import fs from "fs"
import path from "path"

const REPO = "KartikLabhshetwar/better-shot"

export interface ReleaseInfo {
  version: string
  appleSilicon: string
  intel: string
}

function shippedVersion(): string {
  const raw = fs.readFileSync(path.resolve(process.cwd(), "../version.json"), "utf-8")
  return JSON.parse(raw).version
}

const fallback: ReleaseInfo = {
  version: shippedVersion(),
  appleSilicon: `https://github.com/${REPO}/releases/latest`,
  intel: `https://github.com/${REPO}/releases/latest`,
}

export async function getLatestRelease(): Promise<ReleaseInfo> {
  try {
    const res = await fetch(`https://api.github.com/repos/${REPO}/releases/latest?shipped=${fallback.version}`, {
      next: { revalidate: 300 },
      headers: { Accept: "application/vnd.github+json" },
    })
    if (!res.ok) return fallback

    const data = await res.json()
    const tag = (data.tag_name ?? "").replace(/^v/, "")
    const assets: { name: string; browser_download_url: string }[] = data.assets ?? []

    const arm = assets.find(
      (a) => a.name.includes("aarch64") || a.name.includes("arm64"),
    )
    const x64 = assets.find(
      (a) => a.name.includes("x64") || a.name.includes("x86_64") || a.name.includes("intel"),
    )

    return {
      version: tag || fallback.version,
      appleSilicon: arm?.browser_download_url ?? `https://github.com/${REPO}/releases/latest`,
      intel: x64?.browser_download_url ?? `https://github.com/${REPO}/releases/latest`,
    }
  } catch {
    return fallback
  }
}

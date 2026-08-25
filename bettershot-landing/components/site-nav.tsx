import { SiteNavClient } from "@/components/site-nav-client"
import { getLatestRelease } from "@/lib/downloads"

export async function SiteNav() {
  const release = await getLatestRelease()
  return <SiteNavClient release={release} />
}

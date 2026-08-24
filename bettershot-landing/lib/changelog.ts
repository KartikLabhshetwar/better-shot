import fs from "fs"
import path from "path"

export interface ChangelogSection {
  label: string
  items: string[]
}

export interface ChangelogVersion {
  version: string
  date: string
  summary: string
  sections: ChangelogSection[]
}

export function getChangelog(): ChangelogVersion[] {
  const filePath = path.resolve(process.cwd(), "../CHANGELOG.md")
  const raw = fs.readFileSync(filePath, "utf-8")
  const lines = raw.split("\n")

  const versions: ChangelogVersion[] = []
  let currentVersion: ChangelogVersion | null = null
  let currentSection: ChangelogSection | null = null

  for (const line of lines) {
    const versionMatch = line.match(/^## \[(.+?)\]\s*-\s*(.+)$/)
    if (versionMatch) {
      if (currentSection && currentVersion) {
        currentVersion.sections.push(currentSection)
        currentSection = null
      }
      if (currentVersion) {
        versions.push(currentVersion)
      }
      currentVersion = {
        version: versionMatch[1],
        date: versionMatch[2].trim(),
        summary: "",
        sections: [],
      }
      continue
    }

    const sectionMatch = line.match(/^### (.+)$/)
    if (sectionMatch && currentVersion) {
      if (currentSection) {
        currentVersion.sections.push(currentSection)
      }
      currentSection = { label: sectionMatch[1].trim(), items: [] }
      continue
    }

    const itemMatch = line.match(/^- (.+)$/)
    if (itemMatch && currentSection) {
      currentSection.items.push(itemMatch[1].trim())
      continue
    }

    if (currentVersion && !currentSection && line.trim()) {
      currentVersion.summary = `${currentVersion.summary} ${line.trim()}`.trim()
    }
  }

  if (currentSection && currentVersion) {
    currentVersion.sections.push(currentSection)
  }
  if (currentVersion) {
    versions.push(currentVersion)
  }

  return versions
}

import fs from "fs"
import path from "path"

export interface ChangelogSection {
  label: string
  items: string[]
}

export interface ChangelogVersion {
  version: string
  date: string
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
    // Match version header: ## [0.3.7] - 2026-06-07
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
        sections: [],
      }
      continue
    }

    // Match section header: ### Added / ### Fixed / etc.
    const sectionMatch = line.match(/^### (.+)$/)
    if (sectionMatch && currentVersion) {
      if (currentSection) {
        currentVersion.sections.push(currentSection)
      }
      currentSection = { label: sectionMatch[1].trim(), items: [] }
      continue
    }

    // Match list items: - **Label**: description  or  - plain text
    const itemMatch = line.match(/^- (.+)$/)
    if (itemMatch && currentSection) {
      // Strip bold markdown (**text**) — keep label text + rest of description
      const text = itemMatch[1]
        .replace(/\*\*(.+?)\*\*:/g, "$1:") // **Foo**: bar → Foo: bar
        .replace(/\*\*(.+?)\*\*/g, "$1")    // **Foo** → Foo
        .trim()
      currentSection.items.push(text)
    }
  }

  // Flush the last section and version
  if (currentSection && currentVersion) {
    currentVersion.sections.push(currentSection)
  }
  if (currentVersion) {
    versions.push(currentVersion)
  }

  return versions
}

import { Badge } from "@/components/ui/badge"
import { Sparkles } from "lucide-react"

export default function HomeBadge() {
  return (
    <Badge
      variant="secondary"
      className="bg-rose-50 text-rose-700 border-rose-200 dark:bg-rose-950 dark:text-rose-300 dark:border-rose-800"
    >
      <Sparkles className="w-3 h-3 mr-1" />
      New UI Library
    </Badge>
  )
}

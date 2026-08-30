import { cn } from "@/lib/utils"

export function SectionLabel({ children, className }: { children: React.ReactNode; className?: string }) {
  return (
    <p
      className={cn(
        "text-[13px] font-medium uppercase tracking-widest text-zinc-400",
        className,
      )}
    >
      {children}
    </p>
  )
}

export function GradientHeading({
  children,
  className,
  as: Tag = "h2",
}: {
  children: React.ReactNode
  className?: string
  as?: "h1" | "h2"
}) {
  return <Tag className={cn("text-zinc-900", className)}>{children}</Tag>
}

export function PageHeader({
  label,
  title,
  children,
}: {
  label: string
  title: React.ReactNode
  children?: React.ReactNode
}) {
  return (
    <header className="mx-auto max-w-[1100px] px-6 pb-14 pt-28 sm:pt-32">
      <SectionLabel className="mb-5">{label}</SectionLabel>
      <GradientHeading
        as="h1"
        className="text-[42px] tracking-tight sm:text-[58px] lg:text-[68px]"
      >
        {title}
      </GradientHeading>
      {children && (
        <div className="mt-6 max-w-[640px] text-[17px] leading-[28px] text-zinc-500">{children}</div>
      )}
    </header>
  )
}

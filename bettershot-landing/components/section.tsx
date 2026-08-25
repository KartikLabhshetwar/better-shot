import { cn } from "@/lib/utils"

export function SectionLabel({ children, className }: { children: React.ReactNode; className?: string }) {
  return (
    <p
      className={cn(
        "micro text-[13px] font-extrabold uppercase text-brand-700",
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
  return <Tag className={cn("text-ink", className)}>{children}</Tag>
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
    <header className="mx-auto max-w-[1240px] px-6 pb-14 pt-28 sm:pt-32">
      <SectionLabel className="mb-5">{label}</SectionLabel>
      <GradientHeading
        as="h1"
        className="display -ml-[0.04em] text-[42px] sm:text-[58px] lg:text-[68px]"
      >
        {title}
      </GradientHeading>
      {children && (
        <div className="mt-6 max-w-[640px] text-[17px] leading-[28px] text-ink/70">{children}</div>
      )}
    </header>
  )
}

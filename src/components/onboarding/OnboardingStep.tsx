import { ReactNode } from "react";

interface OnboardingStepProps {
  title: string;
  description: string;
  icon?: ReactNode;
  children?: ReactNode;
  highlightElement?: string;
}

export function OnboardingStep({
  title,
  description,
  icon,
  children,
  highlightElement,
}: OnboardingStepProps) {
  return (
    <div className="space-y-4">
      {icon && (
        <div className="flex justify-center mb-4">
          <div className="size-16 rounded-full bg-secondary border border-border flex items-center justify-center">
            {icon}
          </div>
        </div>
      )}
      <div className="text-center space-y-2">
        <h2 className="text-2xl font-semibold text-foreground text-balance">{title}</h2>
        <p className="text-muted-foreground text-sm text-pretty max-w-md mx-auto">{description}</p>
      </div>
      {children && (
        <div className="mt-6">
          {children}
        </div>
      )}
      {highlightElement && (
        <div
          id={highlightElement}
          className="relative after:absolute after:inset-0 after:ring-2 after:ring-primary after:ring-offset-2 after:ring-offset-background after:rounded-lg"
        />
      )}
    </div>
  );
}

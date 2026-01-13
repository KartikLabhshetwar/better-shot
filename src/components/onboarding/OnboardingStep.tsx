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
          <div className="size-16 rounded-full bg-zinc-800 border border-zinc-700 flex items-center justify-center">
            {icon}
          </div>
        </div>
      )}
      <div className="text-center space-y-2">
        <h2 className="text-2xl font-semibold text-zinc-50 text-balance">{title}</h2>
        <p className="text-zinc-400 text-sm text-pretty max-w-md mx-auto">{description}</p>
      </div>
      {children && (
        <div className="mt-6">
          {children}
        </div>
      )}
      {highlightElement && (
        <div
          id={highlightElement}
          className="relative after:absolute after:inset-0 after:ring-2 after:ring-blue-500 after:ring-offset-2 after:ring-offset-zinc-950 after:rounded-lg"
        />
      )}
    </div>
  );
}

interface OnboardingProgressProps {
  currentStep: number;
  totalSteps: number;
}

export function OnboardingProgress({ currentStep, totalSteps }: OnboardingProgressProps) {
  return (
    <div className="flex items-center justify-center gap-2 mb-8">
      {Array.from({ length: totalSteps }).map((_, index) => {
        const stepNumber = index + 1;
        const isActive = stepNumber === currentStep;
        const isCompleted = stepNumber < currentStep;

        return (
          <div key={stepNumber} className="flex items-center gap-2">
            <div
              className={`
                size-8 rounded-full flex items-center justify-center text-xs font-medium transition-all
                ${
                  isActive
                    ? "bg-blue-600 text-white scale-110"
                    : isCompleted
                      ? "bg-blue-600/50 text-blue-300"
                      : "bg-secondary text-foreground0 border border-border"
                }
              `}
            >
              {isCompleted ? (
                <svg
                  className="size-4"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke="currentColor"
                  aria-hidden="true"
                >
                  <path
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    strokeWidth={2}
                    d="M5 13l4 4L19 7"
                  />
                </svg>
              ) : (
                stepNumber
              )}
            </div>
            {index < totalSteps - 1 && (
              <div
                className={`h-0.5 w-8 transition-colors ${
                  isCompleted ? "bg-blue-600" : "bg-secondary"
                }`}
              />
            )}
          </div>
        );
      })}
    </div>
  );
}

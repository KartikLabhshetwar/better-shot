import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { OnboardingStep } from "./OnboardingStep";
import { OnboardingProgress } from "./OnboardingProgress";
import { markOnboardingComplete } from "@/lib/onboarding";

interface OnboardingFlowProps {
  onComplete: () => void;
}

const ONBOARDING_STEPS = [
  {
    id: "welcome",
    title: "Welcome to Better Shot",
    description:
      "Your open-source alternative to CleanShot X. Let's get you started with a quick tour of the app.",
    icon: (
      <svg className="size-8 text-blue-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path
          strokeLinecap="round"
          strokeLinejoin="round"
          strokeWidth={1.5}
          d="M9.813 15.904L9 18.75l-.813-2.846a4.5 4.5 0 00-3.09-3.09L2.25 12l2.846-.813a4.5 4.5 0 003.09-3.09L9 5.25l.813 2.846a4.5 4.5 0 003.09 3.09L15.75 12l-2.846.813a4.5 4.5 0 00-3.09 3.09zM18.259 8.715L18 9.75l-.259-1.035a3.375 3.375 0 00-2.455-2.456L14.25 6l1.036-.259a3.375 3.375 0 002.455-2.456L18 2.25l.259 1.035a3.375 3.375 0 002.456 2.456L21.75 6l-1.035.259a3.375 3.375 0 00-2.456 2.456zM16.894 20.567L16.5 21.75l-.394-1.183a2.25 2.25 0 00-1.423-1.423L13.5 18.75l1.183-.394a2.25 2.25 0 001.423-1.423l.394-1.183.394 1.183a2.25 2.25 0 001.423 1.423l1.183.394-1.183.394a2.25 2.25 0 00-1.423 1.423z"
        />
      </svg>
    ),
  },
  {
    id: "capture-modes",
    title: "Capture Modes",
    description: "Better Shot offers three ways to capture your screen, each with a handy keyboard shortcut.",
    icon: (
      <svg className="size-8 text-blue-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path
          strokeLinecap="round"
          strokeLinejoin="round"
          strokeWidth={1.5}
          d="M6.827 6.175A2.31 2.31 0 015.186 7.23c-.38.054-.757.112-1.134.175C2.999 7.58 2.25 8.507 2.25 9.574V18a2.25 2.25 0 002.25 2.25h15A2.25 2.25 0 0021.75 18V9.574c0-1.067-.75-1.994-1.802-2.169a47.865 47.865 0 00-1.134-.175 2.31 2.31 0 01-1.64-1.055l-.822-1.316a2.192 2.192 0 00-1.736-1.039 48.774 48.774 0 00-5.232 0 2.192 2.192 0 00-1.736 1.039l-.821 1.316z"
        />
        <path
          strokeLinecap="round"
          strokeLinejoin="round"
          strokeWidth={1.5}
          d="M16.5 12.75a4.5 4.5 0 11-9 0 4.5 4.5 0 019 0zm-4.5-2.25a.75.75 0 00-.75.75v2.25a.75.75 0 001.5 0v-2.25a.75.75 0 00-.75-.75z"
        />
      </svg>
    ),
    content: (
      <div className="space-y-6">
        <div className="grid grid-cols-3 gap-3">
          <div className="p-4 bg-secondary rounded-lg border border-border">
            <div className="flex flex-col items-center gap-2">
              <svg className="size-6 text-blue-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth={1.5}
                  d="M4 5a1 1 0 011-1h4a1 1 0 010 2H6v3a1 1 0 01-2 0V5zM4 19a1 1 0 001 1h4a1 1 0 100-2H6v-3a1 1 0 10-2 0v4zM20 5a1 1 0 00-1-1h-4a1 1 0 100 2h3v3a1 1 0 102 0V5zM20 19a1 1 0 01-1 1h-4a1 1 0 110-2h3v-3a1 1 0 112 0v4z"
                />
              </svg>
              <div className="text-center">
                <div className="text-sm font-medium text-foreground">Region</div>
                <div className="text-xs text-foreground0 mt-1">Select area · ⌘⇧2</div>
              </div>
            </div>
          </div>
          <div className="p-4 bg-secondary rounded-lg border border-border">
            <div className="flex flex-col items-center gap-2">
              <svg className="size-6 text-blue-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth={1.5}
                  d="M9.75 17L9 20l-1 1h8l-1-1-.75-3M3 13h18M5 17h14a2 2 0 002-2V5a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z"
                />
              </svg>
              <div className="text-center">
                <div className="text-sm font-medium text-foreground">Fullscreen</div>
                <div className="text-xs text-foreground0 mt-1">Entire screen · ⌘⇧F</div>
              </div>
            </div>
          </div>
          <div className="p-4 bg-secondary rounded-lg border border-border">
            <div className="flex flex-col items-center gap-2">
              <svg className="size-6 text-blue-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth={1.5}
                  d="M4 5a2 2 0 012-2h12a2 2 0 012 2v14a2 2 0 01-2 2H6a2 2 0 01-2-2V5z"
                />
                <path
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth={1.5}
                  d="M8 3v2M12 3v2M16 3v2"
                />
              </svg>
              <div className="text-center">
                <div className="text-sm font-medium text-foreground">Window</div>
                <div className="text-xs text-foreground0 mt-1">Single window · ⌘⇧D</div>
              </div>
            </div>
          </div>
        </div>
        <div className="space-y-3">
          <div className="flex items-center justify-between p-3 bg-secondary rounded-lg border border-border">
            <span className="text-sm text-foreground">Capture Region</span>
            <kbd className="px-3 py-1 bg-card border border-border rounded text-foreground font-mono text-xs tabular-nums">
              ⌘⇧2
            </kbd>
          </div>
          <div className="flex items-center justify-between p-3 bg-secondary rounded-lg border border-border">
            <span className="text-sm text-foreground">Capture Fullscreen</span>
            <kbd className="px-3 py-1 bg-card border border-border rounded text-foreground font-mono text-xs tabular-nums">
              ⌘⇧F
            </kbd>
          </div>
          <div className="flex items-center justify-between p-3 bg-secondary rounded-lg border border-border">
            <span className="text-sm text-foreground">Capture Window</span>
            <kbd className="px-3 py-1 bg-card border border-border rounded text-foreground font-mono text-xs tabular-nums">
              ⌘⇧D
            </kbd>
          </div>
          <p className="text-xs text-foreground0 text-center pt-2">
            Customize these shortcuts anytime in Preferences
          </p>
        </div>
      </div>
    ),
  },
  {
    id: "settings",
    title: "Settings & Preferences",
    description: "Fine-tune how captures behave. Access these options anytime from the gear icon.",
    icon: (
      <svg className="size-8 text-blue-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path
          strokeLinecap="round"
          strokeLinejoin="round"
          strokeWidth={1.5}
          d="M9.594 3.94c.09-.542.56-.94 1.11-.94h2.593c.55 0 1.02.398 1.11.94l.213 1.281c.063.374.313.686.645.87.074.04.147.083.22.127.324.196.72.257 1.075.124l1.217-.456a1.125 1.125 0 011.37.49l1.296 2.247a1.125 1.125 0 01-.26 1.431l-1.003.827c-.293.24-.438.613-.431.992a6.759 6.759 0 010 .255c-.007.378.138.75.43.99l1.005.828c.424.35.534.954.26 1.43l-1.298 2.247a1.125 1.125 0 01-1.369.491l-1.217-.456c-.355-.133-.75-.072-1.076.124a6.57 6.57 0 01-.22.128c-.331.183-.581.495-.644.87l-.213 1.28c-.09.543-.56.941-1.11.941h-2.594c-.55 0-1.02-.398-1.11-.94l-.213-1.281c-.062-.374-.312-.686-.644-.87a6.52 6.52 0 01-.22-.127c-.325-.196-.72-.257-1.076-.124l-1.217.456a1.125 1.125 0 01-1.369-.49l-1.297-2.247a1.125 1.125 0 01.26-1.431l1.004-.827c.292-.24.437-.613.43-.992a6.932 6.932 0 010-.255c.007-.378-.138-.75-.43-.99l-1.004-.828a1.125 1.125 0 01-.26-1.43l1.297-2.247a1.125 1.125 0 011.37-.491l1.216.456c.356.133.751.072 1.076-.124.072-.044.146-.087.22-.128.332-.183.582-.495.644-.87l.214-1.281z"
        />
        <path
          strokeLinecap="round"
          strokeLinejoin="round"
          strokeWidth={1.5}
          d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"
        />
      </svg>
    ),
    content: (
      <div className="space-y-4">
        <div className="p-4 bg-secondary rounded-lg border border-border">
          <div className="text-sm font-medium text-foreground mb-1">Auto-apply background</div>
          <p className="text-xs text-muted-foreground text-pretty">
            Instantly apply your default background and save, without opening the editor.
          </p>
        </div>
        <div className="p-4 bg-secondary rounded-lg border border-border">
          <div className="text-sm font-medium text-foreground mb-1">Default background</div>
          <p className="text-xs text-muted-foreground text-pretty">
            Choose the image Better Shot uses for auto-apply and as the starting point in the editor.
          </p>
        </div>
        <div className="p-4 bg-secondary rounded-lg border border-border">
          <div className="text-sm font-medium text-foreground mb-1">Save location</div>
          <p className="text-xs text-muted-foreground text-pretty">
            Pick where screenshots are saved. Desktop is the default.
          </p>
        </div>
        <div className="p-4 bg-secondary rounded-lg border border-border">
          <div className="text-sm font-medium text-foreground mb-1">Copy to clipboard</div>
          <p className="text-xs text-muted-foreground text-pretty">
            Automatically copy saved screenshots so they are ready to paste.
          </p>
        </div>
      </div>
    ),
  },
  {
    id: "permissions",
    title: "Screen Recording Permission",
    description:
      "Better Shot needs Screen Recording permission from macOS before it can capture your screen.",
    icon: (
      <svg className="size-8 text-amber-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path
          strokeLinecap="round"
          strokeLinejoin="round"
          strokeWidth={1.5}
          d="M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126zM12 15.75h.007v.008H12v-.008z"
        />
      </svg>
    ),
    content: (
      <div className="space-y-4">
        <div className="p-4 bg-amber-950/20 border border-amber-800/50 rounded-lg">
          <div className="flex items-start gap-3">
            <svg
              className="size-5 text-amber-500 mt-0.5 shrink-0"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2}
                d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
              />
            </svg>
            <div className="flex-1 space-y-1">
              <div className="text-sm font-medium text-amber-200">Required by macOS</div>
              <ul className="text-xs text-amber-300/80 space-y-1 text-pretty list-disc list-inside">
                <li>macOS will ask for Screen Recording the first time you capture.</li>
                <li>Better Shot cannot capture anything until this is granted.</li>
              </ul>
            </div>
          </div>
        </div>
        <div className="space-y-3">
          <div className="p-4 bg-secondary rounded-lg border border-border">
            <div className="text-sm font-medium text-foreground mb-2">How to Grant Permission</div>
            <ol className="text-xs text-muted-foreground space-y-1 list-decimal list-inside text-pretty">
              <li>Click “Open System Settings” in the macOS prompt.</li>
              <li>Go to Privacy &amp; Security → Screen Recording.</li>
              <li>Toggle on <span className="text-foreground font-mono">bettershot</span> in the list.</li>
              <li>Restart Better Shot so the change takes effect.</li>
            </ol>
          </div>
          <div className="p-4 bg-secondary rounded-lg border border-border">
            <div className="text-sm font-medium text-foreground mb-2">What You'll See</div>
            <p className="text-xs text-muted-foreground text-pretty">
              macOS shows a dialog like{" "}
              <span className="text-foreground font-mono">
                "bettershot" would like to record this computer&apos;s screen and audio.
              </span>{" "}
              Click “Open System Settings” to grant access.
            </p>
          </div>
        </div>
      </div>
    ),
  },
  {
    id: "ready",
    title: "You're All Set!",
    description: "Start capturing screenshots and editing them with beautiful backgrounds and effects.",
    icon: (
      <svg className="size-8 text-green-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path
          strokeLinecap="round"
          strokeLinejoin="round"
          strokeWidth={1.5}
          d="M9 12.75L11.25 15 15 9.75M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
        />
      </svg>
    ),
    content: (
      <div className="space-y-4 text-center">
        <p className="text-sm text-muted-foreground text-pretty">
          Press <kbd className="px-2 py-1 bg-secondary border border-border rounded text-foreground font-mono text-xs tabular-nums">⌘⇧2</kbd> to capture a region, or use the buttons on the main screen.
        </p>
        <div className="p-4 bg-secondary/50 rounded-lg border border-border/50">
          <p className="text-xs text-foreground0 text-pretty">
            <span className="text-muted-foreground font-medium">Pro tip:</span> Enable "Auto-apply background" on the main screen for instant captures with your default background - no editing required.
          </p>
        </div>
      </div>
    ),
  },
];

export function OnboardingFlow({ onComplete }: OnboardingFlowProps) {
  const [currentStep, setCurrentStep] = useState(0);

  const handleNext = () => {
    if (currentStep < ONBOARDING_STEPS.length - 1) {
      setCurrentStep(currentStep + 1);
    } else {
      markOnboardingComplete();
      onComplete();
    }
  };

  const handlePrevious = () => {
    if (currentStep > 0) {
      setCurrentStep(currentStep - 1);
    }
  };

  const handleSkip = () => {
    markOnboardingComplete();
    onComplete();
  };

  const step = ONBOARDING_STEPS[currentStep];
  const isFirstStep = currentStep === 0;
  const isLastStep = currentStep === ONBOARDING_STEPS.length - 1;

  return (
    <div className="fixed inset-0 z-50 bg-background/95 backdrop-blur-sm flex items-center justify-center p-8">
      <div className="w-full max-w-2xl">
        <OnboardingProgress currentStep={currentStep + 1} totalSteps={ONBOARDING_STEPS.length} />
        <Card className="bg-card border-border">
          <CardContent className="p-8">
            <OnboardingStep
              title={step.title}
              description={step.description}
              icon={step.icon}
            >
              {step.content}
            </OnboardingStep>
            <div className="flex items-center justify-between mt-8 pt-6 border-t border-border">
              <div>
                {!isFirstStep && (
                  <Button
                    variant="outline"
                    onClick={handlePrevious}
                    className="border-border text-foreground hover:bg-secondary"
                  >
                    Previous
                  </Button>
                )}
              </div>
              <div className="flex items-center gap-3">
                <Button
                  onClick={handleSkip}
                  className="text-muted-foreground hover:text-foreground"
                >
                  Skip
                </Button>
                <Button
                  onClick={handleNext}
                  variant="cta"
                  size="lg"
                >
                  {isLastStep ? "Get Started" : "Next"}
                </Button>
              </div>
            </div>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}

import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Download, RefreshCw, Check, X } from "lucide-react";
import { useEffect, useState } from "react";
import { motion, AnimatePresence } from "motion/react";

type UpdateState = "available" | "downloading" | "installing" | "ready" | "error";

interface UpdateDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  version: string;
  releaseNotes?: string;
  onUpdate: (onProgress: (progress: number) => void) => Promise<void>;
  onSkip: () => void;
}

export function UpdateDialog({
  open,
  onOpenChange,
  version,
  releaseNotes,
  onUpdate,
  onSkip,
}: UpdateDialogProps) {
  const [state, setState] = useState<UpdateState>("available");
  const [progress, setProgress] = useState(0);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!open) {
      setState("available");
      setProgress(0);
      setError(null);
    }
  }, [open]);

  const handleUpdate = async () => {
    try {
      setState("downloading");
      setProgress(0);
      setError(null);

      const progressCallback = (progressValue: number) => {
        setProgress(progressValue);
        if (progressValue >= 100) {
          setState("installing");
        }
      };

      await onUpdate(progressCallback);
      setState("ready");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Update failed");
      setState("error");
    }
  };

  const handleSkip = () => {
    onSkip();
    onOpenChange(false);
  };

  const isLoading = state === "downloading" || state === "installing";

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent
        className="sm:max-w-sm"
        onInteractOutside={(e) => e.preventDefault()}
      >
        <DialogHeader>
          <DialogTitle>Update Available</DialogTitle>
          <DialogDescription>
            Version {version} is ready to install
          </DialogDescription>
        </DialogHeader>

        <AnimatePresence mode="wait">
          {state === "available" && (
            <motion.div
              key="available"
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              transition={{ duration: 0.15 }}
              className="space-y-3"
            >
              {releaseNotes && (
                <p className="text-sm text-muted-foreground text-pretty">
                  {releaseNotes}
                </p>
              )}
            </motion.div>
          )}

          {isLoading && (
            <motion.div
              key="loading"
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              transition={{ duration: 0.15 }}
              className="space-y-3"
            >
              <div className="space-y-2">
                <div className="flex items-center justify-between text-sm">
                  <span className="text-muted-foreground">
                    {state === "downloading" ? "Downloading..." : "Installing..."}
                  </span>
                  {state === "downloading" && (
                    <span className="text-foreground0 tabular-nums">{progress}%</span>
                  )}
                </div>
                <div className="h-1 w-full overflow-hidden rounded-full bg-secondary">
                  <motion.div
                    className="h-full bg-muted-foreground"
                    initial={{ width: "0%" }}
                    animate={{
                      width: state === "installing" ? "100%" : `${progress}%`,
                    }}
                    transition={{ duration: 0.2, ease: "easeOut" }}
                  />
                </div>
              </div>
            </motion.div>
          )}

          {state === "ready" && (
            <motion.div
              key="ready"
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              transition={{ duration: 0.15 }}
              className="flex items-center gap-3 rounded-lg bg-secondary/50 p-3"
            >
              <div className="flex size-8 shrink-0 items-center justify-center rounded-full bg-muted">
                <Check className="size-4 text-foreground" />
              </div>
              <p className="text-sm text-foreground text-pretty">
                Update installed. The app will restart now.
              </p>
            </motion.div>
          )}

          {state === "error" && (
            <motion.div
              key="error"
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              transition={{ duration: 0.15 }}
              className="flex items-center gap-3 rounded-lg bg-red-950/30 p-3"
            >
              <div className="flex size-8 shrink-0 items-center justify-center rounded-full bg-red-900/50">
                <X className="size-4 text-red-400" />
              </div>
              <p className="text-sm text-red-400 text-pretty">
                {error || "Update failed. Please try again."}
              </p>
            </motion.div>
          )}
        </AnimatePresence>

        <DialogFooter>
          {state === "available" && (
            <>
              <Button variant="ghost" onClick={handleSkip}>
                Later
              </Button>
              <Button variant="cta" size="lg" onClick={handleUpdate}>
                <Download className="mr-2 size-4" />
                Update
              </Button>
            </>
          )}
          {isLoading && (
            <Button disabled className="w-full">
              <RefreshCw className="mr-2 size-4 animate-spin" />
              {state === "downloading" ? "Downloading..." : "Installing..."}
            </Button>
          )}
          {state === "error" && (
            <>
              <Button variant="ghost" onClick={handleSkip}>
                Close
              </Button>
              <Button variant="cta" size="lg" onClick={handleUpdate}>Try Again</Button>
            </>
          )}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

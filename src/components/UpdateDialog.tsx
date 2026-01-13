import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Download, Sparkles } from "lucide-react";
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

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md" onInteractOutside={(e) => e.preventDefault()}>
        <DialogHeader>
          <div className="flex items-center gap-3">
            <div className="flex size-10 items-center justify-center rounded-full bg-zinc-800">
              <Sparkles className="size-5 text-zinc-300" />
            </div>
            <div>
              <DialogTitle className="text-xl">Update Available</DialogTitle>
              <DialogDescription className="mt-1">
                Version {version} is ready to install
              </DialogDescription>
            </div>
          </div>
        </DialogHeader>

        <AnimatePresence mode="wait">
          {state === "available" && (
            <motion.div
              key="available"
              initial={{ opacity: 0, y: 10 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -10 }}
              transition={{ duration: 0.2 }}
            >
              {releaseNotes && (
                <div className="my-4 rounded-lg border border-zinc-800 bg-zinc-950/50 p-4">
                  <p className="text-sm text-zinc-300 text-pretty">{releaseNotes}</p>
                </div>
              )}
              <p className="text-sm text-zinc-400 text-pretty">
                Would you like to update now? The app will restart after installation.
              </p>
            </motion.div>
          )}

          {state === "downloading" && (
            <motion.div
              key="downloading"
              initial={{ opacity: 0, y: 10 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -10 }}
              transition={{ duration: 0.2 }}
              className="space-y-4"
            >
              <div className="space-y-2">
                <div className="flex items-center justify-between text-sm">
                  <span className="text-zinc-300">Downloading update...</span>
                  <span className="text-zinc-400 tabular-nums">{progress}%</span>
                </div>
                <div className="h-2 w-full overflow-hidden rounded-full bg-zinc-800">
                  <motion.div
                    className="h-full bg-zinc-300"
                    initial={{ width: "0%" }}
                    animate={{ width: `${progress}%` }}
                    transition={{ duration: 0.2, ease: "easeOut" }}
                  />
                </div>
              </div>
              <p className="text-sm text-zinc-400 text-pretty">
                Please wait while we download the update...
              </p>
            </motion.div>
          )}

          {state === "installing" && (
            <motion.div
              key="installing"
              initial={{ opacity: 0, y: 10 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -10 }}
              transition={{ duration: 0.2 }}
              className="space-y-4"
            >
              <div className="flex items-center justify-center py-4">
                <motion.div
                  animate={{ rotate: 360 }}
                  transition={{ duration: 1, repeat: Infinity, ease: "linear" }}
                  className="size-8 rounded-full border-2 border-zinc-300 border-t-transparent"
                />
              </div>
              <p className="text-center text-sm text-zinc-400 text-pretty">
                Installing update...
              </p>
            </motion.div>
          )}

          {state === "ready" && (
            <motion.div
              key="ready"
              initial={{ opacity: 0, scale: 0.95 }}
              animate={{ opacity: 1, scale: 1 }}
              exit={{ opacity: 0, scale: 0.95 }}
              transition={{ duration: 0.2 }}
              className="space-y-4"
            >
              <div className="flex flex-col items-center justify-center py-4">
                <motion.div
                  initial={{ scale: 0 }}
                  animate={{ scale: 1 }}
                  transition={{ type: "spring", duration: 0.5 }}
                  className="mb-4 flex size-16 items-center justify-center rounded-full bg-zinc-800"
                >
                  <motion.div
                    initial={{ scale: 0 }}
                    animate={{ scale: 1 }}
                    transition={{ delay: 0.2, type: "spring", duration: 0.5 }}
                  >
                    <Sparkles className="size-8 text-zinc-300" />
                  </motion.div>
                </motion.div>
                <p className="text-center text-base font-medium text-zinc-50">
                  Update Ready!
                </p>
                <p className="mt-2 text-center text-sm text-zinc-400 text-pretty">
                  The update has been installed. The app will restart now.
                </p>
              </div>
            </motion.div>
          )}

          {state === "error" && (
            <motion.div
              key="error"
              initial={{ opacity: 0, y: 10 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -10 }}
              transition={{ duration: 0.2 }}
              className="space-y-4"
            >
              <div className="rounded-lg border border-red-800/50 bg-red-950/30 p-4">
                <p className="text-sm font-medium text-red-300">Update Failed</p>
                <p className="mt-1 text-sm text-red-400 text-pretty">
                  {error || "An error occurred while updating. Please try again later."}
                </p>
              </div>
            </motion.div>
          )}
        </AnimatePresence>

        <DialogFooter>
          {state === "available" && (
            <>
              <Button
                variant="outline"
                onClick={handleSkip}
                className="border-zinc-800 bg-zinc-900 text-zinc-300 hover:bg-zinc-800"
              >
                Later
              </Button>
              <Button
                onClick={handleUpdate}
                className="bg-zinc-300 text-zinc-950 hover:bg-zinc-200"
              >
                <Download className="mr-2 size-4" />
                Update Now
              </Button>
            </>
          )}
          {state === "error" && (
            <>
              <Button
                variant="outline"
                onClick={handleSkip}
                className="border-zinc-800 bg-zinc-900 text-zinc-300 hover:bg-zinc-800"
              >
                Close
              </Button>
              <Button
                onClick={handleUpdate}
                className="bg-zinc-300 text-zinc-950 hover:bg-zinc-200"
              >
                Try Again
              </Button>
            </>
          )}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { FileText, Copy, Check } from "lucide-react";
import { useState, useEffect } from "react";
import { motion, AnimatePresence } from "motion/react";

interface OcrResultDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  text: string;
  onCopy: (text: string) => void;
}

export function OcrResultDialog({
  open,
  onOpenChange,
  text,
  onCopy,
}: OcrResultDialogProps) {
  const [copied, setCopied] = useState(false);
  const [editedText, setEditedText] = useState(text);

  // Sync editedText when text prop changes (new OCR result)
  useEffect(() => {
    setEditedText(text);
  }, [text]);

  const handleCopy = () => {
    onCopy(editedText);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  const handleClose = () => {
    onOpenChange(false);
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-lg" onInteractOutside={(e) => e.preventDefault()}>
        <DialogHeader>
          <div className="flex items-center gap-3">
            <div className="flex size-10 items-center justify-center rounded-full bg-zinc-800">
              <FileText className="size-5 text-zinc-300" />
            </div>
            <div>
              <DialogTitle className="text-xl">OCR Result</DialogTitle>
              <DialogDescription className="mt-1">
                Text extracted and copied to clipboard
              </DialogDescription>
            </div>
          </div>
        </DialogHeader>

        <AnimatePresence mode="wait">
          <motion.div
            key="content"
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -10 }}
            transition={{ duration: 0.2 }}
          >
            {text ? (
              <textarea
                value={editedText}
                onChange={(e) => setEditedText(e.target.value)}
                className="my-4 w-full h-64 rounded-lg border border-zinc-800 bg-zinc-950/50 p-4 font-mono text-sm text-zinc-300 resize-none focus:outline-none focus:ring-1 focus:ring-zinc-700"
                spellCheck={false}
              />
            ) : (
              <div className="my-4 rounded-lg border border-zinc-800 bg-zinc-950/50 p-4">
                <p className="text-center text-sm text-zinc-400">
                  No text was found in the selected area.
                </p>
              </div>
            )}
          </motion.div>
        </AnimatePresence>

        <DialogFooter>
          <Button
            variant="outline"
            onClick={handleClose}
            className="border-zinc-800 bg-zinc-900 text-zinc-300 hover:bg-zinc-800"
          >
            Close
          </Button>
          {text && (
            <Button
              onClick={handleCopy}
              className="bg-zinc-300 text-zinc-950 hover:bg-zinc-200"
            >
              {copied ? (
                <>
                  <Check className="mr-2 size-4" />
                  Copied!
                </>
              ) : (
                <>
                  <Copy className="mr-2 size-4" />
                  Copy Text
                </>
              )}
            </Button>
          )}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

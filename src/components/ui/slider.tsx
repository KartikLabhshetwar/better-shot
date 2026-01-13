import * as React from "react";
import { cn } from "@/lib/utils";

export interface SliderProps
  extends Omit<React.InputHTMLAttributes<HTMLInputElement>, "value" | "onChange"> {
  value?: number[];
  /** Called on every change during drag - use for visual feedback */
  onValueChange?: (value: number[]) => void;
  /** Called when interaction ends (mouseup/touchend) - use for committing to state/history */
  onValueCommit?: (value: number[]) => void;
}

const Slider = React.forwardRef<HTMLInputElement, SliderProps>(
  ({ className, value = [0], onValueChange, onValueCommit, min = 0, max = 100, step = 1, ...props }, ref) => {
    // Track the value during drag for commit
    const valueRef = React.useRef(value[0]);
    const isDraggingRef = React.useRef(false);
    
    const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
      const newValue = Number(e.target.value);
      valueRef.current = newValue;
      onValueChange?.([newValue]);
    };

    const handlePointerDown = () => {
      isDraggingRef.current = true;
    };

    const handlePointerUp = () => {
      if (isDraggingRef.current) {
        isDraggingRef.current = false;
        onValueCommit?.([valueRef.current]);
      }
    };

    // Handle keyboard changes - commit immediately
    const handleKeyUp = (e: React.KeyboardEvent<HTMLInputElement>) => {
      if (["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown", "Home", "End"].includes(e.key)) {
        onValueCommit?.([valueRef.current]);
      }
    };

    // Update ref when controlled value changes
    React.useEffect(() => {
      valueRef.current = value[0] ?? 0;
    }, [value]);

    const minNum = Number(min);
    const maxNum = Number(max);
    const valueNum = Number(value[0] ?? 0);
    const percentage = ((valueNum - minNum) / (maxNum - minNum)) * 100;

    return (
      <div className="relative w-full">
        <input
          type="range"
          className={cn(
            "w-full h-1.5 bg-zinc-700 rounded-full appearance-none cursor-pointer",
            "[&::-webkit-slider-thumb]:appearance-none [&::-webkit-slider-thumb]:w-4 [&::-webkit-slider-thumb]:h-4 [&::-webkit-slider-thumb]:rounded-full [&::-webkit-slider-thumb]:bg-white [&::-webkit-slider-thumb]:cursor-pointer [&::-webkit-slider-thumb]:shadow-sm [&::-webkit-slider-thumb]:border-0",
            "[&::-moz-range-thumb]:w-4 [&::-moz-range-thumb]:h-4 [&::-moz-range-thumb]:rounded-full [&::-moz-range-thumb]:bg-white [&::-moz-range-thumb]:cursor-pointer [&::-moz-range-thumb]:shadow-sm [&::-moz-range-thumb]:border-0",
            className
          )}
          style={{
            background: `linear-gradient(to right, rgb(59 130 246) 0%, rgb(59 130 246) ${percentage}%, rgb(63 63 70) ${percentage}%, rgb(63 63 70) 100%)`,
          }}
          ref={ref}
          value={valueNum}
          onChange={handleChange}
          onPointerDown={handlePointerDown}
          onPointerUp={handlePointerUp}
          onPointerLeave={handlePointerUp}
          onKeyUp={handleKeyUp}
          min={minNum}
          max={maxNum}
          step={step}
          {...props}
        />
      </div>
    );
  }
);
Slider.displayName = "Slider";

export { Slider };

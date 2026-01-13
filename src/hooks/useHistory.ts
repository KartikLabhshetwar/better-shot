import { useState, useCallback, useRef } from "react";

export interface HistoryState<T> {
  current: T;
  canUndo: boolean;
  canRedo: boolean;
}

export interface HistoryActions<T> {
  set: (value: T) => void;
  undo: () => void;
  redo: () => void;
  reset: (value: T) => void;
}

const MAX_HISTORY_SIZE = 50;

export function useHistory<T>(initialValue: T): [HistoryState<T>, HistoryActions<T>] {
  const [current, setCurrent] = useState<T>(initialValue);
  const pastRef = useRef<T[]>([]);
  const futureRef = useRef<T[]>([]);
  
  // Force re-render when history changes
  const [, forceUpdate] = useState(0);

  const set = useCallback((value: T) => {
    setCurrent((prev) => {
      // Add current state to past
      pastRef.current = [...pastRef.current, prev].slice(-MAX_HISTORY_SIZE);
      // Clear future when new action is taken
      futureRef.current = [];
      forceUpdate((n) => n + 1);
      return value;
    });
  }, []);

  const undo = useCallback(() => {
    if (pastRef.current.length === 0) return;
    
    setCurrent((prev) => {
      const previous = pastRef.current[pastRef.current.length - 1];
      pastRef.current = pastRef.current.slice(0, -1);
      futureRef.current = [prev, ...futureRef.current].slice(0, MAX_HISTORY_SIZE);
      forceUpdate((n) => n + 1);
      return previous;
    });
  }, []);

  const redo = useCallback(() => {
    if (futureRef.current.length === 0) return;
    
    setCurrent((prev) => {
      const next = futureRef.current[0];
      futureRef.current = futureRef.current.slice(1);
      pastRef.current = [...pastRef.current, prev].slice(-MAX_HISTORY_SIZE);
      forceUpdate((n) => n + 1);
      return next;
    });
  }, []);

  const reset = useCallback((value: T) => {
    pastRef.current = [];
    futureRef.current = [];
    setCurrent(value);
    forceUpdate((n) => n + 1);
  }, []);

  const state: HistoryState<T> = {
    current,
    canUndo: pastRef.current.length > 0,
    canRedo: futureRef.current.length > 0,
  };

  const actions: HistoryActions<T> = {
    set,
    undo,
    redo,
    reset,
  };

  return [state, actions];
}

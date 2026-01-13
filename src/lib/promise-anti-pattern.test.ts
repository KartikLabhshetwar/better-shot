import { describe, it, expect } from "vitest";

/**
 * This test file demonstrates the "async executor" Promise anti-pattern
 * and why it should be avoided.
 *
 * Anti-pattern: new Promise(async (resolve, reject) => { ... })
 * Correct pattern: async function that uses await directly
 */

// Simulated async operation
function simulateAsyncOperation(shouldFail: boolean): Promise<string> {
  return new Promise((resolve, reject) => {
    setTimeout(() => {
      if (shouldFail) {
        reject(new Error("Simulated failure"));
      } else {
        resolve("success");
      }
    }, 10);
  });
}

// Simulated sync validation that may throw
function validateInput(input: string): void {
  if (!input || input.length === 0) {
    throw new Error("Input cannot be empty");
  }
  if (input === "invalid") {
    throw new Error("Invalid input provided");
  }
}

/**
 * OLD IMPLEMENTATION (Anti-pattern)
 * Uses `new Promise(async (resolve, reject) => { ... })`
 *
 * Problems:
 * 1. Errors thrown before first await don't reject the promise
 * 2. The error becomes an unhandled rejection
 * 3. The promise hangs forever (never resolves or rejects)
 */
function processWithAntiPattern(input: string): Promise<string> {
  return new Promise(async (resolve, reject) => {
    // This throws BEFORE any await - causes unhandled rejection!
    validateInput(input);

    try {
      const result = await simulateAsyncOperation(false);
      resolve(`Processed: ${result}`);
    } catch (err) {
      reject(err);
    }
  });
}

/**
 * NEW IMPLEMENTATION (Correct pattern)
 * Uses async/await directly without wrapping in new Promise()
 *
 * Benefits:
 * 1. All errors (sync and async) are properly caught
 * 2. Cleaner, more readable code
 * 3. Proper error propagation through the promise chain
 */
async function processWithCorrectPattern(input: string): Promise<string> {
  // This throws and properly rejects the returned promise
  validateInput(input);

  const result = await simulateAsyncOperation(false);
  return `Processed: ${result}`;
}

describe("Promise Anti-Pattern Demonstration", () => {
  describe("Tests that pass for BOTH implementations (basic functionality)", () => {
    it("should resolve successfully with valid input (anti-pattern)", async () => {
      const result = await processWithAntiPattern("valid input");
      expect(result).toBe("Processed: success");
    });

    it("should resolve successfully with valid input (correct pattern)", async () => {
      const result = await processWithCorrectPattern("valid input");
      expect(result).toBe("Processed: success");
    });

    it("both handle async errors properly", async () => {
      // Both implementations properly reject async errors that happen AFTER await
      // For this test, we'll create versions that can trigger async failures

      const asyncFailAntiPattern = (): Promise<string> => {
        return new Promise(async (resolve, reject) => {
          try {
            const result = await simulateAsyncOperation(true); // This will fail
            resolve(`Processed: ${result}`);
          } catch (err) {
            reject(err);
          }
        });
      };

      const asyncFailCorrectPattern = async (): Promise<string> => {
        const result = await simulateAsyncOperation(true); // This will fail
        return `Processed: ${result}`;
      };

      await expect(asyncFailAntiPattern()).rejects.toThrow("Simulated failure");
      await expect(asyncFailCorrectPattern()).rejects.toThrow("Simulated failure");
    });
  });

  describe("Tests that EXPOSE the anti-pattern bug (correct pattern passes, anti-pattern causes issues)", () => {
    it("correct pattern: sync error properly rejects the promise", async () => {
      // With the correct pattern, the synchronous throw properly rejects
      // the promise, allowing us to catch and handle the error
      await expect(processWithCorrectPattern("")).rejects.toThrow(
        "Input cannot be empty"
      );
    });

    it("correct pattern: handles validation errors with try/catch", async () => {
      let caughtError: Error | null = null;

      try {
        await processWithCorrectPattern("invalid");
      } catch (err) {
        caughtError = err as Error;
      }

      expect(caughtError).not.toBeNull();
      expect(caughtError?.message).toBe("Invalid input provided");
    });

    it("anti-pattern: sync error causes promise to hang (never settles)", async () => {
      // With the anti-pattern, the synchronous throw BEFORE the first await
      // does NOT reject the promise - it throws an unhandled exception instead.
      //
      // The promise will NEVER settle (neither resolves nor rejects).
      // We demonstrate this by racing against a timeout.

      const promise = processWithAntiPattern("");

      const result = await Promise.race([
        promise.then(
          () => "resolved",
          () => "rejected"
        ),
        new Promise<string>((resolve) =>
          setTimeout(() => resolve("timeout"), 50)
        ),
      ]);

      // The anti-pattern promise hangs, so the timeout wins
      expect(result).toBe("timeout");

      // Note: This test also causes an unhandled rejection which Vitest reports.
      // That unhandled rejection IS the bug we're demonstrating.
    });

    it("anti-pattern: cannot use .catch() to handle sync errors", async () => {
      // With the correct pattern, you can chain .catch() to handle errors
      // With the anti-pattern, .catch() never gets called for sync errors

      let antiPatternCatchCalled = false;
      let correctPatternCatchCalled = false;

      // Set up the anti-pattern promise with .catch()
      // We don't await this - we just want to see if .catch() gets called
      processWithAntiPattern("invalid")
        .catch(() => {
          antiPatternCatchCalled = true;
        });

      // Set up the correct pattern promise with .catch()
      const correctPatternPromise = processWithCorrectPattern("invalid")
        .catch(() => {
          correctPatternCatchCalled = true;
          return "caught";
        });

      // Wait a bit for everything to settle
      await new Promise((resolve) => setTimeout(resolve, 50));

      // The correct pattern's .catch() was called
      expect(correctPatternCatchCalled).toBe(true);
      const correctResult = await correctPatternPromise;
      expect(correctResult).toBe("caught");

      // The anti-pattern's .catch() was NEVER called - the promise is still pending
      expect(antiPatternCatchCalled).toBe(false);

      // Note: Again, this causes an unhandled rejection - that IS the bug
    });
  });
});

describe("Why the anti-pattern is dangerous in real code", () => {
  it("demonstrates lost errors - callers think everything is fine", async () => {
    // In real code, you might call the anti-pattern function and await it
    // The caller has no idea an error occurred - their await never completes
    // and the error silently disappears (becomes unhandled rejection)

    let callerGotResult = false;
    let callerGotError = false;

    const callWithTimeout = async () => {
      try {
        const result = await Promise.race([
          processWithAntiPattern(""), // Will cause unhandled rejection
          new Promise<string>((_, reject) =>
            setTimeout(() => reject(new Error("Operation timed out")), 50)
          ),
        ]);
        callerGotResult = true;
        return result;
      } catch (err) {
        callerGotError = true;
        return err;
      }
    };

    const result = await callWithTimeout();

    // The caller got a timeout error, not the actual validation error!
    // The real error was lost as an unhandled rejection
    expect(callerGotResult).toBe(false);
    expect(callerGotError).toBe(true);
    expect((result as Error).message).toBe("Operation timed out");
    // The actual error "Input cannot be empty" was lost!
  });

  it("correct pattern preserves the actual error", async () => {
    let callerGotResult = false;
    let callerGotError = false;

    const callWithTimeout = async () => {
      try {
        const result = await Promise.race([
          processWithCorrectPattern(""), // Will properly reject
          new Promise<string>((_, reject) =>
            setTimeout(() => reject(new Error("Operation timed out")), 50)
          ),
        ]);
        callerGotResult = true;
        return result;
      } catch (err) {
        callerGotError = true;
        return err;
      }
    };

    const result = await callWithTimeout();

    // The caller got the ACTUAL error
    expect(callerGotResult).toBe(false);
    expect(callerGotError).toBe(true);
    expect((result as Error).message).toBe("Input cannot be empty");
  });
});

import React, { useState, useCallback, useMemo, useEffect } from "react";
import { useInput, Text } from "ink";
import chalk from "chalk";
import { enhancePromptPreservingCode } from "../../llm/enhance.ts";

export type EnhancedTextInputProps = {
  /**
   * When disabled, user input is ignored.
   * @default false
   */
  readonly isDisabled?: boolean;
  /**
   * Text to display when input is empty.
   */
  readonly placeholder?: string;
  /**
   * Default input value.
   */
  readonly defaultValue?: string;
  /**
   * Callback when enter is pressed. First argument is input value.
   */
  readonly onSubmit?: (value: string) => void;
  /**
   * Callback when enhancement starts.
   */
  readonly onEnhanceStart?: () => void;
  /**
   * Callback when enhancement completes.
   */
  readonly onEnhanceComplete?: () => void;
  /**
   * Callback when enhancement fails.
   */
  readonly onEnhanceError?: (error: Error) => void;
};

const cursor = chalk.inverse(" ");

export function EnhancedTextInput({
  isDisabled = false,
  placeholder = "",
  defaultValue = "",
  onSubmit,
  onEnhanceStart,
  onEnhanceComplete,
  onEnhanceError,
}: EnhancedTextInputProps): React.JSX.Element {
  const [value, setValue] = useState(defaultValue);
  const [cursorOffset, setCursorOffset] = useState(defaultValue.length);
  const [isEnhancing, setIsEnhancing] = useState(false);

  // Reset state when defaultValue changes (for key-based remounting)
  useEffect(() => {
    setValue(defaultValue);
    setCursorOffset(defaultValue.length);
  }, [defaultValue]);

  const handleEnhance = useCallback(async () => {
    if (!value.trim() || isEnhancing || isDisabled) return;

    setIsEnhancing(true);
    onEnhanceStart?.();

    try {
      const enhanced = await enhancePromptPreservingCode(value);
      setValue(enhanced);
      setCursorOffset(enhanced.length);
      onEnhanceComplete?.();
    } catch (error) {
      onEnhanceError?.(error instanceof Error ? error : new Error(String(error)));
    } finally {
      setIsEnhancing(false);
    }
  }, [value, isEnhancing, isDisabled, onEnhanceStart, onEnhanceComplete, onEnhanceError]);

  useInput(
    (input, key) => {
      if (isDisabled || isEnhancing) return;

      // Check for Ctrl+P (works on all platforms) or Cmd+P (macOS)
      // In terminal, Ctrl+P sends ASCII 16 (DLE - Data Link Escape)
      // which corresponds to input === '\x10'
      if (input === "\x10" || (key.ctrl && input === "p")) {
        handleEnhance();
        return;
      }

      // Ignore other control sequences
      if (
        key.upArrow ||
        key.downArrow ||
        (key.ctrl && input === "c") ||
        key.tab ||
        (key.shift && key.tab)
      ) {
        return;
      }

      if (key.return) {
        onSubmit?.(value);
        return;
      }

      if (key.leftArrow) {
        setCursorOffset((prev) => Math.max(0, prev - 1));
      } else if (key.rightArrow) {
        setCursorOffset((prev) => Math.min(value.length, prev + 1));
      } else if (key.backspace || key.delete) {
        if (cursorOffset > 0) {
          const newValue =
            value.slice(0, cursorOffset - 1) + value.slice(cursorOffset);
          setValue(newValue);
          setCursorOffset((prev) => Math.max(0, prev - 1));
        }
      } else if (input && !key.ctrl && !key.meta) {
        const newValue =
          value.slice(0, cursorOffset) + input + value.slice(cursorOffset);
        setValue(newValue);
        setCursorOffset((prev) => prev + input.length);
      }
    },
    { isActive: !isDisabled }
  );

  const renderedPlaceholder = useMemo(() => {
    if (isDisabled || isEnhancing) {
      return placeholder ? chalk.dim(placeholder) : "";
    }
    return placeholder && placeholder.length > 0
      ? chalk.inverse(placeholder[0]) + chalk.dim(placeholder.slice(1))
      : cursor;
  }, [isDisabled, isEnhancing, placeholder]);

  const renderedValue = useMemo(() => {
    if (isDisabled || isEnhancing) {
      return value;
    }

    let index = 0;
    let result = value.length > 0 ? "" : cursor;

    for (const char of value) {
      result += index === cursorOffset ? chalk.inverse(char) : char;
      index++;
    }

    if (value.length > 0 && cursorOffset === value.length) {
      result += cursor;
    }

    return result;
  }, [isDisabled, isEnhancing, value, cursorOffset]);

  const displayValue = value.length > 0 ? renderedValue : renderedPlaceholder;

  return <Text>{displayValue}</Text>;
}


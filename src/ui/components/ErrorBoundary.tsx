import React, { Component, type ReactNode } from "react";
import { Box, Text } from "ink";

interface ErrorBoundaryProps {
  children: ReactNode;
  fallback?: ReactNode;
}

interface ErrorBoundaryState {
  hasError: boolean;
  error: Error | null;
}

/**
 * Error boundary component for graceful error handling in the UI
 */
export class ErrorBoundary extends Component<ErrorBoundaryProps, ErrorBoundaryState> {
  constructor(props: ErrorBoundaryProps) {
    super(props);
    this.state = { hasError: false, error: null };
  }

  static getDerivedStateFromError(error: Error): ErrorBoundaryState {
    return { hasError: true, error };
  }

  override componentDidCatch(error: Error, errorInfo: React.ErrorInfo): void {
    // Log error for debugging
    console.error("UI Error:", error);
    console.error("Component Stack:", errorInfo.componentStack);
  }

  override render(): ReactNode {
    if (this.state.hasError) {
      if (this.props.fallback) {
        return this.props.fallback;
      }

      return (
        <Box flexDirection="column" padding={1}>
          <Text color="red" bold>
            An error occurred in the UI
          </Text>
          <Text color="gray">{this.state.error?.message || "Unknown error"}</Text>
          <Text color="yellow" dimColor>
            Press Ctrl+C to exit and restart
          </Text>
        </Box>
      );
    }

    return this.props.children;
  }
}


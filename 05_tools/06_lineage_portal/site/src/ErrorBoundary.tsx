"use client";

import { Component, type ReactNode } from "react";

type Props = { children: ReactNode };
type State = { error: Error | null };

export class ErrorBoundary extends Component<Props, State> {
  state: State = { error: null };

  static getDerivedStateFromError(error: Error): State {
    return { error };
  }

  render() {
    if (this.state.error) {
      return (
        <main className="app-shell">
          <div style={{
            display: "grid", placeItems: "center", minHeight: "60vh",
            color: "#fafafa", fontFamily: "Geist, Inter, sans-serif", gap: 16
          }}>
            <h1 style={{ color: "#ef4444", fontSize: "1.5rem" }}>Client Error</h1>
            <pre style={{
              maxWidth: 700, padding: 20, borderRadius: 10,
              background: "#18181b", border: "1px solid #27272a",
              color: "#f87171", fontSize: "0.82rem", lineHeight: 1.6,
              whiteSpace: "pre-wrap", wordBreak: "break-word"
            }}>
              {this.state.error.message}
              {"\n\n"}
              {this.state.error.stack?.slice(0, 800)}
            </pre>
          </div>
        </main>
      );
    }
    return this.props.children;
  }
}

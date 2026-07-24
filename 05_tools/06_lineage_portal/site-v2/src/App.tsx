import { useCallback, useEffect, useMemo, useState } from "react";
import { CommandPalette } from "./panels/CommandPalette";
import { DetailSheet } from "./panels/DetailSheet";
import { EmptyState } from "./panels/EmptyState";
import { LineageGraph, type FocusHighlight } from "./graph/LineageGraph";
import { Legend } from "./components/Legend";
import { Topbar } from "./components/Topbar";
import { focusView, fullView, martView, type ViewMode } from "./lib/view";
import { neighborhood } from "./lib/lineage";
import { normalizeSnapshot } from "./lib/normalize";
import type { LineageNode, Snapshot } from "./lib/types";

// Snapshot lives next to index.html so it works locally and on GitHub Pages.
const SNAPSHOT_URL = `${import.meta.env.VITE_BASE_PATH ?? "/"}lineage_snapshot.json`.replace(
  /\/+/g,
  "/"
);

export function App() {
  const [snapshot, setSnapshot] = useState<Snapshot | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);

  // View state — the three preset modes.
  const [mode, setMode] = useState<ViewMode>("focus");
  const [focusId, setFocusId] = useState<string | null>(null);
  const [martId, setMartId] = useState<string | null>(null);
  const [hops, setHops] = useState(2);
  const [showSupport, setShowSupport] = useState(false);

  const [detail, setDetail] = useState<LineageNode | null>(null);
  const [paletteOpen, setPaletteOpen] = useState(false);

  useEffect(() => {
    fetch(SNAPSHOT_URL)
      .then((r) => {
        if (!r.ok) throw new Error(`snapshot ${r.status}`);
        return r.json();
      })
      .then((data: Snapshot) => setSnapshot(normalizeSnapshot(data)))
      .catch((err: Error) => setLoadError(err.message));
  }, []);

  useEffect(() => {
    const handler = (event: KeyboardEvent) => {
      const cmdKey = event.metaKey || event.ctrlKey;
      if (cmdKey && event.key.toLowerCase() === "k") {
        event.preventDefault();
        setPaletteOpen((prev) => !prev);
      } else if (event.key === "/" && !paletteOpen) {
        const target = event.target as HTMLElement | null;
        if (target && ["INPUT", "TEXTAREA"].includes(target.tagName)) return;
        event.preventDefault();
        setPaletteOpen(true);
      } else if (event.key === "Escape") {
        if (paletteOpen) setPaletteOpen(false);
        else if (detail || focusId) {
          setDetail(null);
          setFocusId((cur) => (mode === "focus" ? null : cur));
        }
      }
    };
    document.addEventListener("keydown", handler);
    return () => document.removeEventListener("keydown", handler);
  }, [paletteOpen, detail]);

  const nodesById = useMemo(() => {
    if (!snapshot) return new Map<string, LineageNode>();
    return new Map(snapshot.nodes.map((n) => [n.id, n]));
  }, [snapshot]);

  const marts = useMemo(() => {
    if (!snapshot) return [];
    if (snapshot.mart_registry?.length) {
      return snapshot.mart_registry.map((m) => ({ id: m.id, label: m.display_name }));
    }
    return (snapshot.marts ?? [])
      .filter((m) => !["shared", "unresolved"].includes(m.mart))
      .map((m) => ({ id: m.mart, label: m.mart.replace(/_/g, " ") }));
  }, [snapshot]);

  // Which nodes/edges are visible — depends purely on mode. Synchronous, memoized.
  const view = useMemo(() => {
    if (!snapshot) return null;
    if (mode === "focus" && focusId) {
      const fv = focusView(snapshot, focusId, hops, showSupport);
      return { nodes: fv.nodes, edges: fv.edges };
    }
    if (mode === "mart" && martId) {
      const mv = martView(snapshot, martId, showSupport);
      return { nodes: mv.nodes, edges: mv.edges };
    }
    if (mode === "full") {
      const all = fullView(snapshot, showSupport);
      return { nodes: all.nodes, edges: all.edges };
    }
    return null;
  }, [snapshot, mode, focusId, martId, hops, showSupport]);

  // Emphasis overlay — computed from the selected node over the VISIBLE edges,
  // so clicking any table (in mart / full / focus) highlights its full
  // up/downstream lineage path and dims everything else. Consistent across modes.
  const highlight = useMemo<FocusHighlight | null>(() => {
    if (!view) return null;
    const selId = detail?.id ?? focusId;
    if (!selId || !view.nodes.some((n) => n.id === selId)) return null;
    const nb = neighborhood(selId, view.edges, Number.POSITIVE_INFINITY);
    return {
      selectedId: selId,
      upstream: nb.upstream,
      downstream: nb.downstream,
      upstreamEdges: nb.upstreamEdges,
      downstreamEdges: nb.downstreamEdges,
    };
  }, [view, detail, focusId]);

  const focusNode = focusId ? nodesById.get(focusId) ?? null : null;

  // ── actions ───────────────────────────────────────────────
  const selectTable = useCallback((node: LineageNode) => {
    setMode("focus");
    setFocusId(node.id);
    setDetail(node);
  }, []);

  const openMart = useCallback((id: string) => {
    setMode("mart");
    setMartId(id);
    setDetail(null);
  }, []);

  const openFull = useCallback(() => {
    setMode("full");
    setDetail(null);
  }, []);

  // Return to the landing screen — clears every view + selection state.
  const goHome = useCallback(() => {
    setMode("focus");
    setFocusId(null);
    setMartId(null);
    setDetail(null);
    setPaletteOpen(false);
  }, []);

  // Deselect the current node without leaving the view (clicking empty canvas /
  // pressing Escape). Highlight overlay clears because focusId + detail reset.
  const clearSelection = useCallback(() => {
    setDetail(null);
    if (mode === "focus") setFocusId(null);
  }, [mode]);

  const handleDownload = useCallback(() => {
    const link = document.createElement("a");
    link.href = SNAPSHOT_URL;
    link.download = "lineage_snapshot.json";
    link.click();
  }, []);

  // ── render guards ─────────────────────────────────────────
  if (loadError) {
    return (
      <main className="flex h-full items-center justify-center px-6">
        <div className="text-center">
          <div className="font-mono text-[10.5px] uppercase tracking-[0.2em] text-[var(--color-signal-err)]">
            Snapshot unavailable
          </div>
          <p className="mt-3 max-w-md text-[13.5px] text-ink-400">{loadError}</p>
          <p className="mt-2 max-w-md text-[11.5px] text-ink-600">
            Expected file at <code className="font-mono">{SNAPSHOT_URL}</code>
          </p>
        </div>
      </main>
    );
  }

  if (!snapshot) {
    return (
      <main className="flex h-full items-center justify-center">
        <div className="loading-pulse font-mono text-[10.5px] uppercase tracking-[0.22em] text-ink-500">
          Loading lineage…
        </div>
      </main>
    );
  }

  const isLanding = mode === "focus" && !focusId;

  return (
    <main className="flex h-full flex-col">
      <Topbar
        snapshot={snapshot}
        mode={mode}
        marts={marts}
        martId={martId}
        focusNode={focusNode}
        hops={hops}
        showSupport={showSupport}
        onHome={goHome}
        onModeFocus={() => {
          setMode("focus");
          if (!focusId) setPaletteOpen(true);
        }}
        onModeMart={(id) => openMart(id)}
        onModeFull={openFull}
        onHopsChange={setHops}
        onToggleSupport={() => setShowSupport((s) => !s)}
        onOpenSearch={() => setPaletteOpen(true)}
        onDownload={handleDownload}
        nodeCount={view?.nodes.length ?? 0}
        edgeCount={view?.edges.length ?? 0}
      />

      <div className="relative flex flex-1 overflow-hidden">
        <section className="relative flex-1 overflow-hidden">
          {isLanding || !view ? (
            <EmptyState
              snapshot={snapshot}
              marts={marts}
              onSelect={selectTable}
              onOpenMart={openMart}
              onOpenFull={openFull}
              onOpenSearch={() => setPaletteOpen(true)}
            />
          ) : (
            <>
              <LineageGraph
                nodes={view.nodes}
                edges={view.edges}
                highlight={highlight}
                selectedId={detail?.id ?? focusId}
                onSelect={(node) => setDetail(node)}
                onClear={clearSelection}
              />
              <Legend showDirection={!!highlight} />
            </>
          )}
        </section>

        <DetailSheet
          node={detail}
          edges={snapshot.edges}
          nodesById={nodesById}
          onClose={() => setDetail(null)}
          onNavigate={(node) => selectTable(node)}
        />
      </div>

      <CommandPalette
        open={paletteOpen}
        onOpenChange={setPaletteOpen}
        snapshot={snapshot}
        onSelect={selectTable}
      />
    </main>
  );
}

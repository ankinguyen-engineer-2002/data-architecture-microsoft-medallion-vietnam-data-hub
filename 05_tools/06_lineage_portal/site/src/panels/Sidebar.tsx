"use client";

import { AlertTriangle, Boxes, ChevronLeft, ChevronRight, Database, GitBranch, Search } from "lucide-react";
import type { LineageNode } from "../types";

type Props = {
  query: string;
  onQueryChange: (value: string) => void;
  mart: string;
  onMartChange: (value: string) => void;
  layer: string;
  onLayerChange: (value: string) => void;
  showSupport: boolean;
  onToggleSupport: () => void;
  marts: Array<{ id: string; display_name: string }>;
  layers: string[];
  filteredNodeCount: number;
  filteredEdgeCount: number;
  totalNodeCount: number;
  warningCount: number;
  collapsed: boolean;
  onToggleCollapse: () => void;
  layerBadgeCounts: Record<string, number>;
};

export function Sidebar({
  query,
  onQueryChange,
  mart,
  onMartChange,
  layer,
  onLayerChange,
  showSupport,
  onToggleSupport,
  marts,
  layers,
  filteredNodeCount,
  filteredEdgeCount,
  totalNodeCount,
  warningCount,
  collapsed,
  onToggleCollapse,
  layerBadgeCounts
}: Props) {
  return (
    <>
      <button className="sidebar-collapse-toggle" onClick={onToggleCollapse} aria-label={collapsed ? "Expand sidebar" : "Collapse sidebar"}>
        {collapsed ? <ChevronRight size={18} /> : <ChevronLeft size={18} />}
      </button>
      {!collapsed && (
        <aside className="sidebar">
          <div className="sidebar-inner">
            <label className="search-box">
              <Search size={16} />
              <input
                value={query}
                onChange={(event) => onQueryChange(event.target.value)}
                placeholder="Search table, schema, object..."
              />
              {query && (
                <span className="search-badge">{filteredNodeCount}/{totalNodeCount}</span>
              )}
            </label>

            <div className="sidebar-section">
              <span className="section-label">Mart</span>
              <div className="select-wrapper">
                <select value={mart} onChange={(event) => onMartChange(event.target.value)}>
                  <option value="all">All business marts</option>
                  {marts.map((item) => (
                    <option key={item.id} value={item.id}>{item.display_name}</option>
                  ))}
                </select>
              </div>
            </div>

            <div className="sidebar-section">
              <span className="section-label">Layer</span>
              <div className="layer-chips">
                <button
                  className={`layer-chip ${layer === "all" ? "active" : ""}`}
                  onClick={() => onLayerChange("all")}
                >
                  All
                </button>
                {layers.map((item) => (
                  <button
                    key={item}
                    className={`layer-chip ${layer === item ? "active" : ""} chip-${item.toLowerCase()}`}
                    onClick={() => onLayerChange(item)}
                  >
                    {item}
                    {layerBadgeCounts[item] != null && (
                      <span className="chip-badge">{layerBadgeCounts[item]}</span>
                    )}
                  </button>
                ))}
              </div>
            </div>

            <label className="toggle">
              <input type="checkbox" checked={showSupport} onChange={onToggleSupport} />
              Show shared/support
            </label>

            <div className="summary-stack">
              <Summary icon={<Boxes size={18} />} label="Visible tables" value={filteredNodeCount} />
              <Summary icon={<GitBranch size={18} />} label="Visible flows" value={filteredEdgeCount} />
              <Summary icon={<Database size={18} />} label="Marts" value={marts.length} />
              <Summary icon={<AlertTriangle size={18} />} label="Warnings" value={warningCount} />
            </div>

            <div className="sidebar-footer">
              <kbd>Cmd+K</kbd> <span>Command palette</span>
            </div>
          </div>
        </aside>
      )}
    </>
  );
}

function Summary({ icon, label, value }: { icon: JSX.Element; label: string; value: number }) {
  return (
    <div className="summary-card">
      {icon}
      <span>{label}</span>
      <strong>{value.toLocaleString()}</strong>
    </div>
  );
}

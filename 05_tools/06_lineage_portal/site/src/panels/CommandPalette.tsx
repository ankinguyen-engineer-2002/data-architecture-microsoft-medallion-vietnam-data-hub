"use client";

import { useEffect, useState } from "react";
import { Command } from "cmdk";
import { Box, Database, Download, Eye, EyeOff, Layers3, Search } from "lucide-react";
import type { LineageNode } from "../types";

type Props = {
  nodes: LineageNode[];
  marts: Array<{ id: string; display_name: string }>;
  onSelectNode: (nodeId: string) => void;
  onSetMart: (mart: string) => void;
  onSetLayer: (layer: string) => void;
  onToggleSupport: () => void;
  showSupport: boolean;
  onDownload: () => void;
};

export function CommandPalette({ nodes, marts, onSelectNode, onSetMart, onSetLayer, onToggleSupport, showSupport, onDownload }: Props) {
  const [open, setOpen] = useState(false);

  useEffect(() => {
    const handler = (event: KeyboardEvent) => {
      if ((event.metaKey || event.ctrlKey) && event.key === "k") {
        event.preventDefault();
        setOpen((prev) => !prev);
      }
    };
    document.addEventListener("keydown", handler);
    return () => document.removeEventListener("keydown", handler);
  }, []);

  useEffect(() => {
    if (!open) return;
    const handler = (event: KeyboardEvent) => {
      if (event.key === "Escape") setOpen(false);
    };
    document.addEventListener("keydown", handler);
    return () => document.removeEventListener("keydown", handler);
  }, [open]);

  if (!open) return null;

  const tableItems = nodes.map((node) => ({
    id: node.id,
    name: node.display_name,
    schema: node.schema,
    layer: node.layer,
    mart: node.mart,
    keywords: [node.display_name, node.schema, node.full_name, node.layer, node.mart ?? ""].join(" ")
  }));

  const layerOrder = ["Bronze", "Silver", "Gold", "Semantic"];

  return (
    <div className="command-overlay" onClick={() => setOpen(false)}>
      <div className="command-palette" onClick={(e) => e.stopPropagation()}>
        <Command label="Lineage Command Palette">
          <div className="command-header">
            <Search size={16} />
            <Command.Input autoFocus placeholder="Search tables, switch mart, toggle support..." />
            <kbd>Esc</kbd>
          </div>
          <Command.List>
            <Command.Empty className="command-empty">No results found.</Command.Empty>
            <Command.Group heading="Quick Actions">
              <Command.Item onSelect={() => { onDownload(); setOpen(false); }}>
                <Download size={15} /> Download Snapshot JSON
              </Command.Item>
              <Command.Item onSelect={() => { onToggleSupport(); setOpen(false); }}>
                {showSupport ? <EyeOff size={15} /> : <Eye size={15} />}
                {showSupport ? "Hide shared/support nodes" : "Show shared/support nodes"}
              </Command.Item>
            </Command.Group>
            <Command.Group heading="Switch Mart">
              <Command.Item onSelect={() => { onSetMart("all"); setOpen(false); }}>All business marts</Command.Item>
              {marts.map((mart) => (
                <Command.Item key={mart.id} onSelect={() => { onSetMart(mart.id); setOpen(false); }}>
                  <Box size={15} /> {mart.display_name}
                </Command.Item>
              ))}
            </Command.Group>
            <Command.Group heading="Switch Layer">
              <Command.Item onSelect={() => { onSetLayer("all"); setOpen(false); }}>All layers</Command.Item>
              {layerOrder.map((layer) => (
                <Command.Item key={layer} onSelect={() => { onSetLayer(layer); setOpen(false); }}>
                  <Layers3 size={15} /> {layer}
                </Command.Item>
              ))}
            </Command.Group>
            <Command.Group heading="Tables">
              {tableItems.slice(0, 40).map((item) => (
                <Command.Item
                  key={item.id}
                  value={item.keywords}
                  onSelect={() => { onSelectNode(item.id); setOpen(false); }}
                >
                  <div className="cmd-item">
                    {item.layer === "Semantic" ? <Box size={15} /> : <Database size={15} />}
                    <span className="cmd-item-name">{item.name}</span>
                    <span className={`cmd-item-layer layer-${item.layer.toLowerCase()}`}>{item.layer}</span>
                    <span className="cmd-item-schema">{item.schema}</span>
                  </div>
                </Command.Item>
              ))}
            </Command.Group>
          </Command.List>
        </Command>
      </div>
    </div>
  );
}

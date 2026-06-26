"use client";

import { motion } from "motion/react";

const LAYERS = [
  { name: "Bronze", color: "#f59e0b", description: "Source / raw data" },
  { name: "Silver", color: "#4f8cff", description: "Cleaned & transformed" },
  { name: "Gold", color: "#eab308", description: "Star schema / serving" },
  { name: "Semantic", color: "#22c55e", description: "Power BI model" }
];

export function Legend() {
  return (
    <motion.div
      className="legend"
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ delay: 0.5, duration: 0.35 }}
    >
      {LAYERS.map((layer) => (
        <div key={layer.name} className="legend-item">
          <span className="legend-dot" style={{ background: layer.color }} />
          <span className="legend-label">{layer.name}</span>
          <span className="legend-desc">{layer.description}</span>
        </div>
      ))}
    </motion.div>
  );
}

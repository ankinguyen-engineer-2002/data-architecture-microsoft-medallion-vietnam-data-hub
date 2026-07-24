import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwind from "@tailwindcss/vite";
import { fileURLToPath, URL } from "node:url";

// site-v2 shares the backend snapshot with site/. When deployed to GitHub Pages
// under the repo path, set VITE_BASE_PATH to the same base as the primary site
// (e.g. /data-architecture-microsoft-medallion-vietnam-data-hub/v2/).
export default defineConfig({
  base: process.env.VITE_BASE_PATH ?? "/",
  plugins: [react(), tailwind()],
  resolve: {
    alias: {
      "@": fileURLToPath(new URL("./src", import.meta.url)),
    },
  },
  build: {
    outDir: "dist",
    sourcemap: true,
    chunkSizeWarningLimit: 2200,
  },
  server: {
    port: 5175,
  },
});

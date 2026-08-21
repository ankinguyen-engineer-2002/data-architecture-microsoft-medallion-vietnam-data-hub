import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  root: ".",
  server: {
    port: 5186,
  },
  build: {
    outDir: ".tmp/rich-presentation-web",
    emptyOutDir: true,
    sourcemap: true,
  },
});

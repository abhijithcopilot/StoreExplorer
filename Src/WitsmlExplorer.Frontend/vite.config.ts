/// <reference types="vite/client" />

import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";
import tsconfigPaths from "vite-tsconfig-paths";

// https://vitejs.dev/config/
export default defineConfig(({ mode }) => ({
  plugins: [react(), tsconfigPaths()],

  // Sub-path when hosted in IIS under an existing website (e.g. /storeExplorer/).
  // Falls back to "/" in development so the dev server still works.
  base: mode === "production" ? "/storeExplorer/" : "/",

  // port for preview
  preview: {
    port: 3000
  },

  // port for dev
  server: {
    port: 3000
  }
}));

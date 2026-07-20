import { defineConfig } from 'vite';

export default defineConfig({
  base: './', // relative paths for WebView loading
  build: {
    outDir: 'dist'
  }
});

import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

// Support console. Separate app and port from the buyer-facing web client;
// deployed behind its own host, never bundled with the public site.
export default defineConfig({
  plugins: [react(), tailwindcss()],
  server: {
    port: 5174,
    proxy: {
      '/graphql': 'http://localhost:4000',
    },
  },
})

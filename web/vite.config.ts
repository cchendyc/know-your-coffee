import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

export default defineConfig({
  // Production is https://knowyourthings.top (site root). CI sets BASE_PATH=/ .
  base: process.env.BASE_PATH || '/',
  plugins: [react(), tailwindcss()],
  server: {
    proxy: {
      '/graphql': 'http://localhost:4000',
    },
  },
})

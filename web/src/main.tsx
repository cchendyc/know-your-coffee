import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { BrowserRouter } from 'react-router'
import './index.css'
import './theme'
import App from './App'

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    {/* BASE_URL is "/" at knowyourthings.top and "/<repo>/" on github.io. */}
    <BrowserRouter basename={import.meta.env.BASE_URL}>
      <App />
    </BrowserRouter>
  </StrictMode>,
)

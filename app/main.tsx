import React from 'react';
import {createRoot} from 'react-dom/client';
import {ThemeProvider} from 'next-themes';
import App from './auth';
import './globals.css';
import './enhancements.css';
createRoot(document.getElementById('root')!).render(<React.StrictMode><ThemeProvider forcedTheme="light"><App/></ThemeProvider></React.StrictMode>);

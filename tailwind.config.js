const colors = require('tailwindcss/colors');

/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    "./public/index.html",
    "./src/**/*.{js,jsx}"
  ],
  theme: {
    extend: {
      colors: {
        // keep your existing primary scale
        primary: {
          50:  '#edf9ff',
          100: '#d6f0ff',
          200: '#b5e7ff',
          300: '#83d9ff',
          400: '#48c2ff',
          500: '#1ea1ff',
          600: '#0682ff',
          700: '#006be6',
          800: '#0057b8',
          900: '#003d7a'
        },
        // NEW: add a secondary scale so classes like text-secondary-800 exist
        secondary: colors.slate
      },
      fontFamily: { sans: ['Inter', 'sans-serif'] },
    },
  },
  plugins: [],
};

/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      fontFamily: {
        sans: ['"SF Pro Display"', '-apple-system', 'BlinkMacSystemFont', 'sans-serif'],
      },
      keyframes: {
        float: {
          '0%, 100%': { transform: 'translate(0, 0)' },
          '50%': { transform: 'translate(30px, -30px)' },
        },
        'float-reverse': {
          '0%, 100%': { transform: 'translate(0, 0)' },
          '50%': { transform: 'translate(-30px, 30px)' },
        },
        slideUp: {
          'from': { opacity: '0', transform: 'translateY(30px)' },
          'to': { opacity: '1', transform: 'translateY(0)' },
        },
        slideIn: {
          'from': { opacity: '0', transform: 'translateY(20px)' },
          'to': { opacity: '1', transform: 'translateY(0)' },
        },
        fadeIn: {
          'from': { opacity: '0' },
          'to': { opacity: '1' },
        }
      },
      animation: {
        float: 'float 20s ease-in-out infinite',
        'float-reverse': 'float-reverse 15s ease-in-out infinite',
        slideUp: 'slideUp 0.6s ease-out forwards',
        slideIn: 'slideIn 0.5s ease-out forwards',
        fadeIn: 'fadeIn 0.2s ease-out forwards',
      }
    },
  },
  plugins: [],
}
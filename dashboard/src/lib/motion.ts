import type { Variants } from 'framer-motion';

// Shared, restrained motion presets. Framer Motion automatically respects the
// OS "reduce motion" setting when components opt in via useReducedMotion; these
// presets keep travel small so the UI stays minimal rather than flashy.

export const fadeUp: Variants = {
  hidden: { opacity: 0, y: 12 },
  show: {
    opacity: 1,
    y: 0,
    transition: { duration: 0.45, ease: [0.22, 1, 0.36, 1] },
  },
};

export const fade: Variants = {
  hidden: { opacity: 0 },
  show: { opacity: 1, transition: { duration: 0.4 } },
};

export const staggerContainer = (stagger = 0.05, delay = 0): Variants => ({
  hidden: {},
  show: {
    transition: { staggerChildren: stagger, delayChildren: delay },
  },
});

// Standard viewport config for scroll-reveal sections.
export const inView = { once: true, amount: 0.2 } as const;

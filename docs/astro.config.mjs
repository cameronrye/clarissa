import { defineConfig } from 'astro/config';

export default defineConfig({
  site: 'https://cameronrye.github.io',
  base: '/clarissa/',
  trailingSlash: 'always',
  build: {
    assets: '_assets'
  }
});


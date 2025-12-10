import { $ } from 'bun';

const sizes = [192, 512];
const svgPath = 'public/logo.svg';
const outputDir = 'public/icons';

// Read SVG and add background for PWA icons
const svgContent = await Bun.file(svgPath).text();

// Create a modified SVG with solid background for PWA
const createPwaSvg = (size: number) => {
  const padding = Math.round(size * 0.15);
  const innerSize = size - padding * 2;

  return `<svg width="${size}" height="${size}" viewBox="0 0 ${size} ${size}" xmlns="http://www.w3.org/2000/svg">
  <rect width="${size}" height="${size}" fill="#0a0a0f" rx="${Math.round(size * 0.15)}"/>
  <g transform="translate(${padding}, ${padding})">
    <svg viewBox="0 0 64 64" width="${innerSize}" height="${innerSize}">
      ${svgContent.replace(/<\?xml[^?]*\?>/, '').replace(/<svg[^>]*>/, '').replace(/<\/svg>/, '')}
    </svg>
  </g>
</svg>`;
};

// Check if we have a tool to convert SVG to PNG
try {
  await $`which rsvg-convert`.quiet();

  for (const size of sizes) {
    const pwaSvg = createPwaSvg(size);
    const tempSvg = `${outputDir}/temp-${size}.svg`;
    await Bun.write(tempSvg, pwaSvg);
    await $`rsvg-convert -w ${size} -h ${size} ${tempSvg} -o ${outputDir}/icon-${size}.png`;
    await $`rm ${tempSvg}`;
    console.log(`Generated icon-${size}.png`);
  }
} catch {
  // Fallback: create placeholder PNGs using ImageMagick if available
  try {
    await $`which convert`.quiet();

    for (const size of sizes) {
      const pwaSvg = createPwaSvg(size);
      const tempSvg = `${outputDir}/temp-${size}.svg`;
      await Bun.write(tempSvg, pwaSvg);
      await $`convert ${tempSvg} -resize ${size}x${size} ${outputDir}/icon-${size}.png`;
      await $`rm ${tempSvg}`;
      console.log(`Generated icon-${size}.png`);
    }
  } catch {
    // Final fallback: just save the SVG files as placeholders
    console.log('No SVG to PNG converter found (rsvg-convert or ImageMagick)');
    console.log('Saving SVG versions - you can convert manually or install librsvg/ImageMagick');

    for (const size of sizes) {
      const pwaSvg = createPwaSvg(size);
      await Bun.write(`${outputDir}/icon-${size}.svg`, pwaSvg);
      console.log(`Saved icon-${size}.svg (convert to PNG manually)`);
    }
  }
}


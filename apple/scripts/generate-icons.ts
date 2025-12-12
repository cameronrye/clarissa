import { $ } from "bun";

const svgPath = "docs/public/logo.svg";
const outputDir = "apple/Clarissa/Resources/Assets.xcassets/AppIcon.appiconset";

// Read SVG content
const svgContent = await Bun.file(svgPath).text();

// Create app icon SVG with background
// logoPadding adds space around the logo by expanding the viewBox
// Higher values = smaller logo (more padding around it)
const createAppIconSvg = (size: number, logoPadding: number = 8) => {
  const viewBoxSize = 64 + logoPadding * 2;

  // Extract SVG inner content (remove xml declaration, svg tags)
  const innerContent = svgContent
    .replace(/<\?xml[^?]*\?>/, "")
    .replace(/<svg[^>]*>/, "")
    .replace(/<\/svg>/, "");

  return `<svg width="${size}" height="${size}" viewBox="-${logoPadding} -${logoPadding} ${viewBoxSize} ${viewBoxSize}" xmlns="http://www.w3.org/2000/svg">
  <rect x="-${logoPadding}" y="-${logoPadding}" width="${viewBoxSize}" height="${viewBoxSize}" fill="#0a0a0f"/>
  ${innerContent}
</svg>`;
};

// Check for rsvg-convert or ImageMagick
const hasRsvg = await $`which rsvg-convert`.quiet().then(() => true).catch(() => false);
const hasConvert = await $`which convert`.quiet().then(() => true).catch(() => false);

if (!hasRsvg && !hasConvert) {
  console.error("Error: No SVG to PNG converter found.");
  console.error("Please install librsvg: brew install librsvg");
  console.error("Or ImageMagick: brew install imagemagick");
  process.exit(1);
}

// Logo padding value - higher = smaller logo (8 is default, try 5-12)
const LOGO_PADDING = 4;

// Generate iOS icon (1024x1024)
const iosIconSvg = createAppIconSvg(1024, LOGO_PADDING);
const iosTempSvg = `${outputDir}/temp-ios.svg`;
await Bun.write(iosTempSvg, iosIconSvg);

if (hasRsvg) {
  await $`rsvg-convert -w 1024 -h 1024 ${iosTempSvg} -o ${outputDir}/AppIcon.png`;
} else {
  await $`convert ${iosTempSvg} -resize 1024x1024 ${outputDir}/AppIcon.png`;
}
await $`rm ${iosTempSvg}`;
console.log("Generated AppIcon.png (1024x1024)");

// Generate macOS icon (1024x1024)
const macIconSvg = createAppIconSvg(1024, LOGO_PADDING);
const macTempSvg = `${outputDir}/temp-mac.svg`;
await Bun.write(macTempSvg, macIconSvg);

if (hasRsvg) {
  await $`rsvg-convert -w 1024 -h 1024 ${macTempSvg} -o ${outputDir}/AppIcon-mac.png`;
} else {
  await $`convert ${macTempSvg} -resize 1024x1024 ${outputDir}/AppIcon-mac.png`;
}
await $`rm ${macTempSvg}`;
console.log("Generated AppIcon-mac.png (1024x1024)");

console.log(`\nDone! Icons generated with logo padding: ${LOGO_PADDING}`);


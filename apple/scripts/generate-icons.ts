import { $ } from "bun";

const svgPath = "docs/public/logo.svg";
const iosOutputDir = "apple/Clarissa/Resources/Assets.xcassets/AppIcon.appiconset";
const watchOutputDir = "apple/Clarissa/ClarissaWatch/Resources/Assets.xcassets/AppIcon.appiconset";

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

// Helper to generate a PNG icon
async function generateIcon(size: number, outputPath: string, padding: number = LOGO_PADDING) {
  const svg = createAppIconSvg(size, padding);
  const tempSvg = `${outputPath}.temp.svg`;
  await Bun.write(tempSvg, svg);
  if (hasRsvg) {
    await $`rsvg-convert -w ${size} -h ${size} ${tempSvg} -o ${outputPath}`;
  } else {
    await $`convert ${tempSvg} -resize ${size}x${size} ${outputPath}`;
  }
  await $`rm ${tempSvg}`;
}

// Generate iOS/macOS icons
await generateIcon(1024, `${iosOutputDir}/AppIcon.png`);
console.log("Generated AppIcon.png (1024x1024)");

await generateIcon(1024, `${iosOutputDir}/AppIcon-mac.png`);
console.log("Generated AppIcon-mac.png (1024x1024)");

await generateIcon(512, `${iosOutputDir}/AppIcon-mac-1x.png`);
console.log("Generated AppIcon-mac-1x.png (512x512)");

// Modern watchOS uses a single 1024x1024 icon (watchOS 10+, Xcode 15+)
console.log("\nGenerating watchOS icon...");
await generateIcon(1024, `${watchOutputDir}/AppIcon.png`);
console.log("Generated watchOS AppIcon.png (1024x1024)");

// Update watchOS Contents.json with modern single-icon format
const watchContents = {
  images: [
    {
      filename: "AppIcon.png",
      idiom: "universal",
      platform: "watchos",
      size: "1024x1024"
    }
  ],
  info: { author: "xcode", version: 1 },
};
await Bun.write(`${watchOutputDir}/Contents.json`, JSON.stringify(watchContents, null, 2));
console.log("Updated watchOS Contents.json");

console.log(`\nDone! Icons generated with logo padding: ${LOGO_PADDING}`);


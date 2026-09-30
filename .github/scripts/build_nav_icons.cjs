// Build the runtime atlas from original vector artwork. Requires sharp.
// Usage: node .github/scripts/build_nav_icons.cjs [preview.png]
const fs = require('node:fs');
const path = require('node:path');
const sharp = require('sharp');
const root = path.resolve(__dirname, '../..');
async function build() {
  const source = path.join(root, 'tools/artwork/menu_navigation.svg');
  const {data, info} = await sharp(source).ensureAlpha().raw().toBuffer({resolveWithObject: true});
  if (info.width !== 1024 || info.height !== 1024 || info.channels !== 4) throw new Error('Unexpected atlas format');
  const header = Buffer.alloc(18);
  header[2] = 2; // Uncompressed BGRA, top-left origin, eight alpha bits.
  header.writeUInt16LE(info.width, 12);
  header.writeUInt16LE(info.height, 14);
  header[16] = 32;
  header[17] = 0x28;
  const pixels = Buffer.from(data);
  for (let i = 0; i < pixels.length; i += 4) {
    [pixels[i], pixels[i + 2]] = [pixels[i + 2], pixels[i]];
    // White transparent padding prevents dark fringes when the atlas is reduced.
    if (pixels[i + 3] === 0) pixels[i] = pixels[i + 1] = pixels[i + 2] = 255;
  }
  fs.writeFileSync(path.join(root, 'MidnightSimpleUnitFrames/Media/msuf_nav_icons_hd.tga'), Buffer.concat([header, pixels]));
  if (process.argv[2]) await sharp(data, {raw: info}).png().toFile(process.argv[2]);
  console.log('Navigation atlas: 1024 x 1024 RGBA, 128 px per cell');
}
build().catch(error => { console.error(error); process.exitCode = 1; });

// 把 concepts.mjs 里的图标方案渲染成 PNG，拼一张对比图，选定后装进 Xcode 的图标资源。
// 在 tools/icon 文件夹里运行（第一次先 npm install）：
//   node build_icon.mjs                 渲染全部方案到 out/，并生成 out/contact-sheet.png 对比图
//   node build_icon.mjs --install heart 把 heart 方案的三张图装进 App 的 AppIcon.appiconset
// 渲染用的是 sharp（GitHub 上三万多星的 Node 图片库，内置 SVG 渲染）。

import sharp from "sharp";
import { copyFileSync, mkdirSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { CONCEPTS } from "./concepts.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const OUT = join(HERE, "out");
const ROOT = resolve(HERE, "..", "..");
const APPICON_DIR = join(ROOT, "FoodTracker/FoodTracker/Assets.xcassets/AppIcon.appiconset");
const SIZE = 1024;
const VARIANTS = ["light", "dark", "tinted"];

/** SVG 文字 → 1024×1024 的 PNG */
async function renderPng(svgText) {
  return sharp(Buffer.from(svgText)).resize(SIZE, SIZE).png().toBuffer();
}

/** 系统给图标切的圆角，近似成圆角矩形（真实的是「超椭圆」，看起来差不多） */
function roundedMask(size) {
  const r = Math.round(size * 0.2237);
  return Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}"><rect width="${size}" height="${size}" rx="${r}" ry="${r}" fill="white"/></svg>`);
}

/** 把图标缩到 size 并切圆角，垫上背景（模拟 dark / tinted 版本在系统里的样子） */
async function preview(png, size, { background, tint } = {}) {
  let icon = sharp(png).resize(size, size);
  if (tint) icon = icon.tint(tint);
  const iconBuf = await icon.png().toBuffer();
  let layered = iconBuf;
  if (background) {
    layered = await sharp({ create: { width: size, height: size, channels: 4, background } })
      .composite([{ input: iconBuf }])
      .png()
      .toBuffer();
  }
  return sharp(layered).composite([{ input: roundedMask(size), blend: "dest-in" }]).png().toBuffer();
}

async function renderAll() {
  mkdirSync(OUT, { recursive: true });
  const rendered = {};
  for (const [name, concept] of Object.entries(CONCEPTS)) {
    rendered[name] = {};
    for (const variant of VARIANTS) {
      const png = await renderPng(concept.svg(variant));
      writeFileSync(join(OUT, `${name}-${variant}.png`), png);
      rendered[name][variant] = png;
    }
    console.log(`rendered ${name}: ${VARIANTS.join(", ")}`);
  }
  return rendered;
}

/** 对比图：每行一个方案，列是 light、dark、tinted 的模拟效果，再加两个真实大小（主屏幕 60 点 ≈ 180 像素、通知 40 点） */
async function contactSheet(rendered) {
  const names = Object.keys(rendered);
  const big = 200, small = 120, tiny = 60, gap = 28, labelW = 280, top = 70;
  const columns = [big, big, big, small, tiny];
  const width = labelW + columns.reduce((a, b) => a + b + gap, 0) + gap;
  const rowH = big + gap;
  const height = top + names.length * rowH + gap + 40;
  const dark = { r: 28, g: 28, b: 30, alpha: 1 };
  const light = { r: 242, g: 242, b: 247, alpha: 1 };

  const layers = [];
  const labels = [];
  const headers = ["Light", "Dark *", "Tinted *", "60 pt", "40 pt"];
  let x = labelW;
  columns.forEach((w, i) => {
    labels.push(`<text x="${x}" y="44" font-size="20" fill="#3c3c43">${headers[i]}</text>`);
    x += w + gap;
  });
  labels.push(`<text x="24" y="${height - 24}" font-size="16" fill="#6e6e73">* Dark and tinted icons have a transparent background; iOS adds the dark background and the tint color itself (simulated here).</text>`);
  names.forEach((name, row) => {
    const y = top + row * rowH;
    labels.push(`<text x="24" y="${y + 40}" font-size="26" font-weight="bold" fill="#1d1d1f">${String.fromCharCode(65 + row)}. ${name}</text>`);
    labels.push(`<text x="24" y="${y + 74}" font-size="17" fill="#6e6e73">${CONCEPTS[name].title}</text>`);
  });
  layers.push({ input: Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" font-family="Helvetica, Arial, sans-serif">${labels.join("")}</svg>`), left: 0, top: 0 });

  for (const [row, name] of names.entries()) {
    const y = top + row * rowH;
    const r = rendered[name];
    const cells = [
      await preview(r.light, big),
      await preview(r.dark, big, { background: dark }),
      await preview(r.tinted, big, { background: dark, tint: { r: 120, g: 160, b: 255 } }),
      await preview(r.light, small),
      await preview(r.light, tiny),
    ];
    let cx = labelW;
    cells.forEach((cell, i) => {
      layers.push({ input: cell, left: cx, top: y + Math.round((big - columns[i]) / 2) });
      cx += columns[i] + gap;
    });
  }
  const sheet = await sharp({ create: { width, height, channels: 4, background: light } }).composite(layers).png().toBuffer();
  writeFileSync(join(OUT, "contact-sheet.png"), sheet);
  console.log(`contact sheet: ${join(OUT, "contact-sheet.png")}`);
}

/** 把选定方案的三张图装进 Xcode 的图标资源，并写好 Contents.json */
function install(name) {
  if (!CONCEPTS[name]) throw new Error(`没有叫 ${name} 的方案，可选：${Object.keys(CONCEPTS).join(", ")}`);
  const files = {};
  for (const variant of VARIANTS) {
    const file = `AppIcon-1024-${variant}.png`;
    copyFileSync(join(OUT, `${name}-${variant}.png`), join(APPICON_DIR, file));
    files[variant] = file;
  }
  const contents = {
    images: [
      { filename: files.light, idiom: "universal", platform: "ios", size: "1024x1024" },
      { appearances: [{ appearance: "luminosity", value: "dark" }], filename: files.dark, idiom: "universal", platform: "ios", size: "1024x1024" },
      { appearances: [{ appearance: "luminosity", value: "tinted" }], filename: files.tinted, idiom: "universal", platform: "ios", size: "1024x1024" },
    ],
    info: { author: "xcode", version: 1 },
  };
  writeFileSync(join(APPICON_DIR, "Contents.json"), JSON.stringify(contents, null, 2) + "\n");
  console.log(`installed ${name} into ${APPICON_DIR}`);
}

const args = process.argv.slice(2);
if (args[0] === "--install") {
  install(args[1]);
} else {
  const rendered = await renderAll();
  await contactSheet(rendered);
}

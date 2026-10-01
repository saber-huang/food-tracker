// 把 concepts.mjs 里的图标方案渲染成 PNG，拼一张对比图，选定后装进 Xcode 的图标资源。
// 在 tools/icon 文件夹里运行（第一次先 npm install）：
//   node build_icon.mjs                              渲染全部方案到 out/，并生成 out/contact-sheet.png 对比图
//   node build_icon.mjs --only kWhite,kBlack         只渲染这几个方案，对比图也只放它们
//   node build_icon.mjs --palettes                   把 lens 和 bowl 用 PALETTES 里的每套配色各渲染一遍，生成 out/palette-sheet.png
//   node build_icon.mjs --bowl-colors                扁平的碗按 BOWL_COLORS 里的每种颜色渲染，生成 out/bowl-colors.png
//   node build_icon.mjs --bowl-colors muted          同上，但用低饱和度的 BOWL_COLORS_MUTED，生成 out/bowl-colors-muted.png
//   node build_icon.mjs --bowl-colors light          同上，但用浅米色的 BOWL_COLORS_LIGHT，生成 out/bowl-colors-light.png
//   node build_icon.mjs --install heart              把 heart 方案的三张图装进 App 的 AppIcon.appiconset
//   node build_icon.mjs --install bowl --palette ink 同上，但用 ink 这套配色（只有 lens 和 bowl 支持）
//   node build_icon.mjs --install bowlFlat --color oat --bg white   扁平的碗指定颜色和背景（white / cream / #RRGGBB）
// 渲染用的是 sharp（GitHub 上三万多星的 Node 图片库，内置 SVG 渲染）。

import sharp from "sharp";
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { BOWL_COLORS, BOWL_COLORS_LIGHT, BOWL_COLORS_MUTED, CONCEPTS, PALETTES, PALETTE_CONCEPTS, bowlFlatSvg } from "./concepts.mjs";

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

async function renderAll(only) {
  mkdirSync(OUT, { recursive: true });
  const rendered = {};
  for (const [name, concept] of Object.entries(CONCEPTS)) {
    if (only && !only.includes(name)) continue;
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

/** 配色对比图：每行一套配色，列是 lens 和 bowl 各自的 light、dark 和主屏幕大小 */
async function paletteSheet() {
  mkdirSync(OUT, { recursive: true });
  const names = Object.keys(PALETTES);
  const big = 180, small = 60, gap = 24, labelW = 250, top = 70;
  const columns = [big, big, small, big, big, small];
  const width = labelW + columns.reduce((a, b) => a + b + gap, 0) + gap + 24;
  const rowH = big + gap;
  const height = top + names.length * rowH + gap + 40;
  const dark = { r: 28, g: 28, b: 30, alpha: 1 };
  const light = { r: 242, g: 242, b: 247, alpha: 1 };
  const layers = [];
  const labels = [];
  const headers = ["D lens", "D dark *", "60 pt", "E bowl", "E dark *", "60 pt"];
  let x = labelW;
  columns.forEach((w, i) => {
    labels.push(`<text x="${x}" y="44" font-size="20" fill="#3c3c43">${headers[i]}</text>`);
    x += w + gap;
  });
  labels.push(`<text x="24" y="${height - 24}" font-size="16" fill="#6e6e73">* Dark icons have a transparent background; iOS adds the dark background itself (simulated here).</text>`);
  for (const [row, name] of names.entries()) {
    const y = top + row * rowH;
    const p = PALETTES[name];
    labels.push(`<text x="24" y="${y + 40}" font-size="26" font-weight="bold" fill="#1d1d1f">${row + 1}. ${name}</text>`);
    labels.push(`<text x="24" y="${y + 72}" font-size="17" fill="#6e6e73">${p.title}</text>`);
    labels.push(`<text x="24" y="${y + 100}" font-size="15" fill="#8e8e93">${p.lens.bg.join(" → ")}</text>`);
    let cx = labelW;
    for (const concept of ["lens", "bowl"]) {
      const draw = PALETTE_CONCEPTS[concept];
      const lightPng = await renderPng(draw("light", p));
      const darkPng = await renderPng(draw("dark", p));
      writeFileSync(join(OUT, `palette-${name}-${concept}-light.png`), lightPng);
      writeFileSync(join(OUT, `palette-${name}-${concept}-dark.png`), darkPng);
      const cells = [await preview(lightPng, big), await preview(darkPng, big, { background: dark }), await preview(lightPng, small)];
      const widths = [big, big, small];
      cells.forEach((cell, i) => {
        layers.push({ input: cell, left: cx, top: y + Math.round((big - widths[i]) / 2) });
        cx += widths[i] + gap;
      });
    }
  }
  layers.unshift({ input: Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" font-family="Helvetica, Arial, sans-serif">${labels.join("")}</svg>`), left: 0, top: 0 });
  const sheet = await sharp({ create: { width, height, channels: 4, background: light } }).composite(layers).png().toBuffer();
  writeFileSync(join(OUT, "palette-sheet.png"), sheet);
  console.log(`palette sheet: ${join(OUT, "palette-sheet.png")}`);
}

/** 碗的颜色对比图：每行一种颜色，列是纯白底、米白底、两个主屏幕大小、深色外观 */
async function bowlColorSheet(group = "bright") {
  mkdirSync(OUT, { recursive: true });
  const colors = { muted: BOWL_COLORS_MUTED, light: BOWL_COLORS_LIGHT }[group] ?? BOWL_COLORS;
  const names = Object.keys(colors);
  const big = 180, small = 60, gap = 24, labelW = 250, top = 70;
  const columns = [big, big, small, small, big];
  const width = labelW + columns.reduce((a, b) => a + b + gap, 0) + gap + 24;
  const rowH = big + gap;
  const height = top + names.length * rowH + gap + 40;
  const dark = { r: 28, g: 28, b: 30, alpha: 1 };
  const light = { r: 242, g: 242, b: 247, alpha: 1 };
  const layers = [];
  const labels = [];
  const headers = ["Pure white", "Off-white", "60 pt", "60 pt", "Dark *"];
  let x = labelW;
  columns.forEach((w, i) => {
    labels.push(`<text x="${x}" y="44" font-size="20" fill="#3c3c43">${headers[i]}</text>`);
    x += w + gap;
  });
  labels.push(`<text x="24" y="${height - 24}" font-size="16" fill="#6e6e73">* Dark icons have a transparent background; iOS adds the dark background itself (simulated here).</text>`);
  for (const [row, name] of names.entries()) {
    const y = top + row * rowH;
    const c = colors[name];
    labels.push(`<text x="24" y="${y + 40}" font-size="26" font-weight="bold" fill="#1d1d1f">${row + 1}. ${name}</text>`);
    labels.push(`<text x="24" y="${y + 72}" font-size="17" fill="#6e6e73">${c.title}</text>`);
    labels.push(`<text x="24" y="${y + 100}" font-size="15" fill="#8e8e93">bowl ${c.bowl} · rim ${c.rim}</text>`);
    const onWhite = await renderPng(bowlFlatSvg("light", c, "#FFFFFF"));
    const onCream = await renderPng(bowlFlatSvg("light", c, "#FBF6EF"));
    const darkPng = await renderPng(bowlFlatSvg("dark", c));
    writeFileSync(join(OUT, `bowl-${name}-white.png`), onWhite);
    writeFileSync(join(OUT, `bowl-${name}-cream.png`), onCream);
    const cells = [
      await preview(onWhite, big), await preview(onCream, big),
      await preview(onWhite, small), await preview(onCream, small),
      await preview(darkPng, big, { background: dark }),
    ];
    let cx = labelW;
    cells.forEach((cell, i) => {
      layers.push({ input: cell, left: cx, top: y + Math.round((big - columns[i]) / 2) });
      cx += columns[i] + gap;
    });
  }
  layers.unshift({ input: Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" font-family="Helvetica, Arial, sans-serif">${labels.join("")}</svg>`), left: 0, top: 0 });
  const sheet = await sharp({ create: { width, height, channels: 4, background: light } }).composite(layers).png().toBuffer();
  const file = { muted: "bowl-colors-muted.png", light: "bowl-colors-light.png" }[group] ?? "bowl-colors.png";
  writeFileSync(join(OUT, file), sheet);
  console.log(`bowl color sheet: ${join(OUT, file)}`);
}

/** 把选定方案的三张图装进 Xcode 的图标资源，并写好 Contents.json。paletteName 只对 lens 和 bowl 有效 */
async function install(name, paletteName, colorName, background) {
  if (!CONCEPTS[name]) throw new Error(`没有叫 ${name} 的方案，可选：${Object.keys(CONCEPTS).join(", ")}`);
  let draw = (variant) => CONCEPTS[name].svg(variant);
  if (name === "bowlFlat" && (colorName || background)) {
    // 扁平的碗可以指定颜色（三组颜色表里的任何一个名字）和背景（white / cream 或 #RRGGBB）
    const colors = { ...BOWL_COLORS, ...BOWL_COLORS_MUTED, ...BOWL_COLORS_LIGHT };
    const color = colors[colorName ?? "oat"];
    if (!color) throw new Error(`没有叫 ${colorName} 的颜色，可选：${Object.keys(colors).join(", ")}`);
    const bg = { white: "#FFFFFF", cream: "#FBF6EF" }[background ?? "white"] ?? background;
    draw = (variant) => bowlFlatSvg(variant, color, bg);
  }
  if (paletteName) {
    if (!PALETTE_CONCEPTS[name]) throw new Error(`${name} 不支持换配色，只有 ${Object.keys(PALETTE_CONCEPTS).join(", ")} 支持`);
    if (!PALETTES[paletteName]) throw new Error(`没有叫 ${paletteName} 的配色，可选：${Object.keys(PALETTES).join(", ")}`);
    draw = (variant) => PALETTE_CONCEPTS[name](variant, PALETTES[paletteName]);
  }
  mkdirSync(APPICON_DIR, { recursive: true });
  const files = {};
  for (const variant of VARIANTS) {
    const file = `AppIcon-1024-${variant}.png`;
    let png = await renderPng(draw(variant));
    // App Store 要求 light 版不能带透明通道（哪怕全部不透明也会被拒），这里去掉；dark / tinted 版必须保留透明
    if (variant === "light") png = await sharp(png).removeAlpha().png().toBuffer();
    writeFileSync(join(APPICON_DIR, file), png);
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
  console.log(`installed ${name}${paletteName ? ` (${paletteName})` : ""} into ${APPICON_DIR}`);
}

const args = process.argv.slice(2);
if (args[0] === "--install") {
  const flag = (f) => { const i = args.indexOf(f); return i >= 0 ? args[i + 1] : undefined; };
  await install(args[1], flag("--palette"), flag("--color"), flag("--bg"));
} else if (args[0] === "--palettes") {
  await paletteSheet();
} else if (args[0] === "--bowl-colors") {
  await bowlColorSheet(args[1]);  // 不带参数 = 鲜艳的一组，muted = 低饱和度的一组
} else {
  // --only a,b,c 只渲染这几个方案（对比图也只放它们）
  const onlyIndex = args.indexOf("--only");
  const only = onlyIndex >= 0 ? args[onlyIndex + 1].split(",") : undefined;
  const rendered = await renderAll(only);
  await contactSheet(rendered);
}

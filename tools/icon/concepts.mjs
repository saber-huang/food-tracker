// App 图标的几个方案，每个方案是一个函数：传入 variant（light / dark / tinted）返回 1024×1024 的 SVG 文字。
// 苹果的规则（详见 .claude/skills/app-icon/SKILL.md）：
// - light：铺满整个正方形，不留透明、不自己切圆角（系统会切）
// - dark：只画图案，背景透明，系统会垫一层深色背景
// - tinted：只画灰白的图案，背景透明，系统按用户选的颜色染色
// 图案尽量放在中间 80% 的范围里，四角会被系统的圆角切掉一部分。
//
// lens（取景框餐盘）和 bowl（微笑的碗）两个方案支持换配色：PALETTES 里每套配色写明 light 和 dark 两种外观用的颜色，
// tinted 一律用白到灰。加一套配色就在 PALETTES 里加一项。

const SIZE = 1024;

/** 三种版本各用什么颜色：light 用设计色，dark 用亮一点的设计色，tinted 只用白到灰 */
function pick(variant, light, dark, tinted) {
  return { light, dark, tinted }[variant];
}

function svg(variant, gradientStops, body) {
  const background =
    variant === "light"
      ? `<defs><linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="${gradientStops[0]}"/><stop offset="1" stop-color="${gradientStops[1]}"/>
    </linearGradient></defs><rect width="${SIZE}" height="${SIZE}" fill="url(#bg)"/>`
      : "";
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${SIZE}" height="${SIZE}" viewBox="0 0 ${SIZE} ${SIZE}">
${background}
${body}
</svg>`;
}

/** 四角星（AI 的「闪光」），中心在 (x, y)，s 是半径 */
function sparkle(x, y, s, fill) {
  return `<path transform="translate(${x} ${y}) scale(${s})" fill="${fill}"
    d="M0,-1 C0.12,-0.12 0.12,-0.12 1,0 C0.12,0.12 0.12,0.12 0,1 C-0.12,0.12 -0.12,0.12 -1,0 C-0.12,-0.12 -0.12,-0.12 0,-1Z"/>`;
}

/** 「咬掉一口」：用遮罩在图形右上角挖一个圆 */
function biteMask(id, cx, cy, r) {
  return `<mask id="${id}"><rect width="${SIZE}" height="${SIZE}" fill="white"/><circle cx="${cx}" cy="${cy}" r="${r}" fill="black"/></mask>`;
}

// MARK: - 配色（给 lens 和 bowl 用）

/** tinted 外观固定用白到灰，系统会染色 */
const TINTED = {
  lens: { bracket: "#FFFFFF", plate: "#FFFFFF", ring: "#D0D0D0", food: "#A8A8A8" },
  bowl: { bowl: "#FFFFFF", smile: "#FFFFFF" },
};

export const PALETTES = {
  // 原版：紫色取景框、橙黄的碗（用户觉得不喜欢，留着对照）
  original: {
    title: "Original",
    lens: { bg: ["#7C6CFF", "#3A2DBB"], light: { bracket: "#FFFFFF", plate: "#FFFFFF", ring: "#E4E1FF", food: "#FF8F5E" }, dark: { bracket: "#D6D2FF", plate: "#F4F2FF", ring: "#CFC9FF", food: "#FFA57A" } },
    bowl: { bg: ["#FFC857", "#F4845F"], light: { bowl: "#FFFDF7", smile: "#FFFDF7" }, dark: { bowl: "#FFF3D6", smile: "#FFF3D6" } },
  },
  // 深蓝：沉稳、可信，暖色的食物点缀
  ink: {
    title: "Deep blue + warm accent",
    lens: { bg: ["#2F4F9E", "#131E42"], light: { bracket: "#FFFFFF", plate: "#FFFFFF", ring: "#DCE3FF", food: "#FFB84D" }, dark: { bracket: "#CBD5FF", plate: "#F4F6FF", ring: "#C7D0FF", food: "#FFB84D" } },
    bowl: { bg: ["#2F4F9E", "#131E42"], light: { bowl: "#FFFFFF", smile: "#FFB84D" }, dark: { bowl: "#F4F6FF", smile: "#FFB84D" } },
  },
  // 鼠尾草绿：健康、平静
  sage: {
    title: "Sage green",
    lens: { bg: ["#9BD3AE", "#3E8F68"], light: { bracket: "#FFFFFF", plate: "#FFFDF5", ring: "#E3F1E7", food: "#FF8A65" }, dark: { bracket: "#D8F0E0", plate: "#F1FBF4", ring: "#CDE9D6", food: "#FF9A76" } },
    bowl: { bg: ["#9BD3AE", "#3E8F68"], light: { bowl: "#FFFDF5", smile: "#FFFDF5" }, dark: { bowl: "#F1FBF4", smile: "#F1FBF4" } },
  },
  // 奶油底 + 深色图案：极简、温和，和别的 App 都不一样
  cream: {
    title: "Cream + dark ink",
    lens: { bg: ["#FFF7EA", "#FFE4C4"], light: { bracket: "#2E2A26", plate: "#2E2A26", ring: "#FFF7EA", food: "#E9673F" }, dark: { bracket: "#FFF1DE", plate: "#FFF1DE", ring: "#2E2A26", food: "#FF8C5A" } },
    bowl: { bg: ["#FFF7EA", "#FFE4C4"], light: { bowl: "#2E2A26", smile: "#E9673F" }, dark: { bowl: "#FFF1DE", smile: "#FF8C5A" } },
  },
  // 珊瑚红：有食欲、有活力
  coral: {
    title: "Coral",
    lens: { bg: ["#FF8B6A", "#E5423E"], light: { bracket: "#FFFFFF", plate: "#FFFFFF", ring: "#FFE1D6", food: "#FFD166" }, dark: { bracket: "#FFD3C6", plate: "#FFF4EF", ring: "#FFC9B8", food: "#FFD166" } },
    bowl: { bg: ["#FF8B6A", "#E5423E"], light: { bowl: "#FFFFFF", smile: "#FFFFFF" }, dark: { bowl: "#FFF4EF", smile: "#FFF4EF" } },
  },
  // 天蓝：清爽、干净
  sky: {
    title: "Sky blue",
    lens: { bg: ["#5BC8FA", "#1C7BD6"], light: { bracket: "#FFFFFF", plate: "#FFFFFF", ring: "#DCEFFF", food: "#FFB347" }, dark: { bracket: "#CFEAFF", plate: "#F3F9FF", ring: "#BFE2FF", food: "#FFB347" } },
    bowl: { bg: ["#5BC8FA", "#1C7BD6"], light: { bowl: "#FFFFFF", smile: "#FFFFFF" }, dark: { bowl: "#F3F9FF", smile: "#F3F9FF" } },
  },
  // 炭黑 + 青柠：现代、高对比
  charcoal: {
    title: "Charcoal + lime",
    lens: { bg: ["#3A3A3C", "#141414"], light: { bracket: "#F5F5F7", plate: "#F5F5F7", ring: "#E0E0E5", food: "#C6F135" }, dark: { bracket: "#F5F5F7", plate: "#F5F5F7", ring: "#E0E0E5", food: "#C6F135" } },
    bowl: { bg: ["#3A3A3C", "#141414"], light: { bowl: "#F5F5F7", smile: "#C6F135" }, dark: { bowl: "#F5F5F7", smile: "#C6F135" } },
  },
};

// MARK: - 可以换配色的两个方案

/** D. 取景框里的餐盘：相机 + 食物 */
export function lensSvg(v, palette = PALETTES.original) {
  const c = v === "tinted" ? TINTED.lens : palette.lens[v];
  return svg(v, palette.lens.bg, `
  <defs>${biteMask("bite", 740, 300, 105)}</defs>
  <g fill="none" stroke="${c.bracket}" stroke-width="40" stroke-linecap="round" stroke-linejoin="round">
    <path d="M300 172H212V300"/><path d="M724 172H812V300"/>
    <path d="M300 852H212V724"/><path d="M724 852H812V724"/>
  </g>
  <g mask="url(#bite)">
    <circle cx="512" cy="512" r="300" fill="${c.plate}"/>
    <circle cx="512" cy="512" r="232" fill="none" stroke="${c.ring}" stroke-width="16"/>
    <circle cx="512" cy="512" r="150" fill="${c.food}"/>
  </g>`);
}

/** E. 冒着热气的碗，热气弯成一个微笑：温和、不责备 */
export function bowlSvg(v, palette = PALETTES.original) {
  const c = v === "tinted" ? TINTED.bowl : palette.bowl[v];
  return svg(v, palette.bowl.bg, `
  <defs>${biteMask("bite", 838, 450, 92)}</defs>
  <path fill="none" stroke="${c.smile}" stroke-width="58" stroke-linecap="round" d="M388 292Q512 408 636 292"/>
  <g mask="url(#bite)">
    <path fill="${c.bowl}" d="M202 470H822A310 310 0 0 1 512 780A310 310 0 0 1 202 470Z"/>
    <rect x="182" y="436" width="660" height="64" rx="32" fill="${c.bowl}"/>
  </g>`);
}

/** 支持换配色的方案：名字 → 画图函数 */
export const PALETTE_CONCEPTS = { lens: lensSvg, bowl: bowlSvg };

// MARK: - 全部方案

export const CONCEPTS = {
  // A. 被咬了一口的爱心：Kindbite 的字面意思，温和 + 食物
  heart: {
    title: "Heart with a bite",
    svg(v) {
      const heart = pick(v, "#FFF7F0", "#FF8A80", "#FFFFFF");
      const crumb = pick(v, "#FFF7F0", "#FFB4A8", "#DADADA");
      return svg(v, ["#FFA36C", "#FF5C6C"], `
  <defs>${biteMask("bite", 805, 285, 100)}</defs>
  <path mask="url(#bite)" fill="${heart}"
    d="M512 880C300 720 160 600 160 420C160 300 250 220 360 220C430 220 480 260 512 310C544 260 594 220 664 220C774 220 864 300 864 420C864 600 724 720 512 880Z"/>
  <circle cx="905" cy="190" r="16" fill="${crumb}"/><circle cx="945" cy="248" r="10" fill="${crumb}"/>`);
    },
  },

  // B. 被咬了一口的爱心 + 闪光：Kindbite（温和的一口）加上 AI 识别的闪光
  heartSparkle: {
    title: "Heart with a bite and sparkle",
    svg(v) {
      const heart = pick(v, "#FFF7F0", "#FF8A80", "#FFFFFF");
      const spark = pick(v, "#FFFFFF", "#FFD3C4", "#E0E0E0");
      return svg(v, ["#FF9A7A", "#FF5470"], `
  <defs>${biteMask("bite", 805, 285, 100)}</defs>
  <path mask="url(#bite)" fill="${heart}"
    d="M512 880C300 720 160 600 160 420C160 300 250 220 360 220C430 220 480 260 512 310C544 260 594 220 664 220C774 220 864 300 864 420C864 600 724 720 512 880Z"/>
  ${sparkle(896, 196, 46, spark)}
  ${sparkle(944, 274, 20, spark)}`);
    },
  },

  // C. 被咬了一口的餐盘 + 闪光：拍照识别、AI
  plate: {
    title: "Plate with a bite and sparkle",
    svg(v) {
      const plate = pick(v, "#FFF5E1", "#FFF1D6", "#FFFFFF");
      const well = pick(v, "#F6DFB8", "#E8D0A8", "#D6D6D6");
      const spark = pick(v, "#FFFFFF", "#FFE9A8", "#FFFFFF");
      return svg(v, ["#3BB8AB", "#1C7C78"], `
  <defs>${biteMask("bite", 770, 330, 120)}</defs>
  <g mask="url(#bite)">
    <circle cx="512" cy="530" r="330" fill="${plate}"/>
    <circle cx="512" cy="530" r="235" fill="${well}"/>
  </g>
  ${sparkle(852, 200, 48, spark)}
  ${sparkle(920, 285, 24, spark)}`);
    },
  },

  // D. 取景框里的餐盘（默认配色，换配色见 PALETTES）
  lens: { title: "Viewfinder around a plate", svg: (v) => lensSvg(v) },

  // E. 微笑的碗（默认配色，换配色见 PALETTES）
  bowl: { title: "Smiling bowl", svg: (v) => bowlSvg(v) },
};

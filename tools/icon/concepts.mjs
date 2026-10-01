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


// MARK: - 扁平、极简的方案（参考用户喜欢的图标：Gmail、不背单词、Peloton、Apple 健身、FitHub）
// 共同点：纯白或纯黑的底，没有渐变，中间一个粗壮的符号。

/** 圆弧路径：角度从正上方开始顺时针算（度） */
function arc(cx, cy, r, a0, a1) {
  const rad = (a) => ((a - 90) * Math.PI) / 180;
  const x0 = cx + r * Math.cos(rad(a0)), y0 = cy + r * Math.sin(rad(a0));
  const x1 = cx + r * Math.cos(rad(a1)), y1 = cy + r * Math.sin(rad(a1));
  return `M${x0.toFixed(1)} ${y0.toFixed(1)}A${r} ${r} 0 ${a1 - a0 > 180 ? 1 : 0} 1 ${x1.toFixed(1)} ${y1.toFixed(1)}`;
}

/** 字母 K：竖笔一种颜色，两条斜笔另一种颜色，上面那条斜笔的外侧被咬了一口 */
function letterK(stem, arms, biteId) {
  return `
  <defs>${biteMask(biteId, 560, 262, 74)}</defs>
  <g fill="none" stroke-width="150" stroke-linecap="round" mask="url(#${biteId})">
    <path stroke="${arms}" d="M400 512L700 250"/>
    <path stroke="${arms}" d="M400 512L700 774"/>
  </g>
  <path fill="none" stroke="${stem}" stroke-width="150" stroke-linecap="round" d="M370 240V784"/>`;
}

const HEART_PATH = "M512 880C300 720 160 600 160 420C160 300 250 220 360 220C430 220 480 260 512 310C544 260 594 220 664 220C774 220 864 300 864 420C864 600 724 720 512 880Z";

const FLAT = {
  // F. 白底 + 两色的 K，被咬了一口（Gmail、不背单词的思路：干净的底，一个字母做标志）
  kWhite: {
    title: "K on white, two warm colors",
    svg(v) {
      const stem = pick(v, "#F4553B", "#FF7A5C", "#FFFFFF");
      const arms = pick(v, "#FF9A3C", "#FFB25C", "#C8C8C8");
      return svg(v, ["#FFFFFF", "#FFFFFF"], letterK(stem, arms, "biteK"));
    },
  },
  // G. 黑底 + 白色的 K，一点橙色闪光（Peloton 的思路）
  kBlack: {
    title: "K on black with a sparkle",
    svg(v) {
      const k = pick(v, "#FFFFFF", "#FFFFFF", "#FFFFFF");
      const spark = pick(v, "#FF9A3C", "#FFB25C", "#C8C8C8");
      return svg(v, ["#0B0B0C", "#0B0B0C"], letterK(k, k, "biteK") + sparkle(790, 205, 44, spark));
    },
  },
  // H. 白底 + 橙色圆章，里面一颗被咬了一口的白色爱心（不背单词的布局）
  badge: {
    title: "Orange badge with a bitten heart",
    svg(v) {
      const badge = pick(v, "#FF6A3D", "#FF7A50", "#FFFFFF");
      const heart = pick(v, "#FFFFFF", "#FFFFFF", "#8E8E93");
      return svg(v, ["#FFFFFF", "#FFFFFF"], `
  <defs>${biteMask("biteH", 805, 285, 100)}</defs>
  <circle cx="512" cy="512" r="400" fill="${badge}"/>
  <g transform="translate(512 528) scale(0.56) translate(-512 -550)">
    <path mask="url(#biteH)" fill="${heart}" d="${HEART_PATH}"/>
  </g>`);
    },
  },
  // I. 黑底 + 三段颜色的圆环（蛋白质蓝、碳水橙、脂肪粉，就是 App 里用的三种颜色），右上角缺一口
  ring: {
    title: "Three-color ring with a bite",
    svg(v) {
      const protein = pick(v, "#4DA3FF", "#5FAEFF", "#FFFFFF");
      const carbs = pick(v, "#FF9F1C", "#FFAE3D", "#C8C8C8");
      const fat = pick(v, "#FF4D6D", "#FF6683", "#9A9A9A");
      const stroke = `fill="none" stroke-width="120" stroke-linecap="butt"`;
      return svg(v, ["#0B0B0C", "#0B0B0C"], `
  <path ${stroke} stroke="${protein}" d="${arc(512, 512, 300, 76, 190)}"/>
  <path ${stroke} stroke="${carbs}" d="${arc(512, 512, 300, 196, 310)}"/>
  <path ${stroke} stroke="${fat}" d="${arc(512, 512, 300, 316, 384)}"/>`);
    },
  },
  // J. 浅底 + 扁平的碗和笑脸（FitHub 的思路：浅底，一个简单的物件）。颜色见 BOWL_COLORS，默认橙色
  bowlFlat: {
    title: "Flat bowl on a light background",
    svg(v) {
      return bowlFlatSvg(v, BOWL_COLORS.orange);
    },
  },
};

// MARK: - 扁平的碗：可以换颜色

/** 每种颜色：bg 背景，bowl 碗身，rim 碗沿（深一点），smile 笑脸，shadow 碗下面的浅影子；dark 是深色外观用的亮一点的颜色 */
export const BOWL_COLORS = {
  orange: { title: "Orange (current)", bg: "#FBF6EF", bowl: "#FF7A3D", rim: "#E8622A", smile: "#FF7A3D", shadow: "#EFE5D6", dark: { bowl: "#FF8A55", rim: "#F07040", smile: "#FF8A55" } },
  teal: { title: "Teal", bg: "#FFFFFF", bowl: "#2BB3A3", rim: "#1F8F83", smile: "#2BB3A3", shadow: "#E6F3F1", dark: { bowl: "#3CC6B5", rim: "#2AA697", smile: "#3CC6B5" } },
  sage: { title: "Sage green", bg: "#FFFFFF", bowl: "#6FAE6E", rim: "#558E54", smile: "#6FAE6E", shadow: "#E9F1E8", dark: { bowl: "#84C283", rim: "#6AA669", smile: "#84C283" } },
  navy: { title: "Navy", bg: "#FFFFFF", bowl: "#2F4F9E", rim: "#22397A", smile: "#2F4F9E", shadow: "#E8ECF5", dark: { bowl: "#5B7BD6", rim: "#4463B8", smile: "#5B7BD6" } },
  charcoal: { title: "Charcoal (like 不背单词)", bg: "#FFFFFF", bowl: "#2E2A26", rim: "#161311", smile: "#2E2A26", shadow: "#ECEAE7", dark: { bowl: "#F2EFEA", rim: "#D9D4CC", smile: "#F2EFEA" } },
  brick: { title: "Brick red", bg: "#FFFFFF", bowl: "#C94F3D", rim: "#A63D2E", smile: "#C94F3D", shadow: "#F5E8E5", dark: { bowl: "#E0664F", rim: "#C9503C", smile: "#E0664F" } },
  rose: { title: "Rose", bg: "#FFFFFF", bowl: "#F06A8A", rim: "#D6547A", smile: "#F06A8A", shadow: "#FBE9EE", dark: { bowl: "#FF7FA0", rim: "#E86A8E", smile: "#FF7FA0" } },
  sky: { title: "Sky blue", bg: "#FFFFFF", bowl: "#3F97E0", rim: "#2E7BC0", smile: "#3F97E0", shadow: "#E6F0F9", dark: { bowl: "#5AAEF5", rim: "#3F97E0", smile: "#5AAEF5" } },
  plum: { title: "Plum", bg: "#FFFFFF", bowl: "#7B4E96", rim: "#5F3A78", smile: "#7B4E96", shadow: "#EFE9F3", dark: { bowl: "#9B6DB8", rim: "#7B4E96", smile: "#9B6DB8" } },
  latte: { title: "Latte brown", bg: "#FFFFFF", bowl: "#A6754C", rim: "#875C3A", smile: "#A6754C", shadow: "#F1EBE5", dark: { bowl: "#C08E62", rim: "#A6754C", smile: "#C08E62" } },
};

/** 低饱和度的一组：灰一点、柔和一点，适合「温和」的定位 */
export const BOWL_COLORS_MUTED = {
  dustyTeal: { title: "Dusty teal", bg: "#FFFFFF", bowl: "#6FA8A3", rim: "#588E89", smile: "#6FA8A3", shadow: "#ECF1F0", dark: { bowl: "#86BDB8", rim: "#6FA8A3", smile: "#86BDB8" } },
  eucalyptus: { title: "Grey green", bg: "#FFFFFF", bowl: "#8CAE98", rim: "#72957E", smile: "#8CAE98", shadow: "#ECF1EE", dark: { bowl: "#A3C3AE", rim: "#8CAE98", smile: "#A3C3AE" } },
  slate: { title: "Grey blue", bg: "#FFFFFF", bowl: "#7A8FA6", rim: "#62778E", smile: "#7A8FA6", shadow: "#ECEFF2", dark: { bowl: "#95A9BF", rim: "#7A8FA6", smile: "#95A9BF" } },
  dustyRose: { title: "Dusty rose", bg: "#FFFFFF", bowl: "#C78F8D", rim: "#AD7775", smile: "#C78F8D", shadow: "#F3ECEC", dark: { bowl: "#D8A5A3", rim: "#C78F8D", smile: "#D8A5A3" } },
  clay: { title: "Clay", bg: "#FFFFFF", bowl: "#C0876B", rim: "#A46F55", smile: "#C0876B", shadow: "#F3EDE9", dark: { bowl: "#D29E83", rim: "#C0876B", smile: "#D29E83" } },
  mushroom: { title: "Mushroom", bg: "#FFFFFF", bowl: "#A79A8D", rim: "#8C8073", smile: "#A79A8D", shadow: "#EFEDEA", dark: { bowl: "#BDB1A5", rim: "#A79A8D", smile: "#BDB1A5" } },
  olive: { title: "Olive", bg: "#FFFFFF", bowl: "#98A06E", rim: "#7E8658", smile: "#98A06E", shadow: "#EFF0EA", dark: { bowl: "#AEB586", rim: "#98A06E", smile: "#AEB586" } },
  sand: { title: "Sand", bg: "#FFFFFF", bowl: "#CBB07E", rim: "#B19664", smile: "#CBB07E", shadow: "#F3F0E9", dark: { bowl: "#DCC496", rim: "#CBB07E", smile: "#DCC496" } },
  lavender: { title: "Grey lavender", bg: "#FFFFFF", bowl: "#9C93B0", rim: "#847A99", smile: "#9C93B0", shadow: "#EFEEF2", dark: { bowl: "#B3ABC4", rim: "#9C93B0", smile: "#B3ABC4" } },
  stone: { title: "Warm grey", bg: "#FFFFFF", bowl: "#8E8984", rim: "#746F6A", smile: "#8E8984", shadow: "#ECEBEA", dark: { bowl: "#A8A39E", rim: "#8E8984", smile: "#A8A39E" } },
};

/** 浅米色的一组（用户喜欢炭黑方案在深色外观下那只米白色的碗），从极浅到中等深浅排列。
 *  浅色碗放在浅色底上对比度低，所以碗沿都比碗身深一档，影子也稍微深一点，帮它「立」在底上 */
export const BOWL_COLORS_LIGHT = {
  ivory: { title: "Ivory (same as the dark-mode bowl)", bg: "#FFFFFF", bowl: "#F2EFEA", rim: "#D9D4CC", smile: "#F2EFEA", shadow: "#E6E1DA", dark: { bowl: "#F2EFEA", rim: "#D9D4CC", smile: "#F2EFEA" } },
  bone: { title: "Bone", bg: "#FFFFFF", bowl: "#ECE6DA", rim: "#CFC6B6", smile: "#ECE6DA", shadow: "#E3DDD3", dark: { bowl: "#F0EAE0", rim: "#D6CEC0", smile: "#F0EAE0" } },
  linen: { title: "Linen", bg: "#FFFFFF", bowl: "#E5DCCF", rim: "#C6BAA7", smile: "#E5DCCF", shadow: "#E0D9CF", dark: { bowl: "#ECE4D9", rim: "#CFC3B2", smile: "#ECE4D9" } },
  oat: { title: "Oat", bg: "#FFFFFF", bowl: "#DED2BF", rim: "#BDAD95", smile: "#DED2BF", shadow: "#E2DBD0", dark: { bowl: "#E7DDCC", rim: "#C8B9A2", smile: "#E7DDCC" } },
  greige: { title: "Greige", bg: "#FFFFFF", bowl: "#D6CEC3", rim: "#B3A89A", smile: "#D6CEC3", shadow: "#E3DFD9", dark: { bowl: "#E0D9CF", rim: "#BDB2A5", smile: "#E0D9CF" } },
  taupe: { title: "Pale taupe", bg: "#FFFFFF", bowl: "#CBBFB1", rim: "#A79989", smile: "#CBBFB1", shadow: "#E6E1DB", dark: { bowl: "#D8CDBF", rim: "#B4A696", smile: "#D8CDBF" } },
  almond: { title: "Almond", bg: "#FFFFFF", bowl: "#D9C7B2", rim: "#B89F84", smile: "#D9C7B2", shadow: "#E6DFD6", dark: { bowl: "#E2D2BF", rim: "#C2AB92", smile: "#E2D2BF" } },
  pebble: { title: "Light warm grey", bg: "#FFFFFF", bowl: "#CFCBC5", rim: "#A9A49C", smile: "#CFCBC5", shadow: "#E4E2DE", dark: { bowl: "#DAD6D0", rim: "#B4AFA7", smile: "#DAD6D0" } },
};

/** 碗的画法（bowlFlat 和换颜色的对比图共用）。background 可以覆盖颜色表里的背景，用来比较纯白和米白 */
export function bowlFlatSvg(v, c, background = c.bg) {
  const bowl = pick(v, c.bowl, c.dark.bowl, "#FFFFFF");
  const rim = pick(v, c.rim, c.dark.rim, "#D0D0D0");
  const smile = pick(v, c.smile, c.dark.smile, "#FFFFFF");
  const shadow = v === "light" ? `<ellipse cx="512" cy="812" rx="250" ry="26" fill="${c.shadow}"/>` : "";
  return svg(v, [background, background], `
  <defs>${biteMask("biteJ", 838, 450, 92)}</defs>
  ${shadow}
  <path fill="none" stroke="${smile}" stroke-width="58" stroke-linecap="round" d="M388 292Q512 408 636 292"/>
  <g mask="url(#biteJ)">
    <path fill="${bowl}" d="M202 470H822A310 310 0 0 1 512 780A310 310 0 0 1 202 470Z"/>
    <rect x="182" y="436" width="660" height="64" rx="32" fill="${rim}"/>
  </g>`);
}

// MARK: - 全部方案（扁平的新方案排在前面）

export const CONCEPTS = {
  ...FLAT,
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

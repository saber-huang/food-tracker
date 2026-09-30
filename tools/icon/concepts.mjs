// App 图标的几个方案，每个方案是一个函数：传入 variant（light / dark / tinted）返回 1024×1024 的 SVG 文字。
// 苹果的规则（详见 .claude/skills/app-icon/SKILL.md）：
// - light：铺满整个正方形，不留透明、不自己切圆角（系统会切）
// - dark：只画图案，背景透明，系统会垫一层深色背景
// - tinted：只画灰白的图案，背景透明，系统按用户选的颜色染色
// 图案尽量放在中间 80% 的范围里，四角会被系统的圆角切掉一部分。

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

  // E. 被咬了一口的爱心 + 闪光：A 和 B 的合体，Kindbite（温和的一口）加上 AI 识别的闪光
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

  // B. 被咬了一口的餐盘 + 闪光：拍照识别、AI
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

  // C. 取景框里的餐盘：相机 + 食物
  lens: {
    title: "Viewfinder around a plate",
    svg(v) {
      const bracket = pick(v, "#FFFFFF", "#D6D2FF", "#FFFFFF");
      const plate = pick(v, "#FFFFFF", "#F4F2FF", "#FFFFFF");
      const ring = pick(v, "#E4E1FF", "#CFC9FF", "#D0D0D0");
      const food = pick(v, "#FF8F5E", "#FFA57A", "#A8A8A8");
      return svg(v, ["#7C6CFF", "#3A2DBB"], `
  <defs>${biteMask("bite", 740, 300, 105)}</defs>
  <g fill="none" stroke="${bracket}" stroke-width="40" stroke-linecap="round" stroke-linejoin="round">
    <path d="M300 172H212V300"/><path d="M724 172H812V300"/>
    <path d="M300 852H212V724"/><path d="M724 852H812V724"/>
  </g>
  <g mask="url(#bite)">
    <circle cx="512" cy="512" r="300" fill="${plate}"/>
    <circle cx="512" cy="512" r="232" fill="none" stroke="${ring}" stroke-width="16"/>
    <circle cx="512" cy="512" r="150" fill="${food}"/>
  </g>`);
    },
  },

  // D. 冒着热气的碗，热气弯成一个微笑：温和、不责备
  bowl: {
    title: "Smiling bowl",
    svg(v) {
      const bowl = pick(v, "#FFFDF7", "#FFF3D6", "#FFFFFF");
      const smile = pick(v, "#FFFDF7", "#FFF3D6", "#FFFFFF");
      return svg(v, ["#FFC857", "#F4845F"], `
  <defs>${biteMask("bite", 838, 450, 92)}</defs>
  <path fill="none" stroke="${smile}" stroke-width="58" stroke-linecap="round" d="M388 292Q512 408 636 292"/>
  <g mask="url(#bite)">
    <path fill="${bowl}" d="M202 470H822A310 310 0 0 1 512 780A310 310 0 0 1 202 470Z"/>
    <rect x="182" y="436" width="660" height="64" rx="32" fill="${bowl}"/>
  </g>`);
    },
  },
};

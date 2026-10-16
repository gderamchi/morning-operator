// Small pixel helpers shared by the explorations. Everything is drawn on a tiny
// canvas and scaled up with image-rendering: pixelated, so the "pixels" are real.
(function () {
  const BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]];

  function hex(c) {
    const m = c.replace('#', '');
    return [parseInt(m.slice(0, 2), 16), parseInt(m.slice(2, 4), 16), parseInt(m.slice(4, 6), 16)];
  }
  function mix(a, b, t) { return a.map((v, i) => v + (b[i] - v) * t); }

  // Vertical gradient through `stops` (array of hex), ordered-dithered into
  // exactly those colours. `horizon` (0..1) pushes the gradient down so the
  // sky can "rise". Writes into canvas c with cols×rows cells.
  function ditherSky(c, cols, rows, stops, opts = {}) {
    const { horizon = 1, levels = stops.length, bias = 0 } = opts;
    c.width = cols; c.height = rows;
    const ctx = c.getContext('2d');
    const img = ctx.createImageData(cols, rows);
    const pal = stops.map(hex);
    for (let y = 0; y < rows; y++) {
      for (let x = 0; x < cols; x++) {
        let t = (y / (rows - 1)) / horizon + bias; // 0 top .. 1 bottom
        t = Math.max(0, Math.min(0.9999, t));
        const pos = t * (pal.length - 1);
        const i = Math.floor(pos);
        const frac = pos - i;
        const th = (BAYER[y % 4][x % 4] + 0.5) / 16;
        const col = frac > th ? pal[Math.min(i + 1, pal.length - 1)] : pal[i];
        const o = (y * cols + x) * 4;
        img.data[o] = col[0]; img.data[o + 1] = col[1]; img.data[o + 2] = col[2]; img.data[o + 3] = 255;
      }
    }
    ctx.putImageData(img, 0, 0);
  }

  // A disc drawn as pixels, optionally only its top `fill` fraction (rows filled
  // from the top down), so it can rise pixel-row by pixel-row.
  function pixelSun(c, size, color, opts = {}) {
    const { fill = 1, bg = null, rays = false, rayColor = color, dim = null } = opts;
    const n = size; c.width = n; c.height = n;
    const ctx = c.getContext('2d');
    if (bg) { ctx.fillStyle = bg; ctx.fillRect(0, 0, n, n); }
    const r = n / 2 - (rays ? 2 : 0.5), cx = n / 2, cy = n / 2;
    const filledRows = Math.round(n * fill);
    for (let y = 0; y < n; y++) {
      for (let x = 0; x < n; x++) {
        const d = Math.hypot(x + 0.5 - cx, y + 0.5 - cy);
        if (d <= r) {
          if (y < filledRows) { ctx.fillStyle = color; ctx.fillRect(x, y, 1, 1); }
          else if (dim) { ctx.fillStyle = dim; ctx.fillRect(x, y, 1, 1); }
        }
      }
    }
    if (rays) {
      ctx.fillStyle = rayColor;
      const pts = [[cx - 0.5, 0], [cx - 0.5, n - 1], [0, cy - 0.5], [n - 1, cy - 0.5]];
      pts.forEach(([x, y]) => ctx.fillRect(Math.floor(x), Math.floor(y), 1, 1));
    }
  }

  // Draw a half sun (top half) rising over a horizon row of a cols×rows field.
  function horizonSun(c, cols, rows, sky, sun, ground, rise) {
    c.width = cols; c.height = rows;
    const ctx = c.getContext('2d');
    ctx.fillStyle = sky; ctx.fillRect(0, 0, cols, rows);
    const hy = Math.round(rows * 0.62);
    const r = Math.round(cols * 0.22);
    const cy = hy + r - Math.round(r * 2 * rise); // rise 0 hidden .. 1 full disc above horizon
    const cx = Math.floor(cols / 2);
    ctx.fillStyle = sun;
    for (let y = 0; y < hy; y++) for (let x = 0; x < cols; x++) {
      if (Math.hypot(x + 0.5 - cx, y + 0.5 - cy) <= r) ctx.fillRect(x, y, 1, 1);
    }
    ctx.fillStyle = ground; ctx.fillRect(0, hy, cols, rows - hy);
  }

  // 1-bit ordered dither of a vertical gradient: returns pattern of two colours.
  function dither1bit(c, cols, rows, dark, light, from = 0, to = 1) {
    c.width = cols; c.height = rows;
    const ctx = c.getContext('2d');
    for (let y = 0; y < rows; y++) for (let x = 0; x < cols; x++) {
      const t = from + (to - from) * (y / (rows - 1));
      const th = (BAYER[y % 4][x % 4] + 0.5) / 16;
      ctx.fillStyle = t > th ? dark : light;
      ctx.fillRect(x, y, 1, 1);
    }
  }

  // 5×7 dot-matrix glyphs for digits, colon and a few letters.
  const FONT = {
    '0': ['01110', '10001', '10011', '10101', '11001', '10001', '01110'],
    '1': ['00100', '01100', '00100', '00100', '00100', '00100', '01110'],
    '2': ['01110', '10001', '00001', '00010', '00100', '01000', '11111'],
    '3': ['11111', '00010', '00100', '00010', '00001', '10001', '01110'],
    '4': ['00010', '00110', '01010', '10010', '11111', '00010', '00010'],
    '5': ['11111', '10000', '11110', '00001', '00001', '10001', '01110'],
    '6': ['00110', '01000', '10000', '11110', '10001', '10001', '01110'],
    '7': ['11111', '00001', '00010', '00100', '01000', '01000', '01000'],
    '8': ['01110', '10001', '10001', '01110', '10001', '10001', '01110'],
    '9': ['01110', '10001', '10001', '01111', '00001', '00010', '01100'],
    ':': ['00000', '00100', '00100', '00000', '00100', '00100', '00000'],
    ' ': ['00000', '00000', '00000', '00000', '00000', '00000', '00000'],
  };
  function dotMatrix(c, text, on, off, dot = 1, gap = 1, pad = 1) {
    const w = text.length * (5 * (dot + gap) + gap) + pad * 2, h = 7 * (dot + gap) + pad * 2;
    c.width = w; c.height = h;
    const ctx = c.getContext('2d');
    if (off) { ctx.fillStyle = off; }
    let ox = pad;
    for (const ch of text) {
      const g = FONT[ch] || FONT[' '];
      for (let y = 0; y < 7; y++) for (let x = 0; x < 5; x++) {
        ctx.fillStyle = g[y][x] === '1' ? on : (off || 'transparent');
        if (g[y][x] === '1' || off) ctx.fillRect(ox + x * (dot + gap), pad + y * (dot + gap), dot, dot);
      }
      ox += 5 * (dot + gap) + gap;
    }
  }

  window.pix = { ditherSky, pixelSun, horizonSun, dither1bit, dotMatrix, hex, mix };
})();

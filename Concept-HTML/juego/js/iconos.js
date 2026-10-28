/* Codemageddon · iconos de la paleta de código.
 * Versión vectorial y simplificada de la hoja «Iconos metálicos de programación robótica».
 * En reposo, todo el icono es grabado (una sola tinta oscura sobre la placa).
 * Al pasar el cursor, cada parte toma su color: t1/s1 → c1, t2/s2 → c2, t3/s3 → c3.
 * Clases: t = relleno, s = trazo. Rejilla de 32 × 32. */
(() => {
  "use strict";
  const svg = (cuerpo) => `<svg viewBox="0 0 32 32" aria-hidden="true" focusable="false">${cuerpo}</svg>`;
  const flechasCiclo = `
    <path class="s1" stroke-width="2.6" stroke-linecap="round" d="M6.2 13.5A10.2 10.2 0 0 1 22.6 7.6"/>
    <path class="t1" d="M26.2 4.4l.3 7.2-7-1.4z"/>
    <path class="s1" stroke-width="2.6" stroke-linecap="round" d="M25.8 18.5A10.2 10.2 0 0 1 9.4 24.4"/>
    <path class="t1" d="M5.8 27.6l-.3-7.2 7 1.4z"/>`;
  const cohete = `
    <path class="t1" d="M16 2.5c3.2 2.6 4.3 6.3 4.3 10.4v8.3h-8.6v-8.3c0-4.1 1.1-7.8 4.3-10.4z"/>
    <path class="t2" d="M11.7 15.5l-3.9 4.4v4.6l3.9-2.4zM20.3 15.5l3.9 4.4v4.6l-3.9-2.4z"/>
    <path class="t3" d="M13.2 22.4h5.6L16 30z"/>`;

  window.ICONOS = {
    comentar: { c1: "#6FA0FF", c2: "#E3ECFF", svg: svg(`
      <path class="s1" stroke-width="2.4" stroke-linejoin="round" d="M5.5 5h21a2.5 2.5 0 0 1 2.5 2.5v12.5a2.5 2.5 0 0 1-2.5 2.5H14l-6.5 5v-5H5.5A2.5 2.5 0 0 1 3 20V7.5A2.5 2.5 0 0 1 5.5 5z"/>
      <path class="t2" d="M10.6 18.8l4.2-10.6h2.8l-4.2 10.6zM16.4 18.8l4.2-10.6h2.8l-4.2 10.6z"/>`) },

    whileTrue: { c1: "#4D9BFF", c2: "#9CC8FF", svg: svg(`${flechasCiclo}
      <path class="s2" stroke-width="2.4" stroke-linejoin="round" d="M10.4 16c0-2.1 1.4-3.1 2.9-3.1 2.9 0 4.5 6.2 7.4 6.2 1.5 0 2.9-1 2.9-3.1s-1.4-3.1-2.9-3.1c-2.9 0-4.5 6.2-7.4 6.2-1.5 0-2.9-1-2.9-3.1z"/>`) },

    mientras: { c1: "#4CC38A", c2: "#F2C14E", svg: svg(`${flechasCiclo}
      <path class="s2" stroke-width="2" stroke-linejoin="round" d="M16 9.6l6.4 6.4-6.4 6.4-6.4-6.4z"/>
      <text class="t2 letra" x="16" y="19.2" font-size="8.5" text-anchor="middle">?</text>`) },

    siNo: { c1: "#F2C14E", c2: "#4CC38A", c3: "#F0645A", svg: svg(`
      <path class="s1" stroke-width="2" stroke-linejoin="round" d="M16 2.2l5.6 5.6-5.6 5.6-5.6-5.6z"/>
      <text class="t1 letra" x="16" y="10.4" font-size="7" text-anchor="middle">?</text>
      <path class="s1" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" d="M10.4 7.8H7.4v8.4M21.6 7.8h3v8.4"/>
      <rect class="s2" stroke-width="2" x="2.4" y="17.6" width="10" height="10" rx="2"/>
      <path class="s2" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" d="M4.9 22.6l2.1 2.1 3.2-4"/>
      <rect class="s3" stroke-width="2" x="19.6" y="17.6" width="10" height="10" rx="2"/>
      <path class="s3" stroke-width="2.2" stroke-linecap="round" d="M22.4 20.4l4.4 4.4M26.8 20.4l-4.4 4.4"/>`) },

    plan: { c1: "#F2C14E", c2: "#E9EEF2", svg: svg(`
      <text class="t1 letra" x="15.6" y="21.4" font-size="16" text-anchor="middle" letter-spacing="-1.5">??</text>
      <path class="s2" stroke-width="2" stroke-linecap="round" d="M5 26.5h22"/>`) },

    esperar: { c1: "#D9B45A", c2: "#F7C866", svg: svg(`
      <rect class="t1" x="6.5" y="2.6" width="19" height="3.2" rx="1.2"/>
      <rect class="t1" x="6.5" y="26.2" width="19" height="3.2" rx="1.2"/>
      <path class="s1" stroke-width="2" stroke-linejoin="round" d="M9.8 5.8v3.4c0 3.2 6.2 4.8 6.2 6.8s-6.2 3.6-6.2 6.8v3.4M22.2 5.8v3.4c0 3.2-6.2 4.8-6.2 6.8s6.2 3.6 6.2 6.8v3.4"/>
      <path class="t2" d="M12.4 9.6h7.2c-.8 1.7-3.6 3-3.6 4.6 0-1.6-2.8-2.9-3.6-4.6zM11.6 25.6c.5-2.6 4.4-4 4.4-6.6 0 2.6 3.9 4 4.4 6.6z"/>`) },

    variable: { c1: "#B7C2CC", c2: "#F2C14E", svg: svg(`
      <path class="s1" stroke-width="2.2" stroke-linejoin="round" d="M4.6 11.2h22.8v16.2H4.6zM4.6 11.2l3.2-5.4h16.4l3.2 5.4"/>
      <rect class="s2" stroke-width="1.8" x="9.6" y="14.6" width="12.8" height="9.4" rx="1.2"/>
      <path class="s2" stroke-width="2.2" stroke-linecap="round" d="M13.2 16.8l5.6 5M18.8 16.8l-5.6 5"/>`) },

    apuntar: { c1: "#F2C14E", c2: "#F0645A", svg: svg(`
      <circle class="s1" stroke-width="2.4" cx="16" cy="16" r="9"/>
      <path class="s1" stroke-width="2.4" stroke-linecap="round" d="M16 2.4v6.2M16 23.4v6.2M2.4 16h6.2M23.4 16h6.2"/>
      <circle class="t2" cx="16" cy="16" r="3.2"/>`) },

    disparo: { c1: "#D5DDE4", c2: "#F0645A", c3: "#F7A93B", svg: svg(`<g transform="rotate(45 16 16)">${cohete}</g>`) },

    rafaga: { c1: "#D5DDE4", c2: "#F0645A", c3: "#F7A93B", svg: svg(
      [[9.5, 11.5], [16, 18], [22.5, 24.5]].map(([x, y]) => `<g transform="translate(${x} ${y}) rotate(45) scale(.52) translate(-16 -16)">${cohete}</g>`).join("")) },

    detener: { c1: "#F0645A", c2: "#F1F4F6", svg: svg(`
      <path class="s1" stroke-width="2.2" stroke-linejoin="round" d="M11.2 2.6h9.6l8.6 8.6v9.6l-8.6 8.6h-9.6l-8.6-8.6v-9.6z"/>
      <rect class="t2" x="11" y="15" width="10.4" height="9.4" rx="3.4"/>
      <rect class="t2" x="11" y="9.4" width="2.3" height="8" rx="1.15"/>
      <rect class="t2" x="13.7" y="7.8" width="2.3" height="9" rx="1.15"/>
      <rect class="t2" x="16.4" y="7.8" width="2.3" height="9" rx="1.15"/>
      <rect class="t2" x="19.1" y="9.4" width="2.3" height="8" rx="1.15"/>
      <rect class="t2" x="20.4" y="14.6" width="2.3" height="6.4" rx="1.15" transform="rotate(32 21.5 17.8)"/>`) },

    sensor: { c1: "#B7C2CC", c2: "#39C5CF", svg: svg(`
      <circle class="t1" cx="11" cy="13.5" r="5.2"/>
      <rect class="t1" x="9.9" y="17.5" width="2.2" height="9"/>
      <rect class="t1" x="5.4" y="26.2" width="11.2" height="2.8" rx="1"/>
      <path class="s2" stroke-width="2.2" stroke-linecap="round" d="M18.6 9.6a5.6 5.6 0 0 1 0 7.8M22 6.6a10 10 0 0 1 0 13.8M25.4 3.6a14.4 14.4 0 0 1 0 19.8"/>`) },

    aviso: { c1: "#E0AE4A", c2: "#FFF4D6", svg: svg(`
      <path class="s1" stroke-width="2.4" stroke-linejoin="round" d="M16 3.6l13 23.2H3z"/>
      <rect class="t2" x="14.8" y="11" width="2.4" height="9" rx="1.2"/>
      <circle class="t2" cx="16" cy="23.4" r="1.6"/>`) },
  };
})();

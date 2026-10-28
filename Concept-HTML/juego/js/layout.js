/* Codemageddon · reparto de pantalla, teclado del teléfono, barra de símbolos y tooltips.
 * No sabe nada del juego: habla con juego.js solo a través de window.cmg (insertar, comentar, medir).
 *
 * Forma: ?forma=movil o ?forma=escritorio la fuerzan; si no, se decide por el tamaño de la ventana.
 * ?marco=1 (lo pone probar.html): dentro de un marco de teléfono se simula el teclado al escribir. */
(() => {
  "use strict";
  const $ = (id) => document.getElementById(id);
  const app = $("app"), divisor = $("divisor"), zonaCodigo = $("zona-codigo");
  const params = new URLSearchParams(location.search);
  const forzada = ["movil", "escritorio"].includes(params.get("forma")) ? params.get("forma") : null;
  const enMarco = params.get("marco") === "1";
  const leer = (k, d) => { try { const v = localStorage.getItem(`cmg-juego-${k}`); return v == null ? d : JSON.parse(v); } catch { return d; } };
  const escribir = (k, v) => { try { localStorage.setItem(`cmg-juego-${k}`, JSON.stringify(v)); } catch { /* sin almacenamiento: no pasa nada */ } };

  if (enMarco) $("b-probar").hidden = true;

  // ---------- Forma y reparto ----------
  const REPARTO = { escritorio: 58, movil: 50 };
  let forma = null;
  // Reserva para Settings: «tira» conserva la presentación móvil anterior.
  app.dataset.inspectorMovil = leer("inspector-movil", "completo") === "tira" ? "tira" : "completo";
  function decidirForma() {
    if (forzada) return forzada;
    const w = innerWidth, h = innerHeight;
    return w < 760 || (w < 1000 && h > w) ? "movil" : "escritorio";
  }
  function aplicarReparto(p) {
    app.style.setProperty("--a", `${p}fr`);
    app.style.setProperty("--b", `${100 - p}fr`);
    divisor.setAttribute("aria-valuenow", Math.round(p));
  }
  function aplicarForma() {
    const f = decidirForma();
    if (f === forma) return;
    forma = f;
    app.dataset.forma = f;
    app.dispatchEvent(new Event("cmg:forma"));
    divisor.setAttribute("aria-orientation", f === "movil" ? "horizontal" : "vertical");
    aplicarReparto(leer(`reparto-${f}`, REPARTO[f]));
    actualizarTeclado();
  }

  // El divisor se arrastra (ratón o dedo), se mueve con las flechas y vuelve al reparto inicial con doble clic.
  function limites() {
    const r = app.getBoundingClientRect();
    if (forma === "movil") return { min: 28, max: 72 };
    const ancho = r.width - 16;
    return { min: Math.min(50, 380 / ancho * 100), max: Math.max(50, 100 - 360 / ancho * 100) };
  }
  const recortar = (p) => { const { min, max } = limites(); return Math.min(max, Math.max(min, p)); };
  let arrastre = null;
  divisor.addEventListener("pointerdown", (ev) => {
    divisor.setPointerCapture(ev.pointerId);
    arrastre = app.getBoundingClientRect();
    divisor.classList.add("arrastra");
    ev.preventDefault();
  });
  divisor.addEventListener("pointermove", (ev) => {
    if (!arrastre) return;
    const cs = getComputedStyle(app);
    const p = forma === "movil"
      ? (ev.clientY - arrastre.top - parseFloat(cs.paddingTop)) / (arrastre.height - parseFloat(cs.paddingTop) - parseFloat(cs.paddingBottom) - 16) * 100
      : (ev.clientX - arrastre.left - parseFloat(cs.paddingLeft)) / (arrastre.width - parseFloat(cs.paddingLeft) - parseFloat(cs.paddingRight) - 16) * 100;
    aplicarReparto(recortar(p));
  });
  const soltar = () => {
    if (!arrastre) return;
    arrastre = null; divisor.classList.remove("arrastra");
    escribir(`reparto-${forma}`, parseFloat(app.style.getPropertyValue("--a")));
  };
  divisor.addEventListener("pointerup", soltar);
  divisor.addEventListener("pointercancel", soltar);
  divisor.addEventListener("dblclick", () => { aplicarReparto(REPARTO[forma]); escribir(`reparto-${forma}`, REPARTO[forma]); });
  divisor.addEventListener("keydown", (ev) => {
    const menos = forma === "movil" ? "ArrowUp" : "ArrowLeft", mas = forma === "movil" ? "ArrowDown" : "ArrowRight";
    if (ev.key !== menos && ev.key !== mas) return;
    ev.preventDefault();
    const p = recortar(parseFloat(app.style.getPropertyValue("--a")) + (ev.key === mas ? 2 : -2));
    aplicarReparto(p); escribir(`reparto-${forma}`, p);
  });

  // ---------- Teclado del teléfono ----------
  // Con interactive-widget=resizes-visual el teclado no encoge la página: tapa su parte de abajo.
  // El editor ocupa todo el viewport visual disponible encima de la barra de símbolos.
  const ALTO_SIMBOLOS = 46;
  const simbolos = $("simbolos"), tecladoSim = $("teclado-sim");
  let simulado = 0;
  const codigo = () => window.cmg && window.cmg.codigo;
  function actualizarTeclado() {
    const vv = window.visualViewport;
    const real = vv ? Math.max(0, innerHeight - vv.height - vv.offsetTop) : 0;
    const enCodigo = document.activeElement && document.activeElement === codigo();
    const teclado = enMarco ? simulado : real;
    const abierto = forma === "movil" && enCodigo && teclado > 100;
    app.classList.toggle("teclado", abierto);
    simbolos.hidden = !abierto;
    tecladoSim.hidden = !(abierto && enMarco);
    document.documentElement.style.setProperty("--teclado", `${abierto ? teclado : 0}px`);
    if (abierto) {
      const arriba = enMarco ? 0 : (vv ? vv.offsetTop : 0);
      const alto = enMarco ? innerHeight - simulado : (vv ? vv.height : innerHeight - teclado);
      app.style.setProperty("--codigo-arriba", `${arriba}px`);
      app.style.setProperty("--codigo-alto", `${Math.max(0, alto - ALTO_SIMBOLOS)}px`);
      requestAnimationFrame(() => window.cmg && window.cmg.medirEditor());
    } else {
      app.style.removeProperty("--codigo-arriba");
      app.style.removeProperty("--codigo-alto");
    }
  }
  if (window.visualViewport) {
    visualViewport.addEventListener("resize", actualizarTeclado);
    visualViewport.addEventListener("scroll", actualizarTeclado);
  }
  document.addEventListener("focusin", (ev) => {
    if (ev.target !== codigo()) return;
    if (enMarco) simulado = Math.round(innerHeight * .4);
    actualizarTeclado();
    setTimeout(actualizarTeclado, 350);  // iOS termina de subir el teclado después del foco
  });
  document.addEventListener("focusout", (ev) => {
    if (ev.target !== codigo()) return;
    setTimeout(() => { if (document.activeElement !== codigo()) { simulado = 0; actualizarTeclado(); } }, 60);
  });

  // Teclado simulado (solo en probar.html): un dibujo para ver el reparto; se escribe con el teclado del PC.
  tecladoSim.innerHTML = ["qwertyuiop", "asdfghjkl", "zxcvbnm"].map((f, i) =>
    `<div class="fila">${i === 2 ? `<i class="gris">⇧</i>` : ""}${[...f].map(c => `<i>${c}</i>`).join("")}${i === 2 ? `<i class="gris">⌫</i>` : ""}</div>`).join("")
    + `<div class="fila"><i class="gris">123</i><i class="ancha">espacio</i><i class="gris">intro</i></div>`;

  // ---------- Barra de símbolos ----------
  // Lo que cuesta escribir en un teclado de teléfono: pares, operadores y palabras clave de JavaScript.
  const TECLAS = [
    { t: "⇥", ins: "  ", cls: "nav", n: "Sangría" }, { t: "←", mover: -1, cls: "nav" }, { t: "→", mover: 1, cls: "nav" }, "|",
    { t: "( )", ins: "()", sel: 1 }, { t: "{ }", ins: "{}", sel: 1 }, { t: "[ ]", ins: "[]", sel: 1 }, { t: '" "', ins: '""', sel: 1 },
    { t: ";" }, { t: "." }, { t: "," }, { t: "=" }, { t: "===" }, { t: "!==" }, { t: "<" }, { t: ">" },
    { t: "&&" }, { t: "||" }, { t: "!" }, { t: "??" }, { t: "+" }, { t: "-" }, { t: "*" }, { t: "/" }, { t: "%" }, "|",
    ...["const", "let", "if", "else", "while", "await", "true", "false", "null"].map(k => ({ t: k, ins: k + " ", cls: "kw" })), "|",
    { t: "//", comentar: true, cls: "nav" }, { t: "⌄", ocultar: true, cls: "nav", n: "Ocultar teclado" },
  ];
  simbolos.innerHTML = TECLAS.map((k, i) => k === "|" ? `<span class="sep-pal" aria-hidden="true"></span>`
    : `<button type="button" data-i="${i}" class="${k.cls || ""}" aria-label="${k.n || k.t}">${k.t}</button>`).join("");
  // pointerdown sin foco: el textarea conserva el foco y el teclado no se cierra.
  simbolos.addEventListener("pointerdown", (ev) => { if (ev.target.closest("button")) ev.preventDefault(); });
  simbolos.addEventListener("click", (ev) => {
    const b = ev.target.closest("button[data-i]"); if (!b || !window.cmg) return;
    const k = TECLAS[+b.dataset.i], c = codigo();
    if (k.ocultar) { c.blur(); return; }
    if (k.comentar) { window.cmg.alternarComentario(); return; }
    if (k.mover) { const p = Math.max(0, Math.min(c.value.length, c.selectionStart + k.mover)); c.setSelectionRange(p, p); return; }
    const texto = k.ins ?? k.t;
    window.cmg.insertar(texto, k.sel, k.sel);
  });

  // ---------- Consola plegable (teléfono) ----------
  $("b-pie").addEventListener("click", () => {
    const pie = $("pie"), abierto = pie.dataset.abierto !== "true";
    pie.dataset.abierto = abierto;
    $("b-pie").setAttribute("aria-expanded", abierto);
    const con = $("consola"); con.scrollTop = con.scrollHeight;
  });

  // ---------- Tooltips rápidos ----------
  // Los iconos no llevan nombre: aparece al pasar el cursor (o al tocarlos en el teléfono).
  const tip = $("tip");
  let tipDe = null, tipT = 0, tipFuera = 0;
  function mostrarTip(el) {
    tipDe = el;
    const cod = el.dataset.tipCod;
    tip.innerHTML = `<b></b>${cod ? "<code></code>" : ""}`;
    tip.querySelector("b").textContent = el.dataset.tip;
    if (cod) tip.querySelector("code").textContent = cod;
    tip.hidden = false;
    const r = el.getBoundingClientRect(), t = tip.getBoundingClientRect();
    let x = r.left + r.width / 2 - t.width / 2, y = r.top - t.height - 8;
    if (y < 4) y = r.bottom + 8;
    x = Math.max(6, Math.min(innerWidth - t.width - 6, x));
    tip.style.transform = `translate(${Math.round(x)}px, ${Math.round(y)}px)`;
  }
  function ocultarTip() { clearTimeout(tipT); tipDe = null; tip.hidden = true; }
  document.addEventListener("pointerover", (ev) => {
    if (ev.pointerType === "touch") return;
    const el = ev.target.closest("[data-tip]");
    if (el === tipDe) return;
    clearTimeout(tipT);
    if (!el) { ocultarTip(); return; }
    tipT = setTimeout(() => mostrarTip(el), tip.hidden ? 70 : 0);
  });
  document.addEventListener("pointerdown", (ev) => {
    const el = ev.target.closest && ev.target.closest("[data-tip]");
    if (ev.pointerType !== "touch") { if (!el) ocultarTip(); return; }
    if (!el) { ocultarTip(); return; }
    mostrarTip(el);
    el.classList.add("vivo");
    clearTimeout(tipFuera);
    tipFuera = setTimeout(() => { el.classList.remove("vivo"); if (tipDe === el) ocultarTip(); }, 900);
  });
  addEventListener("blur", ocultarTip);

  // ---------- Arranque ----------
  addEventListener("resize", () => { aplicarForma(); actualizarTeclado(); });
  aplicarForma();
})();


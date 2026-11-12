/* The playground's behaviour: run the generator, show what it made. The engine is
 * the library itself compiled to JavaScript — `docs/engine/browser.js`, built by
 * the docs workflow — so nothing on this page re-implements the generator, and no
 * sample output is pasted in. */

const SAMPLES = {
  rest: `type User {
  id:   int64
  name: string
}

service greet {
  get  /ping         ping        "health check"
  get  /users/:id    get_user
  post /users        create_user "create a user"
}
`,
  stream: `type Tick {
  seq:  int64
  data: bytes
  meta: map[string]string
}

service feed {
  @handler watch
  get /watch returns (stream Tick)

  @handler one
  get /ticks/:id
}
`,
  broken: `service greet {
  get   /ping      ping
  nope  /users     create_user
}
`,
};

const KW = new Set([
  "pub", "priv", "fn", "let", "mut", "match", "if", "else", "for", "in", "while",
  "guard", "break", "continue", "return", "raise", "catch", "try", "async", "test",
  "struct", "enum", "suberror", "impl", "trait", "type", "typealias", "derive", "self",
  "true", "false", "with", "extern", "and",
]);

const esc = (s) =>
  s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

/* Colouring is presentation only: the text is what the library produced, escaped
 * first and split into runs. Nothing here decides what the code says. */
function moonbit(src) {
  let out = "";
  let plain = "";
  const flush = () => {
    if (!plain) return;
    out += esc(plain).replace(/\b[A-Za-z_][A-Za-z0-9_]*\b/g, (w) =>
      KW.has(w) ? `<span class="k">${w}</span>` : w
    );
    plain = "";
  };
  for (let i = 0; i < src.length; ) {
    const c = src[i];
    if (c === "/" && src[i + 1] === "/") {
      flush();
      let j = src.indexOf("\n", i);
      if (j < 0) j = src.length;
      out += `<span class="c">${esc(src.slice(i, j))}</span>`;
      i = j;
    } else if (c === '"') {
      flush();
      let j = i + 1;
      while (j < src.length) {
        if (src[j] === "\\") j += 2;
        else if (src[j] === '"') {
          j += 1;
          break;
        } else j += 1;
      }
      out += `<span class="s">${esc(src.slice(i, j))}</span>`;
      i = j;
    } else {
      plain += c;
      i += 1;
    }
  }
  flush();
  return out;
}

function json(text) {
  return esc(text).replace(
    /(&quot;|")([^"\n]*)(&quot;|")|(-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?)|\b(true|false|null)\b/g,
    (m, open, body, close, num, lit) => {
      if (open) return `<span class="s">${open}${body}${close}</span>`;
      if (num) return `<span class="n">${num}</span>`;
      return `<span class="k">${lit}</span>`;
    }
  );
}

const $ = (id) => document.getElementById(id);
const spec = $("spec");
const out = $("out");
const findings = $("findings");
const specFoot = $("spec-foot");
const outFoot = $("out-foot");
const offline = $("offline");

let compile = null;
let view = "code";
let last = null;

const kb = (text) => {
  const n = new TextEncoder().encode(text).length;
  return n < 1024 ? `${n} bytes` : `${(n / 1024).toFixed(1)} kB`;
};

function say(el, text, bad) {
  el.innerHTML = "";
  const span = document.createElement("span");
  span.className = bad ? "bad" : "said";
  span.textContent = text;
  el.appendChild(span);
}

function renderFindings(list) {
  findings.innerHTML = "";
  if (!list.length) {
    const li = document.createElement("li");
    li.className = "empty";
    li.textContent = "nothing to report";
    findings.appendChild(li);
    return;
  }
  for (const f of list) {
    const li = document.createElement("li");
    li.className = f.severity;
    const sev = document.createElement("span");
    sev.className = "sev";
    sev.textContent = f.severity;
    const rule = document.createElement("span");
    rule.className = "rule";
    rule.textContent = `[${f.rule}]`;
    li.append(sev, rule, document.createTextNode(` ${f.at}: ${f.message}`));
    findings.appendChild(li);
  }
}

function show(result) {
  last = result;
  if (!result.ok) {
    out.innerHTML = "";
    out.textContent = "no code: the spec did not parse.";
    findings.hidden = true;
    out.hidden = false;
    say(specFoot, "the parser stopped", true);
    say(outFoot, result.error, true);
    return;
  }
  const routes = result.routes.length;
  say(
    specFoot,
    `${result.service} · ${routes} route${routes === 1 ? "" : "s"}`
  );
  renderFindings(result.findings);
  paint();
}

function paint() {
  if (!last || !last.ok) return;
  out.hidden = view === "findings";
  findings.hidden = view !== "findings";
  if (view === "code") {
    out.innerHTML = moonbit(last.code);
    say(outFoot, `${kb(last.code)} of MoonBit`);
  } else if (view === "openapi") {
    out.innerHTML = json(last.openapi);
    say(outFoot, `${kb(last.openapi)} of JSON`);
  } else {
    const n = last.findings.length;
    say(outFoot, n === 0 ? "no findings" : `${n} finding${n === 1 ? "" : "s"}`);
  }
}

function run() {
  if (!compile) return;
  let result;
  try {
    result = JSON.parse(compile(spec.value));
  } catch (e) {
    say(outFoot, `the engine failed: ${e}`, true);
    return;
  }
  show(result);
}

let timer = 0;
spec.addEventListener("input", () => {
  clearTimeout(timer);
  timer = setTimeout(run, 140);
});

for (const button of document.querySelectorAll("[data-sample]")) {
  button.addEventListener("click", () => {
    for (const other of document.querySelectorAll("[data-sample]")) {
      other.setAttribute("aria-pressed", String(other === button));
    }
    spec.value = SAMPLES[button.dataset.sample];
    run();
  });
}

for (const button of document.querySelectorAll("[data-out]")) {
  button.addEventListener("click", () => {
    view = button.dataset.out;
    for (const other of document.querySelectorAll("[data-out]")) {
      other.setAttribute("aria-selected", String(other === button));
    }
    paint();
  });
}

try {
  ({ compile } = await import("../engine/browser.js"));
} catch (e) {
  compile = null;
}

if (!compile) {
  spec.value = SAMPLES.rest;
  offline.hidden = false;
  say(specFoot, "the engine is not built here", true);
  say(outFoot, "nothing to run", true);
  out.textContent = "";
} else {
  spec.value = SAMPLES.rest;
  run();
}

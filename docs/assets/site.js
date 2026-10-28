/* moonctl site — the whole of the behaviour: theme, tabs, copy, and the small
 * bits of chrome (sticky header, mobile navigation, table of contents).
 * No framework, no dependency, works from the file system as well as from Pages. */

(function () {
  "use strict";

  var root = document.documentElement;

  /* --- theme ------------------------------------------------------------- */

  function setTheme(name) {
    root.setAttribute("data-theme", name);
    var meta = document.querySelector('meta[name="theme-color"]');
    if (meta) {
      meta.setAttribute("content", name === "light" ? "#fbfbfe" : "#08080d");
    }
    document.querySelectorAll("[data-theme-toggle]").forEach(function (btn) {
      btn.setAttribute(
        "aria-label",
        name === "light" ? "Switch to the dark theme" : "Switch to the light theme"
      );
      btn.dataset.theme = name;
    });
  }

  var stored = null;
  try {
    stored = localStorage.getItem("mctl-theme");
  } catch (e) {
    stored = null;
  }
  setTheme(stored === "light" || stored === "dark" ? stored : "dark");

  document.addEventListener("click", function (event) {
    var toggle = event.target.closest("[data-theme-toggle]");
    if (!toggle) {
      return;
    }
    var next = root.getAttribute("data-theme") === "light" ? "dark" : "light";
    setTheme(next);
    try {
      localStorage.setItem("mctl-theme", next);
    } catch (e) {
      /* a browser with storage switched off still gets the theme for this page */
    }
  });

  /* --- the header earns its border once the page has moved ---------------- */

  var header = document.querySelector(".site-header");
  if (header) {
    var onScroll = function () {
      header.classList.toggle("stuck", window.scrollY > 4);
    };
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
  }

  /* --- mobile navigation -------------------------------------------------- */

  document.addEventListener("click", function (event) {
    var navToggle = event.target.closest("[data-nav-toggle]");
    if (navToggle && header) {
      var open = header.classList.toggle("open");
      navToggle.setAttribute("aria-expanded", open ? "true" : "false");
      return;
    }
    var sideToggle = event.target.closest("[data-side-toggle]");
    var side = document.querySelector(".side");
    if (sideToggle && side) {
      var shown = side.classList.toggle("open");
      sideToggle.setAttribute("aria-expanded", shown ? "true" : "false");
    }
  });

  /* --- tabs --------------------------------------------------------------- */

  function selectTab(bar, index) {
    var tabs = Array.prototype.slice.call(bar.querySelectorAll("[data-tab]"));
    var group = bar.closest("[data-tabs]");
    if (!group) {
      return;
    }
    var panels = group.querySelectorAll("[data-panel]");
    tabs.forEach(function (tab, i) {
      var on = i === index;
      tab.setAttribute("aria-selected", on ? "true" : "false");
      tab.tabIndex = on ? 0 : -1;
    });
    Array.prototype.forEach.call(panels, function (panel, i) {
      panel.dataset.active = i === index ? "true" : "false";
    });
  }

  document.querySelectorAll("[data-tab]").forEach(function (tab) {
    tab.addEventListener("click", function () {
      var bar = tab.parentElement;
      var tabs = Array.prototype.slice.call(bar.querySelectorAll("[data-tab]"));
      selectTab(bar, tabs.indexOf(tab));
    });
  });

  document.querySelectorAll(".tab-bar").forEach(function (bar) {
    bar.addEventListener("keydown", function (event) {
      var tabs = Array.prototype.slice.call(bar.querySelectorAll("[data-tab]"));
      var at = tabs.indexOf(document.activeElement);
      if (at < 0) {
        return;
      }
      if (event.key === "ArrowRight" || event.key === "ArrowLeft") {
        event.preventDefault();
        var step = event.key === "ArrowRight" ? 1 : -1;
        var next = (at + step + tabs.length) % tabs.length;
        tabs[next].focus();
        selectTab(bar, next);
      }
    });
  });

  /* --- copy buttons ------------------------------------------------------- */

  function copyText(text, button) {
    var done = function () {
      var was = button.textContent;
      button.textContent = "Copied";
      setTimeout(function () {
        button.textContent = was;
      }, 1400);
    };
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(done, function () {
        fallbackCopy(text) && done();
      });
    } else if (fallbackCopy(text)) {
      done();
    }
  }

  function fallbackCopy(text) {
    var area = document.createElement("textarea");
    area.value = text;
    area.setAttribute("readonly", "");
    area.style.position = "fixed";
    area.style.opacity = "0";
    document.body.appendChild(area);
    area.select();
    var ok = false;
    try {
      ok = document.execCommand("copy");
    } catch (e) {
      ok = false;
    }
    document.body.removeChild(area);
    return ok;
  }

  document.querySelectorAll("[data-copy]").forEach(function (button) {
    button.addEventListener("click", function () {
      var block = button.closest(".code, .tabs, .term");
      var pre = block && block.querySelector("pre");
      if (pre) {
        copyText(pre.innerText.replace(/\s+$/, ""), button);
      }
    });
  });

  /* --- table of contents -------------------------------------------------- */

  var tocLinks = Array.prototype.slice.call(document.querySelectorAll(".toc a[href^='#']"));
  if (tocLinks.length) {
    var headings = tocLinks
      .map(function (link) {
        return document.getElementById(link.getAttribute("href").slice(1));
      })
      .filter(Boolean);

    var mark = function () {
      var best = headings[0];
      headings.forEach(function (heading) {
        if (heading.getBoundingClientRect().top <= 120) {
          best = heading;
        }
      });
      tocLinks.forEach(function (link) {
        var on = link.getAttribute("href") === "#" + best.id;
        link.classList.toggle("active", on);
      });
    };

    if ("IntersectionObserver" in window) {
      var observer = new IntersectionObserver(mark, {
        rootMargin: "-100px 0px -70% 0px",
        threshold: [0, 1],
      });
      headings.forEach(function (heading) {
        observer.observe(heading);
      });
    }
    mark();
    window.addEventListener("scroll", mark, { passive: true });
  }
})();

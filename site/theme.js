(function () {
  var root = document.documentElement;
  var lightBtn = document.getElementById("lightBtn");
  var darkBtn = document.getElementById("darkBtn");
  if (!lightBtn || !darkBtn) return;
  var media = window.matchMedia("(prefers-color-scheme: dark)");

  function current() {
    var set = root.getAttribute("data-theme");
    if (set) return set;
    return media.matches ? "dark" : "light";
  }

  function paint() {
    var now = current();
    lightBtn.setAttribute("aria-pressed", String(now === "light"));
    darkBtn.setAttribute("aria-pressed", String(now === "dark"));
  }

  function choose(theme) {
    root.setAttribute("data-theme", theme);
    try { localStorage.setItem("overhang-theme", theme); } catch (e) {}
    paint();
  }

  lightBtn.addEventListener("click", function () { choose("light"); });
  darkBtn.addEventListener("click", function () { choose("dark"); });

  // Follow the system while the visitor has not expressed a preference.
  media.addEventListener("change", function () {
    if (!root.getAttribute("data-theme")) paint();
  });

  paint();
})();

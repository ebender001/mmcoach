/**
 * M & M Coach marketing site -- lightweight, dependency-free behavior only:
 * accessible mobile nav toggle, smooth same-page scrolling (respecting
 * reduced-motion), closing the mobile menu after a nav selection, and
 * keeping the footer copyright year current. No trackers, no third-party
 * code.
 */
(function () {
  "use strict";

  var header = document.querySelector(".site-header");
  var navToggle = document.getElementById("nav-toggle");
  var nav = document.getElementById("primary-nav");

  var prefersReducedMotion = window.matchMedia(
    "(prefers-reduced-motion: reduce)"
  );

  function isMobileMenuOpen() {
    return nav.classList.contains("is-open");
  }

  function openMobileMenu() {
    nav.classList.add("is-open");
    navToggle.setAttribute("aria-expanded", "true");
    document.body.style.overflow = "hidden";
  }

  function closeMobileMenu() {
    nav.classList.remove("is-open");
    navToggle.setAttribute("aria-expanded", "false");
    document.body.style.overflow = "";
  }

  function toggleMobileMenu() {
    if (isMobileMenuOpen()) {
      closeMobileMenu();
    } else {
      openMobileMenu();
    }
  }

  if (navToggle && nav) {
    navToggle.addEventListener("click", toggleMobileMenu);

    // Close on Escape, and return focus to the toggle button.
    document.addEventListener("keydown", function (event) {
      if (event.key === "Escape" && isMobileMenuOpen()) {
        closeMobileMenu();
        navToggle.focus();
      }
    });

    // A menu selection should close the menu, not just navigate.
    nav.querySelectorAll("a").forEach(function (link) {
      link.addEventListener("click", function () {
        if (isMobileMenuOpen()) {
          closeMobileMenu();
        }
      });
    });

    // If the viewport grows past the mobile breakpoint while the menu is
    // open (e.g. rotating a tablet), don't leave it stuck open/hidden.
    window
      .matchMedia("(min-width: 880px)")
      .addEventListener("change", function (event) {
        if (event.matches) {
          closeMobileMenu();
        }
      });
  }

  // Smooth-scroll same-page anchor links, skipping bare "#" placeholders
  // (the App Store button) and respecting reduced-motion preference.
  document.querySelectorAll('a[href^="#"]').forEach(function (link) {
    link.addEventListener("click", function (event) {
      var targetId = link.getAttribute("href");
      if (!targetId || targetId === "#") {
        return;
      }

      var target = document.getElementById(targetId.slice(1));
      if (!target) {
        return;
      }

      event.preventDefault();
      target.scrollIntoView({
        behavior: prefersReducedMotion.matches ? "auto" : "smooth",
        block: "start",
      });

      // Keep the URL shareable/bookmarkable without a jarring jump.
      history.pushState(null, "", targetId);
      target.setAttribute("tabindex", "-1");
      target.focus({ preventScroll: true });
    });
  });

  var yearEl = document.getElementById("current-year");
  if (yearEl) {
    yearEl.textContent = String(new Date().getFullYear());
  }

  // Adds a subtle elevation once the page has scrolled, so the sticky
  // header reads as "above" content rather than just floating on it.
  if (header) {
    var toggleHeaderShadow = function () {
      header.classList.toggle("is-scrolled", window.scrollY > 4);
    };
    toggleHeaderShadow();
    window.addEventListener("scroll", toggleHeaderShadow, { passive: true });
  }
})();

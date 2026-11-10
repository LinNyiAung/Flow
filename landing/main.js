// Toe Pwar landing page: the language switch, and the parts that come from the backend (plan prices, the owner's
// contact links, the Android download). Without JavaScript the page still shows in English; prices, contact links and
// the Android buttons stay hidden until the backend answers.
(() => {
  'use strict';

  // The backend, from <meta name="tp-api-base"> in index.html. Both endpoints used here are public (no login).
  const API_BASE = (document.querySelector('meta[name="tp-api-base"]') || {}).content || 'https://toepwar-t9vc.onrender.com';
  const LANG_KEY = 'tp-lang';
  const FETCH_TIMEOUT_MS = 60000; // a sleeping Render instance can take a while to wake up

  const COPY = window.TP_COPY;
  const root = document.querySelector('.tp');
  const defaultTitle = document.title;
  const listTemplates = new Map();
  const state = { lang: 'en', prices: null };

  // ---------------------------------------------------------------- language

  function savedOrBrowserLang() {
    try {
      const saved = localStorage.getItem(LANG_KEY);
      if (saved === 'en' || saved === 'my') return saved;
    } catch (_) { /* storage blocked: fall through */ }
    const langs = navigator.languages && navigator.languages.length ? navigator.languages : [navigator.language || ''];
    // the browser's first preference that is English or Myanmar
    const first = langs.find((l) => /^(en|my)(-|$)/i.test(l));
    return first && /^my/i.test(first) ? 'my' : 'en';
  }

  function applyLang(lang) {
    const t = COPY[lang];
    state.lang = lang;
    root.setAttribute('lang', lang);
    document.documentElement.setAttribute('lang', lang);
    document.title = lang === 'my' ? `${t.brand} — ${t.tagline}` : defaultTitle;

    root.querySelectorAll('[data-i18n]').forEach((el) => { el.textContent = t[el.dataset.i18n]; });
    root.querySelectorAll('[data-i18n-attr]').forEach((el) => {
      el.dataset.i18nAttr.split(',').forEach((pair) => {
        const [attr, key] = pair.split(':');
        el.setAttribute(attr, t[key]);
      });
    });
    root.querySelectorAll('[data-i18n-list]').forEach((ul) => {
      // the first <li> in the page is the template for every item
      if (!listTemplates.has(ul)) listTemplates.set(ul, ul.querySelector('li').cloneNode(true));
      const template = listTemplates.get(ul);
      ul.replaceChildren(...t[ul.dataset.i18nList].map((label) => {
        const li = template.cloneNode(true);
        li.querySelector('[data-item]').textContent = label;
        return li;
      }));
    });
    root.querySelectorAll('[data-set-lang]').forEach((btn) => {
      btn.setAttribute('aria-pressed', String(btn.dataset.setLang === lang));
    });
    renderPrices();
  }

  root.querySelectorAll('[data-set-lang]').forEach((btn) => {
    btn.addEventListener('click', () => {
      applyLang(btn.dataset.setLang);
      measureHeader(); // Myanmar text is taller
      try { localStorage.setItem(LANG_KEY, btn.dataset.setLang); } catch (_) { /* not remembered */ }
    });
  });

  // ---------------------------------------------------------------- prices (GET /api/plan/public)

  /** "K15,000", like the app's formatPlanPrice. */
  const formatPrice = (mmk) => 'K' + Math.round(mmk).toLocaleString('en-US');

  /** A whole number of kyat above 0, else null (not set). */
  function positiveInt(value) {
    return Number.isInteger(value) && value > 0 ? value : null;
  }

  // Like the app's PlanPrice: a plan with no monthly price shows no price; a yearly price only comes with a monthly
  // one; "save N%" (round((1 - yearly / (12 * monthly)) * 100)) only when N is above 0.
  function renderPrices() {
    const t = COPY[state.lang];
    ['plus', 'pro'].forEach((plan) => {
      const price = (state.prices && state.prices[plan]) || {};
      const monthly = positiveInt(price.monthly_mmk);
      const yearly = monthly ? positiveInt(price.yearly_mmk) : null;
      const save = yearly ? Math.round((1 - yearly / (12 * monthly)) * 100) : 0;
      const q = (sel) => root.querySelector(sel);

      q(`[data-price-block="${plan}"]`).hidden = !monthly;
      q(`[data-price="${plan}.main"]`).textContent = monthly ? formatPrice(monthly) : '';
      q(`[data-price-if="${plan}.hasYearly"]`).hidden = !yearly;
      q(`[data-price="${plan}.yearly"]`).textContent = yearly ? t.orYearly.replace('{price}', formatPrice(yearly)) : '';
      q(`[data-price-if="${plan}.hasSave"]`).hidden = !(save > 0);
      q(`[data-price="${plan}.save"]`).textContent = save > 0 ? t.savePct.replace('{p}', String(save)) : '';
    });
  }

  // ---------------------------------------------------------------- contact links (the owner contact in the admin panel)

  /** Same links as the app (frontend/lib/utils/contact_details.dart); null when the value is not usable. */
  function contactHref(kind, value) {
    if (typeof value !== 'string' || !value) return null;
    switch (kind) {
      case 'email': return 'mailto:' + encodeURI(value);
      case 'viber': return 'viber://chat?number=' + encodeURIComponent(value);
      case 'telegram': return 'https://t.me/' + encodeURI(value.startsWith('@') ? value.slice(1) : value);
      case 'facebook':
      case 'messenger': return httpsUrl(value);
      default: return null;
    }
  }

  function httpsUrl(value) {
    try {
      const url = new URL(value);
      return url.protocol === 'https:' ? url.href : null;
    } catch (_) {
      return null;
    }
  }

  function renderContacts(contact) {
    let any = false;
    root.querySelectorAll('[data-contact]').forEach((a) => {
      const href = contactHref(a.dataset.contact, contact && contact[a.dataset.contact]);
      a.hidden = !href;
      if (!href) return;
      any = true;
      a.href = href;
      if (href.startsWith('https://')) {
        a.target = '_blank';
        a.rel = 'noopener noreferrer';
      }
    });
    root.querySelector('[data-contact-nav]').hidden = !any;
  }

  // ---------------------------------------------------------------- Android download (GET /api/app/latest-android)

  // Same rule as the app's shouldOfferAndroidDownload: not on iPhone/iPad/iPod, and not on an iPad that sends a
  // desktop Mac user agent (a Mac user agent on a touch screen; a real Mac reports 0 touch points).
  function shouldOfferAndroidDownload() {
    const ua = navigator.userAgent || '';
    if (/iPhone|iPad|iPod/i.test(ua)) return false;
    return !(ua.includes('Macintosh') && (navigator.maxTouchPoints || 0) > 1);
  }

  function renderDownload(latest) {
    const href = latest && latest.version && typeof latest.download_url === 'string' ? webUrl(latest.download_url) : null;
    root.querySelectorAll('[data-apk]').forEach((a) => {
      a.hidden = !href;
      if (href) a.href = href;
    });
  }

  function webUrl(value) {
    try {
      const url = new URL(value);
      return url.protocol === 'https:' || url.protocol === 'http:' ? url.href : null;
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------- header: the section in view, and its height

  const header = root.querySelector('header');
  const navLinks = [...root.querySelectorAll('header a[href^="#"]:not([href="#top"])')];
  const sections = [...new Set(navLinks.map((a) => a.getAttribute('href')))].map((id) => root.querySelector(id));

  // A section is "in view" once its top has passed a line a third of the way down the space under the header,
  // until its bottom passes that line. None is marked above the first or below the last (hero, footer).
  function markCurrentSection() {
    const headerBottom = header.getBoundingClientRect().bottom;
    const line = headerBottom + (window.innerHeight - headerBottom) / 3;
    const current = sections.find((s) => {
      const r = s.getBoundingClientRect();
      return r.top <= line && r.bottom > line;
    });
    navLinks.forEach((a) => {
      if (current && a.getAttribute('href') === '#' + current.id) a.setAttribute('aria-current', 'location');
      else a.removeAttribute('aria-current');
    });
  }

  // so a tapped section's heading lands just under the (sticky) header, whatever its height in this language
  function measureHeader() {
    root.style.setProperty('--header-h', Math.ceil(header.getBoundingClientRect().height) + 12 + 'px');
  }

  let frame = 0;
  const onScroll = () => {
    if (frame) return;
    frame = requestAnimationFrame(() => { frame = 0; markCurrentSection(); });
  };
  window.addEventListener('scroll', onScroll, { passive: true });
  window.addEventListener('resize', () => { measureHeader(); onScroll(); });

  // ---------------------------------------------------------------- loading

  async function getJson(path) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);
    try {
      const res = await fetch(API_BASE + path, { signal: controller.signal, headers: { Accept: 'application/json' } });
      return res.ok ? await res.json() : null;
    } catch (_) {
      return null; // offline, blocked or timed out: those parts stay hidden
    } finally {
      clearTimeout(timer);
    }
  }

  applyLang(savedOrBrowserLang());
  measureHeader();
  markCurrentSection();

  getJson('/api/plan/public').then((info) => {
    if (!info) return;
    state.prices = info.prices || null;
    renderPrices();
    renderContacts(info.owner_contact);
  });

  if (shouldOfferAndroidDownload()) getJson('/api/app/latest-android').then(renderDownload);
})();

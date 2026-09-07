(function () {
  var legal = window.HotPotLegal;
  if (!legal) return;

  var doc = legal.docFromPath(window.location.pathname);
  var root = document.getElementById('legal-root');
  var nav = document.getElementById('legal-nav');
  if (!root) return;

  if (nav) {
    nav.innerHTML = legal.nav
      .map(function (item) {
        var active = doc && ('/' + doc.slug) === item.href;
        return (
          '<a class="legal-nav-link' +
          (active ? ' is-active' : '') +
          '" href="' +
          item.href +
          '">' +
          item.label +
          '</a>'
        );
      })
      .join('');
  }

  if (!doc) {
    document.title = 'Help · HotPotChef';
    root.innerHTML =
      '<p class="meal-kicker">Help</p>' +
      '<h1 class="meal-title">Policies &amp; FAQs</h1>' +
      '<p class="meal-meta">Pick a document below — same copy as in the HotPotChef app.</p>' +
      '<ul class="legal-index">' +
      legal.nav
        .map(function (item) {
          return '<li><a href="' + item.href + '">' + item.label + '</a></li>';
        })
        .join('') +
      '</ul>';
    return;
  }

  document.title = doc.title + ' · HotPotChef';
  var desc = document.querySelector('meta[name="description"]');
  if (desc) desc.setAttribute('content', doc.title + ' for HotPotChef.');

  root.innerHTML =
    '<p class="meal-kicker">Help</p>' +
    '<h1 class="meal-title">' +
    escapeHtml(doc.title) +
    '</h1>' +
    '<p class="meal-meta">Updated ' +
    escapeHtml(doc.updated) +
    '</p>' +
    doc.sections
      .map(function (section) {
        return (
          '<section class="legal-section">' +
          '<h2>' +
          escapeHtml(section.heading) +
          '</h2>' +
          '<p>' +
          escapeHtml(section.body) +
          '</p>' +
          '</section>'
        );
      })
      .join('') +
    '<p class="legal-contact">Questions? Email <a href="mailto:hello@hotpotchef.com">hello@hotpotchef.com</a></p>';

  function escapeHtml(text) {
    return String(text || '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }
})();

(function () {
  var api = window.HotPotApi;
  if (!api) return;

  function setText(id, text) {
    var el = document.getElementById(id);
    if (el) el.textContent = text || '';
  }

  function show(id, on) {
    var el = document.getElementById(id);
    if (!el) return;
    el.hidden = !on;
  }

  function renderMissing(chefId, message) {
    setText('title', 'Kitchen unavailable');
    setText('meta', message || 'This home kitchen could not be found.');
    show('status', true);
    setText('status', 'Open HotPotChef to browse neighbourhood kitchens near you.');
    api.wireOpenApp('open-app', 'play-cta', 'chef', chefId || '');
  }

  function mealRow(meal) {
    var id = (meal.id || '').toString();
    var title = api.mealTitle(meal);
    var price = api.money(meal.price);
    var image = (meal.image_url || '').toString().trim();
    var thumb = image
      ? '<img src="' + api.escapeHtml(image) + '" alt="" loading="lazy" />'
      : '<div class="chef-meal-thumb chef-meal-thumb--empty" aria-hidden="true"></div>';
    return (
      '<a class="chef-meal" href="/meal/' +
      encodeURIComponent(id) +
      '">' +
      thumb +
      '<div><strong>' +
      api.escapeHtml(title) +
      '</strong>' +
      (price ? '<span>' + api.escapeHtml(price) + '</span>' : '') +
      '</div></a>'
    );
  }

  async function loadChef(chefId) {
    try {
      var users = await api.supabaseGet(
        'users?id=eq.' +
          encodeURIComponent(chefId) +
          '&select=id,name,full_name,fssai_number,city'
      );
      var user = users && users[0];

      var profiles = [];
      try {
        profiles = await api.supabaseGet(
          'chef_profiles?user_id=eq.' +
            encodeURIComponent(chefId) +
            '&select=local_kitchen_name,kitchen_story,hygiene_note'
        );
      } catch (_) {}

      var kitchen = profiles && profiles[0];
      var name = api.chefLabel({
        local_kitchen_name: kitchen && kitchen.local_kitchen_name,
        name: user && (user.name || user.full_name),
        chef_name: user && (user.name || user.full_name),
      });

      if (!user && !kitchen) {
        renderMissing(chefId, 'This home kitchen could not be found.');
        return;
      }

      var fssai = ((user && user.fssai_number) || '').toString().trim();
      var city = ((user && user.city) || '').toString().trim();
      var story = ((kitchen && kitchen.kitchen_story) || '').toString().trim();
      var metaParts = [];
      if (city) metaParts.push(city);
      if (fssai) metaParts.push('FSSAI ' + fssai);

      setText('title', name);
      setText('meta', metaParts.join(' · ') || 'Neighbourhood home kitchen');
      if (story) {
        show('desc', true);
        setText('desc', story);
      }

      var meals = await api.supabaseGet(
        'meals?chef_id=eq.' +
          encodeURIComponent(chefId) +
          '&status=eq.Available&select=id,title,name,price,image_url,created_at&order=created_at.desc&limit=48'
      );

      var list = document.getElementById('meal-list');
      if (list) {
        if (!meals || !meals.length) {
          list.innerHTML = '<p class="chef-empty">No Available plates from this kitchen right now.</p>';
        } else {
          list.innerHTML = meals.map(mealRow).join('');
        }
      }

      var origin = api.siteOrigin();
      var pageUrl = origin + '/chef/' + encodeURIComponent(chefId);
      api.setOg(name + ' · HotPotChef', api.punchline() + ' · ' + name, undefined, pageUrl);
      api.wireOpenApp('open-app', 'play-cta', 'chef', chefId);
    } catch (err) {
      renderMissing(chefId, 'Could not load this kitchen right now.');
    }
  }

  var chefId = api.idFromPath('chef');
  if (!chefId) {
    renderMissing('', 'Missing kitchen link.');
    return;
  }
  if (!api.configReady()) {
    renderMissing(chefId, 'Site config is incomplete. Add Supabase URL and anon key in js/config.js.');
    return;
  }
  api.wireOpenApp('open-app', 'play-cta', 'chef', chefId);
  loadChef(chefId);
})();

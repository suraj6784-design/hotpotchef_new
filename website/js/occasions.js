(function (root, factory) {
  if (typeof module === 'object' && module.exports) {
    module.exports = factory();
  } else {
    root.HotPotOccasions = factory();
  }
})(typeof window !== 'undefined' ? window : globalThis, function () {
  var EVERYDAY = 'everyday';
  var FESTIVE = 'festive';
  var PARTY = 'party';
  var SPECIALTY = 'specialty';
  var SLICE_ALL = 'all';

  var TABS = [
    {
      id: EVERYDAY,
      label: 'Everyday',
      hint: 'Daily lunch and dinner, diet plates, and seasonal food.',
      slices: [
        [SLICE_ALL, 'All'],
        ['lunch', 'Lunch'],
        ['dinner', 'Dinner'],
        ['diet', 'Diet'],
        ['seasonal', 'Seasonal'],
      ],
    },
    {
      id: FESTIVE,
      label: 'Festivals',
      hint: 'Festival sweets, family thalis, and ceremony food.',
      slices: [
        [SLICE_ALL, 'All'],
        ['diwali', 'Diwali'],
        ['holi', 'Holi'],
        ['eid', 'Eid'],
        ['christmas', 'Christmas'],
        ['gathering', 'Gatherings'],
        ['ceremony', 'Ceremonies'],
      ],
    },
    {
      id: PARTY,
      label: 'Parties',
      hint: 'Birthday, anniversary, office, and community bundles.',
      slices: [
        [SLICE_ALL, 'All'],
        ['birthday', 'Birthday'],
        ['anniversary', 'Anniversary'],
        ['office', 'Office'],
        ['community', 'Community'],
      ],
    },
    {
      id: SPECIALTY,
      label: 'Specialty',
      hint: 'Pickles, savories, sweets, and seasonal jars you can subscribe to.',
      slices: [
        [SLICE_ALL, 'All'],
        ['pickle', 'Pickles'],
        ['savory', 'Savories'],
        ['sweet', 'Sweets'],
        ['seasonal', 'Seasonal'],
      ],
    },
  ];

  var OCCASION_COLUMNS =
    'description,category,cuisine,dish_course,health_tags,shelf_kind,society_label,' +
    'is_hamper,is_society_night,is_shelf_item,is_seasonal,occasion,time_slot';

  function normalizeOccasionId(raw) {
    switch ((raw || '').toString().trim().toLowerCase()) {
      case 'everyday':
      case 'daily':
        return EVERYDAY;
      case 'festive':
      case 'festival':
      case 'festivals':
        return FESTIVE;
      case 'party':
      case 'parties':
        return PARTY;
      case 'specialty':
        return SPECIALTY;
      default:
        return null;
    }
  }

  function tabById(id) {
    var wanted = normalizeOccasionId(id) || EVERYDAY;
    for (var i = 0; i < TABS.length; i++) {
      if (TABS[i].id === wanted) return TABS[i];
    }
    return TABS[0];
  }

  function sliceById(tab, id) {
    var wanted = (id || '').toString().trim();
    for (var i = 0; i < tab.slices.length; i++) {
      if (tab.slices[i][0] === wanted) return tab.slices[i];
    }
    return null;
  }

  function sliceLabel(occasion, slice) {
    var wanted = (slice || '').toString().trim();
    if (!wanted || wanted === SLICE_ALL) return '';
    var found = sliceById(tabById(occasion), wanted);
    return found ? found[1] : '';
  }

  function browseLabel(occasion, slice) {
    var label = sliceLabel(occasion, slice);
    return label || tabById(occasion).label;
  }

  function flagTrue(flag) {
    if (flag === true || flag === 1) return true;
    var text = (flag == null ? '' : String(flag)).trim().toLowerCase();
    return text === 'true' || text === '1' || text === 'yes';
  }

  function flagFalse(flag) {
    if (flag === false || flag === 0) return true;
    var text = (flag == null ? '' : String(flag)).trim().toLowerCase();
    return text === 'false' || text === '0' || text === 'no';
  }

  function haystack(meal) {
    var tags = meal.health_tags || meal.tags;
    var tagText = Array.isArray(tags) ? tags.join(' ') : tags == null ? '' : String(tags);
    return [
      meal.title,
      meal.name,
      meal.description,
      meal.category,
      meal.cuisine,
      meal.dish_course,
      meal.shelf_kind,
      meal.society_label,
      tagText,
      meal.time_slot,
    ]
      .join(' ')
      .toLowerCase();
  }

  function hayHas(hay, phrase) {
    var wanted = phrase.trim().toLowerCase();
    if (!wanted) return false;
    if (wanted.indexOf(' ') !== -1 || wanted.indexOf('-') !== -1) return hay.indexOf(wanted) !== -1;
    return new RegExp('\\b' + wanted.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '\\b').test(hay);
  }

  function hayHasAny(hay, phrases) {
    for (var i = 0; i < phrases.length; i++) {
      if (hayHas(hay, phrases[i])) return true;
    }
    return false;
  }

  function firstClockHour(text) {
    var match = /(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b/i.exec(text || '');
    if (!match) return null;
    var hour = parseInt(match[1], 10);
    if (!isFinite(hour)) return null;
    var ap = match[3].toLowerCase();
    if (ap === 'pm' && hour !== 12) hour += 12;
    if (ap === 'am' && hour === 12) hour = 0;
    return hour;
  }

  function isParty(meal, hay) {
    var society = meal.is_society_night != null ? meal.is_society_night : meal.isSocietyNight;
    if (!flagFalse(society) && flagTrue(society)) return true;
    var category = (meal.category || '').toString().toLowerCase();
    if (category.indexOf('society') !== -1 || category.indexOf('rwa') !== -1) return true;
    return hayHasAny(hay, ['birthday', 'anniversary', 'office', 'community', 'finger food', 'society night']);
  }

  function isFestive(meal, hay) {
    var hamper = meal.is_hamper != null ? meal.is_hamper : meal.isHamper;
    if (!flagFalse(hamper) && flagTrue(hamper)) return true;
    var category = (meal.category || '').toString().toLowerCase();
    if (category.indexOf('hamper') !== -1 || category.indexOf('festival') !== -1) return true;
    if (
      hayHasAny(hay, [
        'diwali',
        'holi',
        'gujiya',
        'eid',
        'ramzan',
        'ramadan',
        'christmas',
        'xmas',
        'prasad',
        'sattvic',
        'satvik',
        'fasting',
        'vrat',
        'upvas',
        'housewarming',
        'griha pravesh',
        'grihapravesh',
        'gruh pravesh',
        'naming ceremony',
        'namkaran',
        'naamkaran',
        'family gathering',
        'relatives',
        'bulk',
      ])
    ) {
      return true;
    }
    return hayHas(hay, 'thali') && hayHasAny(hay, ['gathering', 'bulk', 'function', 'family', 'relatives', 'combo']);
  }

  function isSpecialty(meal, hay) {
    var shelf = meal.is_shelf_item != null ? meal.is_shelf_item : meal.isShelfItem;
    if (!flagFalse(shelf) && flagTrue(shelf)) return true;
    if ((meal.shelf_kind || '').toString().trim()) return true;
    var category = (meal.category || '').toString().toLowerCase();
    if (category.indexOf('shelf') !== -1 || category.indexOf('pantry') !== -1) return true;
    return hayHasAny(hay, [
      'pickle',
      'achar',
      'preserve',
      'murabba',
      'chakli',
      'sev',
      'samosa',
      'pakora',
      'namkeen',
      'farsan',
      'chivda',
      'savory',
      'savoury',
      'laddu',
      'ladoo',
      'peda',
      'halwa',
      'motichoor',
      'barfi',
      'modak',
      'ganesh',
      'ganpati',
      'til',
    ]);
  }

  function mealOccasionId(meal) {
    var explicit = normalizeOccasionId(meal && meal.occasion);
    if (explicit) return explicit;
    var hay = haystack(meal || {});
    if (isParty(meal || {}, hay)) return PARTY;
    if (isFestive(meal || {}, hay)) return FESTIVE;
    if (isSpecialty(meal || {}, hay)) return SPECIALTY;
    return EVERYDAY;
  }

  function matchesSlice(meal, occasion, slice) {
    var wanted = (slice || '').toString().trim();
    if (!wanted || wanted === SLICE_ALL) return true;
    var hay = haystack(meal);
    var hour = firstClockHour(meal.time_slot);
    switch (normalizeOccasionId(occasion)) {
      case EVERYDAY:
        if (wanted === 'lunch') return hayHasAny(hay, ['lunch', 'tiffin']) || (hour != null && hour >= 11 && hour < 16);
        if (wanted === 'dinner') return hayHas(hay, 'dinner') || (hour != null && hour >= 17 && hour <= 22);
        if (wanted === 'diet') {
          return hayHasAny(hay, [
            'diabetic',
            'diabetes',
            'gluten-free',
            'gluten free',
            'vegan',
            'ayurvedic',
            'ayurveda',
            'low-oil',
            'low oil',
            'low-sugar',
            'low sugar',
            'sugar-free',
            'sugar free',
            'healthy',
            'balanced',
          ]);
        }
        if (wanted === 'seasonal') {
          return (
            flagTrue(meal.is_seasonal) ||
            hayHasAny(hay, ['seasonal', 'winter', 'summer', 'bhaji', 'soup', 'buttermilk', 'chaas', 'cooler', 'light meal'])
          );
        }
        return false;
      case FESTIVE:
        if (wanted === 'diwali') return hayHas(hay, 'diwali');
        if (wanted === 'holi') return hayHasAny(hay, ['holi', 'gujiya']);
        if (wanted === 'eid') return hayHasAny(hay, ['eid', 'ramzan', 'ramadan']);
        if (wanted === 'christmas') return hayHasAny(hay, ['christmas', 'xmas']);
        if (wanted === 'gathering') return hayHasAny(hay, ['gathering', 'bulk', 'relatives', 'combo', 'function', 'thali']);
        if (wanted === 'ceremony') {
          return hayHasAny(hay, [
            'prasad',
            'sattvic',
            'satvik',
            'fasting',
            'vrat',
            'upvas',
            'housewarming',
            'griha pravesh',
            'grihapravesh',
            'naming',
            'namkaran',
            'naamkaran',
          ]);
        }
        return false;
      case PARTY:
        if (wanted === 'birthday') return hayHasAny(hay, ['birthday', 'finger food']);
        if (wanted === 'anniversary') return hayHas(hay, 'anniversary');
        if (wanted === 'office') return hayHas(hay, 'office');
        if (wanted === 'community') {
          var society = meal.is_society_night != null ? meal.is_society_night : meal.isSocietyNight;
          return (!flagFalse(society) && flagTrue(society)) || hayHasAny(hay, ['community', 'society']);
        }
        return false;
      case SPECIALTY:
        if (wanted === 'pickle') return hayHasAny(hay, ['pickle', 'achar', 'preserve', 'murabba']);
        if (wanted === 'savory') {
          return hayHasAny(hay, ['chakli', 'sev', 'samosa', 'pakora', 'namkeen', 'farsan', 'chivda', 'savory', 'savoury']);
        }
        if (wanted === 'sweet') return hayHasAny(hay, ['laddu', 'ladoo', 'peda', 'halwa', 'motichoor', 'barfi']);
        if (wanted === 'seasonal') {
          return flagTrue(meal.is_seasonal) || hayHasAny(hay, ['til', 'modak', 'ganesh', 'ganpati', 'seasonal']);
        }
        return false;
      default:
        return false;
    }
  }

  function matchesOccasion(meal, occasion, slice) {
    var group = normalizeOccasionId(occasion);
    if (!group || mealOccasionId(meal) !== group) return false;
    return matchesSlice(meal, group, slice || SLICE_ALL);
  }

  function withBrowseOccasion(meal, occasion) {
    var copy = {};
    var key;
    for (key in meal) {
      if (Object.prototype.hasOwnProperty.call(meal, key)) copy[key] = meal[key];
    }
    copy.occasion = normalizeOccasionId(occasion) || mealOccasionId(meal);
    return copy;
  }

  function broadcastInsert(opts) {
    var tab = tabById(opts.occasion);
    var slice = sliceById(tab, opts.slice) || tab.slices[0];
    var sliceId = slice[0];
    var label = sliceId === SLICE_ALL ? tab.label : tab.label + ' · ' + slice[1];
    var note = (opts.note || '').trim();
    var qty = Number(opts.quantity) || 0;
    if (qty < 1) qty = 1;
    var details = (opts.details || '').trim();
    return {
      customer_id: opts.customerId,
      customer_email: (opts.customerEmail || '').trim(),
      customer_phone: (opts.customerPhone || '').trim(),
      title: note || (sliceId === SLICE_ALL ? tab.label + ' request' : tab.label + ': ' + slice[1]),
      description: 'Occasion: ' + label + (details ? '\n' + details : ''),
      quantity: qty,
      remaining_quantity: qty,
      budget: opts.budget == null ? 0 : opts.budget,
      service_type: opts.serviceType || 'Delivery Partner',
      request_type: 'broadcast',
      delivery_address: opts.address,
      target_date_time: opts.targetIso,
      status: 'Open',
      occasion: tab.id,
      occasion_slice: sliceId === SLICE_ALL ? null : sliceId,
      target_chef_ids: [],
    };
  }

  return {
    EVERYDAY: EVERYDAY,
    FESTIVE: FESTIVE,
    PARTY: PARTY,
    SPECIALTY: SPECIALTY,
    SLICE_ALL: SLICE_ALL,
    TABS: TABS,
    OCCASION_COLUMNS: OCCASION_COLUMNS,
    normalizeOccasionId: normalizeOccasionId,
    tabById: tabById,
    sliceLabel: sliceLabel,
    browseLabel: browseLabel,
    mealOccasionId: mealOccasionId,
    matchesOccasion: matchesOccasion,
    withBrowseOccasion: withBrowseOccasion,
    broadcastInsert: broadcastInsert,
  };
});

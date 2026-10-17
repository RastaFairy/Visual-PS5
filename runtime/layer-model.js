'use strict';
(function (root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  if (root) root.PS5HSLayers = api;
})(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  const LAYER_RANK = Object.freeze({
    panel: 0,
    card: 10,
    image: 20,
    separator: 30,
    list: 40,
    progress: 41,
    gauge: 42,
    toggle: 50,
    slider: 51,
    stepper: 52,
    select: 53,
    carousel: 54,
    input: 55,
    button: 56,
    badge: 60,
    text: 70,
    title: 80
  });

  function hasZIndex(component) {
    return component && component.zIndex !== undefined && component.zIndex !== null &&
      component.zIndex !== '' && Number.isFinite(Number(component.zIndex));
  }

  function nextZIndexForNewComponent(components, type) {
    if (!Array.isArray(components) || components.length === 0) return 10;
    const rank = LAYER_RANK[type] ?? 45;
    const ordered = components.slice().sort((a, b) => Number(a.zIndex || 0) - Number(b.zIndex || 0));
    const ranks = ordered.map(component => LAYER_RANK[component.type] ?? 45);
    const followsDefaultOrder = ranks.every((value, index) => index === 0 || value >= ranks[index - 1]);
    if (!followsDefaultOrder) return ordered.reduce((max, component) => Math.max(max, Number(component.zIndex) || 0), 0) + 10;
    const placeholder = { type };
    const insertionIndex = ordered.findIndex(component => (LAYER_RANK[component.type] ?? 45) > rank);
    if (insertionIndex < 0) ordered.push(placeholder); else ordered.splice(insertionIndex, 0, placeholder);
    ordered.forEach((component, index) => { if (component !== placeholder) component.zIndex = (index + 1) * 10; });
    return (ordered.indexOf(placeholder) + 1) * 10;
  }

  function isLegacyArrayOrder(rows) {
    // Older Studio builds filled missing zIndex values with (arrayIndex + 1) * 10.
    // Those synthetic values were then mistaken for a manually arranged layer stack
    // on the next load. Recognize that exact signature and migrate it to semantic order.
    // Requiring at least four components avoids treating a tiny, deliberate stack as legacy.
    return rows.length >= 4 && rows.every((row, index) =>
      hasZIndex(row.component) && Number(row.component.zIndex) === (index + 1) * 10
    );
  }

  function normalizeScreenLayers(components) {
    if (!Array.isArray(components) || components.length === 0) return components || [];
    const rows = components.map((component, index) => ({ component, index }));
    const anyExplicitOrder = rows.some(row => hasZIndex(row.component));
    const legacyArrayOrder = isLegacyArrayOrder(rows);

    if (!anyExplicitOrder || legacyArrayOrder) {
      // Unordered models and legacy synthetic-order models both use semantic defaults.
      // Container components must sit behind their content instead of covering elements
      // simply because they were appended later in the original JSON array.
      rows.sort((a, b) => (LAYER_RANK[a.component.type] ?? 45) - (LAYER_RANK[b.component.type] ?? 45) || a.index - b.index);
      rows.forEach((row, index) => { row.component.zIndex = (index + 1) * 10; });
      return components;
    }

    // Preserve an explicit order. Newly added/partially migrated components go to the front;
    // newly created components receive zIndex in makeComponent() and normally use this path.
    let next = rows.reduce((max, row) => hasZIndex(row.component) ? Math.max(max, Number(row.component.zIndex)) : max, 0);
    rows.forEach(row => {
      if (!hasZIndex(row.component)) {
        next += 10;
        row.component.zIndex = next;
      }
    });
    rows.sort((a, b) => Number(a.component.zIndex) - Number(b.component.zIndex) || a.index - b.index);
    rows.forEach((row, index) => { row.component.zIndex = (index + 1) * 10; });
    return components;
  }

  return { LAYER_RANK, normalizeScreenLayers, nextZIndexForNewComponent };
});

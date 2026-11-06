'use strict';

// DOM renderer for the suggestion menu. Kept separate from the pure logic in
// suggestions.cjs. Positions a floating list near the cursor.

function createSuggestionMenu(doc, container) {
  const el = doc.createElement('div');
  el.className = 'gitn-suggest';
  el.style.cssText = [
    'position:absolute',
    'z-index:50',
    'display:none',
    'max-height:200px',
    'overflow-y:auto',
    'min-width:160px',
    'border-radius:6px',
    'padding:4px',
    'font:12px Menlo,Monaco,monospace',
    'box-shadow:0 4px 16px rgba(0,0,0,0.35)',
  ].join(';');
  container.appendChild(el);

  let items = [];
  let selected = 0;
  let onAccept = null;

  function applyTheme(isDark) {
    if (isDark) {
      el.style.background = '#2a2d2e';
      el.style.border = '1px solid #454545';
      el.style.color = '#e0e0e0';
    } else {
      el.style.background = '#ffffff';
      el.style.border = '1px solid #c8c8c8';
      el.style.color = '#1a1a1a';
    }
    render();
  }

  function render() {
    el.innerHTML = '';
    items.forEach((item, index) => {
      const row = doc.createElement('div');
      row.style.cssText = [
        'display:flex',
        'justify-content:space-between',
        'gap:12px',
        'padding:3px 8px',
        'border-radius:4px',
        'cursor:pointer',
        'white-space:nowrap',
      ].join(';');
      if (index === selected) {
        row.style.background = 'rgba(90,150,230,0.35)';
      }
      const name = doc.createElement('span');
      name.textContent = item.displayName;
      row.appendChild(name);
      if (item.detail) {
        const detail = doc.createElement('span');
        detail.textContent = item.detail;
        detail.style.opacity = '0.6';
        detail.style.overflow = 'hidden';
        detail.style.textOverflow = 'ellipsis';
        detail.style.maxWidth = '220px';
        row.appendChild(detail);
      }
      row.addEventListener('mousedown', (event) => {
        event.preventDefault();
        selected = index;
        if (onAccept) onAccept(items[selected]);
      });
      el.appendChild(row);
    });
  }

  return {
    get visible() {
      return el.style.display !== 'none';
    },
    get count() {
      return items.length;
    },
    get selectedItem() {
      return items[selected] || null;
    },
    setAcceptHandler(fn) {
      onAccept = fn;
    },
    applyTheme,
    show(newItems, position) {
      items = newItems;
      selected = 0;
      if (!items.length) {
        this.hide();
        return;
      }
      el.style.left = `${position.x}px`;
      el.style.top = `${position.y}px`;
      el.style.display = 'block';
      render();
    },
    move(delta) {
      if (!items.length) return;
      selected = (((selected + delta) % items.length) + items.length) % items.length;
      render();
    },
    hide() {
      el.style.display = 'none';
      items = [];
      selected = 0;
    },
  };
}

module.exports = { createSuggestionMenu };

/* @ds-bundle: {"format": 4, "namespace": "GitLama", "components": [{"name": "Icon"}, {"name": "Kbd"}, {"name": "Count"}, {"name": "Button"}, {"name": "IconButton"}, {"name": "ToolbarButton"}, {"name": "TextField"}, {"name": "Segmented"}, {"name": "Checkbox"}, {"name": "Switch"}, {"name": "Select"}, {"name": "Menu"}, {"name": "Compass"}, {"name": "SyncBadge"}, {"name": "RepoTabs"}, {"name": "SidebarSection"}, {"name": "SidebarRow"}, {"name": "Island"}, {"name": "StatusGlyph"}, {"name": "RefChip"}, {"name": "Avatar"}, {"name": "Graph"}, {"name": "CommitRow"}, {"name": "FileRow"}, {"name": "DiffHunk"}, {"name": "Banner"}, {"name": "Logbook"}, {"name": "Composer"}, {"name": "Dialog"}, {"name": "SettingsRow"}, {"name": "SettingsGroup"}, {"name": "Palette"}]} */
(function () {
  var React = window.React, h = React.createElement, useState = React.useState, Fragment = React.Fragment;
  var ICONS = {"arrow-down":"<path d=\"M12 5v14\" /> <path d=\"m19 12-7 7-7-7\" />","arrow-left-right":"<path d=\"M8 3 4 7l4 4\" /> <path d=\"M4 7h16\" /> <path d=\"m16 21 4-4-4-4\" /> <path d=\"M20 17H4\" />","arrow-left":"<path d=\"m12 19-7-7 7-7\" /> <path d=\"M19 12H5\" />","arrow-right":"<path d=\"M5 12h14\" /> <path d=\"m12 5 7 7-7 7\" />","arrow-up":"<path d=\"m5 12 7-7 7 7\" /> <path d=\"M12 19V5\" />","back":"<path d=\"m15 18-6-6 6-6\" />","badge-check":"<path d=\"M3.85 8.62a4 4 0 0 1 4.78-4.77 4 4 0 0 1 6.74 0 4 4 0 0 1 4.78 4.78 4 4 0 0 1 0 6.74 4 4 0 0 1-4.77 4.78 4 4 0 0 1-6.75 0 4 4 0 0 1-4.78-4.77 4 4 0 0 1 0-6.76Z\" /> <path d=\"m16 9-5.5 5.5L8 12\" />","ban":"<circle cx=\"12\" cy=\"12\" r=\"10\" /> <path d=\"M4.929 4.929 19.07 19.071\" />","binary":"<rect x=\"14\" y=\"14\" width=\"4\" height=\"6\" rx=\"2\" /> <rect x=\"6\" y=\"4\" width=\"4\" height=\"6\" rx=\"2\" /> <path d=\"M6 20h4\" /> <path d=\"M14 10h4\" /> <path d=\"M6 14h2v6\" /> <path d=\"M14 4h2v6\" />","blame":"<path d=\"M6 22a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h8a2.4 2.4 0 0 1 1.704.706l3.588 3.588A2.4 2.4 0 0 1 20 8v12a2 2 0 0 1-2 2z\" /> <path d=\"M14 2v5a1 1 0 0 0 1 1h5\" /> <path d=\"M16 22a4 4 0 0 0-8 0\" /> <circle cx=\"12\" cy=\"15\" r=\"3\" />","box":"<path d=\"M21 8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16Z\" /> <path d=\"m3.3 7 8.7 5 8.7-5\" /> <path d=\"M12 22V12\" />","branch":"<path d=\"M15 6a9 9 0 0 0-9 9V3\" /> <circle cx=\"18\" cy=\"6\" r=\"3\" /> <circle cx=\"6\" cy=\"18\" r=\"3\" />","brush-cleaning":"<path d=\"m16 22-1-4\" /> <path d=\"M19 14a1 1 0 0 0 1-1v-1a2 2 0 0 0-2-2h-3a1 1 0 0 1-1-1V4a2 2 0 0 0-4 0v5a1 1 0 0 1-1 1H6a2 2 0 0 0-2 2v1a1 1 0 0 0 1 1\" /> <path d=\"M19 14H5l-1.973 6.767A1 1 0 0 0 4 22h16a1 1 0 0 0 .973-1.233z\" /> <path d=\"m8 22 1-4\" />","changes":"<circle cx=\"5\" cy=\"6\" r=\"3\" /> <path d=\"M12 6h5a2 2 0 0 1 2 2v7\" /> <path d=\"m15 9-3-3 3-3\" /> <circle cx=\"19\" cy=\"18\" r=\"3\" /> <path d=\"M12 18H7a2 2 0 0 1-2-2V9\" /> <path d=\"m9 15 3 3-3 3\" />","check":"<path d=\"M20 6 9 17l-5-5\" />","chevron-down":"<path d=\"m6 9 6 6 6-6\" />","chevron-right":"<path d=\"m9 18 6-6-6-6\" />","chevron-up":"<path d=\"m18 15-6-6-6 6\" />","chevrons-down-up":"<path d=\"m7 20 5-5 5 5\" /> <path d=\"m7 4 5 5 5-5\" />","circle-alert":"<circle cx=\"12\" cy=\"12\" r=\"10\" /> <line x1=\"12\" x2=\"12\" y1=\"8\" y2=\"12\" /> <line x1=\"12\" x2=\"12.01\" y1=\"16\" y2=\"16\" />","circle-dot":"<circle cx=\"12\" cy=\"12\" r=\"1\" /> <circle cx=\"12\" cy=\"12\" r=\"10\" />","circle-x":"<circle cx=\"12\" cy=\"12\" r=\"10\" /> <path d=\"m15 9-6 6\" /> <path d=\"m9 9 6 6\" />","close":"<path d=\"M18 6 6 18\" /> <path d=\"m6 6 12 12\" />","cloud":"<path d=\"M17.5 19H9a7 7 0 1 1 6.71-9h1.79a4.5 4.5 0 1 1 0 9Z\" />","co-author":"<path d=\"M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2\" /> <circle cx=\"9\" cy=\"7\" r=\"4\" /> <line x1=\"19\" x2=\"19\" y1=\"8\" y2=\"14\" /> <line x1=\"22\" x2=\"16\" y1=\"11\" y2=\"11\" />","command":"<path d=\"m7 11 2-2-2-2\" /> <path d=\"M11 13h4\" /> <rect width=\"18\" height=\"18\" x=\"3\" y=\"3\" rx=\"2\" ry=\"2\" />","commit-push":"<path d=\"M12 3v12\" /> <path d=\"m17 8-5-5-5 5\" /> <path d=\"M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4\" />","copy":"<rect width=\"14\" height=\"14\" x=\"8\" y=\"8\" rx=\"2\" ry=\"2\" /> <path d=\"M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2\" />","external-link":"<path d=\"M15 3h6v6\" /> <path d=\"M10 14 21 3\" /> <path d=\"M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6\" />","fetch":"<path d=\"M12 17V3\" /> <path d=\"m6 11 6 6 6-6\" /> <path d=\"M19 21H5\" />","file":"<path d=\"M6 22a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h8a2.4 2.4 0 0 1 1.704.706l3.588 3.588A2.4 2.4 0 0 1 20 8v12a2 2 0 0 1-2 2z\" /> <path d=\"M14 2v5a1 1 0 0 0 1 1h5\" />","fixup":"<circle cx=\"12\" cy=\"12\" r=\"3\" /> <line x1=\"3\" x2=\"9\" y1=\"12\" y2=\"12\" /> <line x1=\"15\" x2=\"21\" y1=\"12\" y2=\"12\" />","focus":"<circle cx=\"12\" cy=\"12\" r=\"3\" /> <path d=\"M3 7V5a2 2 0 0 1 2-2h2\" /> <path d=\"M17 3h2a2 2 0 0 1 2 2v2\" /> <path d=\"M21 17v2a2 2 0 0 1-2 2h-2\" /> <path d=\"M7 21H5a2 2 0 0 1-2-2v-2\" />","folder-closed":"<path d=\"M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z\" /> <path d=\"M2 10h20\" />","folder-history":"<path d=\"M16 14v2.2l1.6 1\" /> <path d=\"M7 20H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h3.9a2 2 0 0 1 1.69.9l.81 1.2a2 2 0 0 0 1.67.9H20a2 2 0 0 1 2 2\" /> <circle cx=\"16\" cy=\"16\" r=\"6\" />","folder-open":"<path d=\"m6 14 1.5-2.9A2 2 0 0 1 9.24 10H20a2 2 0 0 1 1.94 2.5l-1.54 6a2 2 0 0 1-1.95 1.5H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h3.9a2 2 0 0 1 1.69.9l.81 1.2a2 2 0 0 0 1.67.9H18a2 2 0 0 1 2 2v2\" />","folder-symlink":"<path d=\"M2 9.35V5a2 2 0 0 1 2-2h3.9a2 2 0 0 1 1.69.9l.81 1.2a2 2 0 0 0 1.67.9H20a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2v-3a2 2 0 0 1 2-2h7\" /> <path d=\"m8 16 3-3-3-3\" />","forward":"<path d=\"m9 18 6-6-6-6\" />","git-fork":"<circle cx=\"12\" cy=\"18\" r=\"3\" /> <circle cx=\"6\" cy=\"6\" r=\"3\" /> <circle cx=\"18\" cy=\"6\" r=\"3\" /> <path d=\"M18 9v2c0 .6-.4 1-1 1H7c-.6 0-1-.4-1-1V9\" /> <path d=\"M12 12v3\" />","git-merge":"<circle cx=\"18\" cy=\"18\" r=\"3\" /> <circle cx=\"6\" cy=\"6\" r=\"3\" /> <path d=\"M6 21V9a9 9 0 0 0 9 9\" />","git-pull-request":"<circle cx=\"18\" cy=\"18\" r=\"3\" /> <circle cx=\"6\" cy=\"6\" r=\"3\" /> <path d=\"M13 6h3a2 2 0 0 1 2 2v7\" /> <line x1=\"6\" x2=\"6\" y1=\"9\" y2=\"21\" />","grip-vertical":"<circle cx=\"9\" cy=\"12\" r=\"1\" /> <circle cx=\"9\" cy=\"5\" r=\"1\" /> <circle cx=\"9\" cy=\"19\" r=\"1\" /> <circle cx=\"15\" cy=\"12\" r=\"1\" /> <circle cx=\"15\" cy=\"5\" r=\"1\" /> <circle cx=\"15\" cy=\"19\" r=\"1\" />","history":"<path d=\"M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8\" /> <path d=\"M3 3v5h5\" /> <path d=\"M12 7v5l4 2\" />","image":"<rect width=\"18\" height=\"18\" x=\"3\" y=\"3\" rx=\"2\" ry=\"2\" /> <circle cx=\"9\" cy=\"9\" r=\"2\" /> <path d=\"m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21\" />","inspect":"<path d=\"M6 22a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h8a2.4 2.4 0 0 1 1.704.706l3.588 3.588A2.4 2.4 0 0 1 20 8v12a2 2 0 0 1-2 2z\" /> <path d=\"M14 2v5a1 1 0 0 0 1 1h5\" /> <circle cx=\"11.5\" cy=\"14.5\" r=\"2.5\" /> <path d=\"M13.3 16.3 15 18\" />","list-filter-plus":"<path d=\"M12 5H2\" /> <path d=\"M6 12h12\" /> <path d=\"M9 19h6\" /> <path d=\"M16 5h6\" /> <path d=\"M19 8V2\" />","list-view":"<path d=\"M3 5h.01\" /> <path d=\"M3 12h.01\" /> <path d=\"M3 19h.01\" /> <path d=\"M8 5h13\" /> <path d=\"M8 12h13\" /> <path d=\"M8 19h13\" />","log-in":"<path d=\"m10 17 5-5-5-5\" /> <path d=\"M15 12H3\" /> <path d=\"M15 3h4a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-4\" />","manage":"<path d=\"M18 19a5 5 0 0 1-5-5v8\" /> <path d=\"M9 20H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h3.9a2 2 0 0 1 1.69.9l.81 1.2a2 2 0 0 0 1.67.9H20a2 2 0 0 1 2 2v5\" /> <circle cx=\"13\" cy=\"12\" r=\"2\" /> <circle cx=\"20\" cy=\"19\" r=\"2\" />","minus":"<path d=\"M5 12h14\" />","more":"<circle cx=\"12\" cy=\"12\" r=\"1\" /> <circle cx=\"19\" cy=\"12\" r=\"1\" /> <circle cx=\"5\" cy=\"12\" r=\"1\" />","panel-left":"<rect width=\"18\" height=\"18\" x=\"3\" y=\"3\" rx=\"2\" /> <path d=\"M9 3v18\" />","pencil":"<path d=\"M21.174 6.812a1 1 0 0 0-3.986-3.987L3.842 16.174a2 2 0 0 0-.5.83l-1.321 4.352a.5.5 0 0 0 .623.622l4.353-1.32a2 2 0 0 0 .83-.497z\" /> <path d=\"m15 5 4 4\" />","plus":"<path d=\"M5 12h14\" /> <path d=\"M12 5v14\" />","pull":"<path d=\"M12 15V3\" /> <path d=\"M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4\" /> <path d=\"m7 10 5 5 5-5\" />","push":"<path d=\"M12 3v12\" /> <path d=\"m17 8-5-5-5 5\" /> <path d=\"M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4\" />","recovery":"<circle cx=\"12\" cy=\"12\" r=\"10\" /> <path d=\"m4.93 4.93 4.24 4.24\" /> <path d=\"m14.83 9.17 4.24-4.24\" /> <path d=\"m14.83 14.83 4.24 4.24\" /> <path d=\"m9.17 14.83-4.24 4.24\" /> <circle cx=\"12\" cy=\"12\" r=\"4\" />","refresh":"<path d=\"M3 12a9 9 0 0 1 9-9 9.75 9.75 0 0 1 6.74 2.74L21 8\" /> <path d=\"M21 3v5h-5\" /> <path d=\"M21 12a9 9 0 0 1-9 9 9.75 9.75 0 0 1-6.74-2.74L3 16\" /> <path d=\"M8 16H3v5\" />","rotate-ccw":"<path d=\"M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8\" /> <path d=\"M3 3v5h5\" />","rotate-cw":"<path d=\"M21 12a9 9 0 1 1-9-9c2.52 0 4.93 1 6.74 2.74L21 8\" /> <path d=\"M21 3v5h-5\" />","save":"<path d=\"M15.2 3a2 2 0 0 1 1.4.6l3.8 3.8a2 2 0 0 1 .6 1.4V19a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2z\" /> <path d=\"M17 21v-7a1 1 0 0 0-1-1H8a1 1 0 0 0-1 1v7\" /> <path d=\"M7 3v4a1 1 0 0 0 1 1h7\" />","settings":"<path d=\"M9.671 4.136a2.34 2.34 0 0 1 4.659 0 2.34 2.34 0 0 0 3.319 1.915 2.34 2.34 0 0 1 2.33 4.033 2.34 2.34 0 0 0 0 3.831 2.34 2.34 0 0 1-2.33 4.033 2.34 2.34 0 0 0-3.319 1.915 2.34 2.34 0 0 1-4.659 0 2.34 2.34 0 0 0-3.32-1.915 2.34 2.34 0 0 1-2.33-4.033 2.34 2.34 0 0 0 0-3.831A2.34 2.34 0 0 1 6.35 6.051a2.34 2.34 0 0 0 3.319-1.915\" /> <circle cx=\"12\" cy=\"12\" r=\"3\" />","shield-check":"<path d=\"M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z\" /> <path d=\"m9 12 2 2 4-4\" />","shortcuts":"<path d=\"M10 8h.01\" /> <path d=\"M12 12h.01\" /> <path d=\"M14 8h.01\" /> <path d=\"M16 12h.01\" /> <path d=\"M18 8h.01\" /> <path d=\"M6 8h.01\" /> <path d=\"M7 16h10\" /> <path d=\"M8 12h.01\" /> <rect width=\"20\" height=\"16\" x=\"2\" y=\"4\" rx=\"2\" />","side-by-side":"<rect width=\"18\" height=\"18\" x=\"3\" y=\"3\" rx=\"2\" /> <path d=\"M12 3v18\" />","signature":"<path d=\"m21 17-2.156-1.868A.5.5 0 0 0 18 15.5v.5a1 1 0 0 1-1 1h-2a1 1 0 0 1-1-1c0-2.545-3.991-3.97-8.5-4a1 1 0 0 0 0 5c4.153 0 4.745-11.295 5.708-13.5a2.5 2.5 0 1 1 3.31 3.284\" /> <path d=\"M3 21h18\" />","skip-forward":"<path d=\"M21 4v16\" /> <path d=\"M6.029 4.285A2 2 0 0 0 3 6v12a2 2 0 0 0 3.029 1.715l9.997-5.998a2 2 0 0 0 .003-3.432z\" />","spellcheck":"<path d=\"m20 15-5.5 5.5L12 18\" /> <path d=\"m4 16 6-12 5.115 10.23\" /> <path d=\"M6 12h8\" />","squash":"<circle cx=\"18\" cy=\"18\" r=\"3\" /> <circle cx=\"6\" cy=\"6\" r=\"3\" /> <path d=\"M6 21V9a9 9 0 0 0 9 9\" />","stage-all":"<path d=\"M4 11V4a2 2 0 0 1 2-2h8a2.4 2.4 0 0 1 1.706.706l3.588 3.588A2.4 2.4 0 0 1 20 8v12a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2v-1\" /> <path d=\"M14 2v5a1 1 0 0 0 1 1h5\" /> <path d=\"M2 15h10\" /> <path d=\"m9 18 3-3-3-3\" />","stash":"<rect width=\"20\" height=\"5\" x=\"2\" y=\"3\" rx=\"1\" /> <path d=\"M4 8v11a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8\" /> <path d=\"M10 12h4\" />","tag":"<path d=\"M12.586 2.586A2 2 0 0 0 11.172 2H4a2 2 0 0 0-2 2v7.172a2 2 0 0 0 .586 1.414l8.704 8.704a2.426 2.426 0 0 0 3.42 0l6.58-6.58a2.426 2.426 0 0 0 0-3.42z\" /> <circle cx=\"7.5\" cy=\"7.5\" r=\".5\" fill=\"currentColor\" />","template":"<rect width=\"18\" height=\"7\" x=\"3\" y=\"3\" rx=\"1\" /> <rect width=\"9\" height=\"7\" x=\"3\" y=\"14\" rx=\"1\" /> <rect width=\"5\" height=\"7\" x=\"16\" y=\"14\" rx=\"1\" />","trash":"<path d=\"M10 11v6\" /> <path d=\"M14 11v6\" /> <path d=\"M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6\" /> <path d=\"M3 6h18\" /> <path d=\"M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2\" />","tree-view":"<path d=\"M8 5h13\" /> <path d=\"M13 12h8\" /> <path d=\"M13 19h8\" /> <path d=\"M3 10a2 2 0 0 0 2 2h3\" /> <path d=\"M3 5v12a2 2 0 0 0 2 2h3\" />","triangle-alert":"<path d=\"m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3\" /> <path d=\"M12 9v4\" /> <path d=\"M12 17h.01\" />","undo":"<path d=\"M9 14 4 9l5-5\" /> <path d=\"M4 9h10.5a5.5 5.5 0 0 1 5.5 5.5a5.5 5.5 0 0 1-5.5 5.5H11\" />","unified-diff":"<rect width=\"18\" height=\"18\" x=\"3\" y=\"3\" rx=\"2\" /> <path d=\"M3 12h18\" />","unstage-all":"<path d=\"M4.226 20.925A2 2 0 0 0 6 22h12a2 2 0 0 0 2-2V8a2.4 2.4 0 0 0-.706-1.706l-3.588-3.588A2.4 2.4 0 0 0 14 2H6a2 2 0 0 0-2 2v3.127\" /> <path d=\"M14 2v5a1 1 0 0 0 1 1h5\" /> <path d=\"m5 11-3 3\" /> <path d=\"m5 17-3-3h10\" />","whitespace":"<path d=\"M13 4v16\" /> <path d=\"M17 4v16\" /> <path d=\"M19 4H9.5a4.5 4.5 0 0 0 0 9H13\" />","wrap":"<path d=\"m16 16-3 3 3 3\" /> <path d=\"M3 12h14.5a1 1 0 0 1 0 7H13\" /> <path d=\"M3 19h6\" /> <path d=\"M3 5h18\" />"};
  function cx() { var o = []; for (var i = 0; i < arguments.length; i++) if (arguments[i]) o.push(arguments[i]); return o.join(' '); }
  function omit(p, keys) { var o = {}; for (var k in p) if (keys.indexOf(k) < 0) o[k] = p[k]; return o; }

  function Icon(p) {
    var inner = ICONS[p.name] || ICONS['circle-dot'];
    return h('svg', { className: cx('ns-icon', p.size === 'sm' && 'sm', p.className), viewBox: '0 0 24 24', fill: 'none', stroke: 'currentColor', strokeWidth: p.stroke || 2, strokeLinecap: 'round', strokeLinejoin: 'round', 'aria-hidden': 'true', style: p.style, dangerouslySetInnerHTML: { __html: inner } });
  }
  Icon.names = Object.keys(ICONS);

  function Kbd(p) {
    var keys = p.keys || [p.children];
    return h('span', { className: 'ns-kbds' }, keys.map(function (k, i) { return h('kbd', { key: i, className: 'ns-kbd' }, k); }));
  }

  function Count(p) { return h('span', { className: cx('ns-count', p.tone) }, p.children); }

  function Button(p) {
    var v = p.variant || 'secondary';
    var rest = omit(p, ['variant', 'size', 'icon', 'kbd', 'loading', 'children', 'className']);
    return h('button', Object.assign({ type: 'button' }, rest, { className: cx('ns-btn', v !== 'secondary' && v, p.size === 'sm' && 'sm', p.className), 'aria-busy': p.loading ? 'true' : undefined }),
      p.loading ? h('span', { className: 'ns-spin', 'aria-hidden': 'true' }) : (p.icon ? h(Icon, { name: p.icon, size: 'sm' }) : null),
      p.children,
      p.kbd ? h(Kbd, { keys: p.kbd }) : null);
  }

  function IconButton(p) {
    var rest = omit(p, ['icon', 'label', 'size', 'active', 'onGround', 'className']);
    return h('button', Object.assign({ type: 'button' }, rest, { className: cx('ns-ibtn', p.size === 'sm' && 'sm', p.active && 'active', p.onGround && 'on-ground', p.className), 'aria-label': p.label, title: p.label, 'aria-pressed': p.active === undefined ? undefined : String(!!p.active) }),
      h(Icon, { name: p.icon, size: p.size === 'sm' ? 'sm' : undefined }));
  }

  function ToolbarButton(p) {
    var btn = h('button', { type: 'button', className: 'ns-tbtn', disabled: p.disabled, title: p.title || p.label },
      h(Icon, { name: p.icon, stroke: 1.75 }), h('span', { className: 'lbl' }, p.label),
      p.badge ? h(Count, { tone: 'polar' }, p.badge) : null);
    if (!p.menu) return btn;
    return h('span', { className: 'ns-tsplit' }, btn, h('button', { type: 'button', className: 'caret', 'aria-label': p.label + ' options' }, h(Icon, { name: 'chevron-down', size: 'sm', style: { width: 10, height: 10 } })));
  }

  function TextField(p) {
    var f = h('label', { className: cx('ns-field', p.variant === 'search' && 'search', p.size === 'sm' && 'sm', p.error && 'error'), style: p.width ? { width: p.width } : undefined },
      p.icon ? h(Icon, { name: p.icon, size: 'sm' }) : null,
      h('input', { placeholder: p.placeholder, defaultValue: p.value, 'aria-label': p.label || p.placeholder, 'aria-invalid': p.error ? 'true' : undefined }),
      p.trailing ? h('span', { className: 'trail' }, p.trailing) : null);
    if (!p.message) return f;
    return h('span', { className: 'ns-fieldwrap' }, f, h('span', { className: cx('msg', p.error && 'err') }, p.message));
  }

  function Segmented(p) {
    var s = useState(p.value !== undefined ? p.value : (p.options[0] && p.options[0].value)); var val = s[0], set = s[1];
    return h('div', { className: cx('ns-seg', p.size === 'sm' && 'sm'), role: 'group', 'aria-label': p.label },
      p.options.map(function (o) {
        return h('button', { key: o.value, type: 'button', 'aria-pressed': String(o.value === val), title: o.title, onClick: function () { set(o.value); p.onChange && p.onChange(o.value); } },
          o.icon ? h(Icon, { name: o.icon, size: 'sm' }) : null, o.label);
      }));
  }

  function Checkbox(p) {
    var s = useState(!!p.checked); var on = s[0], set = s[1];
    var mixed = p.mixed && !on;
    return h('label', { className: cx('ns-check', on && 'on', mixed && 'mixed', p.disabled && 'disabled'), onClick: function (e) { e.preventDefault(); if (!p.disabled) set(!on); } },
      h('span', { className: 'box', role: 'checkbox', tabIndex: p.disabled ? -1 : 0, 'aria-checked': mixed ? 'mixed' : String(on), 'aria-disabled': p.disabled ? 'true' : undefined },
        on ? h(Icon, { name: 'check', stroke: 3 }) : mixed ? h(Icon, { name: 'minus', stroke: 3 }) : null),
      p.children);
  }

  function Switch(p) {
    var s = useState(!!p.checked); var on = s[0], set = s[1];
    return h('label', { className: cx('ns-switch', on && 'on'), onClick: function (e) { e.preventDefault(); set(!on); } },
      h('span', { className: 'track', role: 'switch', tabIndex: 0, 'aria-checked': String(on) }), p.children);
  }

  function Select(p) {
    return h('button', { type: 'button', className: 'ns-select', style: p.width ? { width: p.width } : undefined, 'aria-haspopup': 'listbox' },
      h('span', null, p.value), h(Icon, { name: 'chevron-down', size: 'sm' }));
  }

  function Menu(p) {
    return h('div', { className: 'ns-menu', role: 'menu', style: p.width ? { width: p.width } : undefined }, p.items.map(function (it, i) {
      if (it.type === 'sep') return h('div', { key: i, className: 'sep', role: 'separator' });
      if (it.type === 'header') return h('div', { key: i, className: 'hdr' }, it.label);
      return h('div', { key: i, role: 'menuitem', className: cx('item', it.hl && 'hl', it.danger && 'danger', it.disabled && 'disabled'), 'aria-disabled': it.disabled ? 'true' : undefined },
        it.icon ? h(Icon, { name: it.icon }) : h('span', { style: { width: 16 } }),
        h('span', { className: 'grow' }, it.label),
        it.hint ? h('span', { className: 'hint' }, it.hint) : null,
        it.kbd ? h(Kbd, { keys: it.kbd }) : null);
    }));
  }

  function SyncBadge(p) {
    if (!p.ahead && !p.behind) return p.showZero ? h('span', { className: 'ns-sync' }, h(Icon, { name: 'check', size: 'sm' })) : null;
    return h('span', { className: 'ns-sync', title: (p.ahead || 0) + ' ahead, ' + (p.behind || 0) + ' behind' },
      p.ahead ? h('span', { className: 'ahead' }, h(Icon, { name: 'arrow-up' }), p.ahead) : null,
      p.behind ? h('span', { className: 'behind' }, h(Icon, { name: 'arrow-down' }), p.behind) : null);
  }

  function Compass(p) {
    return h('div', { className: 'ns-compass', role: 'button', tabIndex: 0, 'aria-label': 'Repository ' + p.repo + ', branch ' + p.branch + '. Open command palette' },
      h('span', { className: 'repo' }, p.repo),
      h('span', { className: 'sep' }, '/'),
      h('span', { className: 'branch' }, h(Icon, { name: p.detached ? 'circle-dot' : 'branch', size: 'sm' }), p.branch),
      h('span', { className: 'grow' }),
      p.operation ? h('span', { className: 'op' }, p.operation) :
        h('span', { className: 'state' },
          p.conflicts ? h(Count, { tone: 'conflict' }, p.conflicts + ' conflicts') : null,
          p.dirty ? h('span', { className: 'warn', title: p.dirty + ' changed files' }, '● ' + p.dirty) : null,
          h(SyncBadge, { ahead: p.ahead, behind: p.behind, showZero: true })),
      h(Kbd, { keys: ['⌘', 'K'] }),
      p.operation ? h('span', { className: cx('rule', p.progress === undefined && 'indet'), style: p.progress !== undefined ? { width: (p.progress * 100) + '%' } : undefined }) : null);
  }

  function RepoTabs(p) {
    return h('div', { className: 'ns-tabs', role: 'tablist' },
      p.tabs.map(function (t, i) {
        return h('div', { key: i, role: 'tab', 'aria-selected': String(i === p.active), tabIndex: i === p.active ? 0 : -1, className: cx('ns-tab', i === p.active && 'active'), title: t.hint },
          h('span', { className: 'name' }, t.name), t.dirty ? h('span', { className: 'dirty', 'aria-label': 'uncommitted changes' }) : null,
          h('span', { className: 'x', 'aria-label': 'Close ' + t.name }, h(Icon, { name: 'close' })));
      }),
      h(IconButton, { icon: 'plus', label: 'Open repository', size: 'sm', onGround: true }));
  }

  function SidebarSection(p) {
    return h('div', { role: 'group', 'aria-label': p.title },
      h('div', { className: 'ns-sec' }, h('span', null, p.title), p.count !== undefined ? h(Count, { tone: 'quiet' }, p.count) : null, h('span', { className: 'grow' }),
        p.action ? h(IconButton, { icon: p.action, label: 'Add', size: 'sm', onGround: true }) : null),
      p.children);
  }

  function SidebarRow(p) {
    var pad = 8 + (p.depth || 0) * 14;
    return h('div', { role: 'treeitem', 'aria-selected': p.state ? 'true' : undefined, 'aria-expanded': p.expandable ? String(!!p.open) : undefined, tabIndex: -1, className: cx('ns-srow', p.current && 'current', p.state), style: { paddingLeft: pad } },
      p.expandable ? h(Icon, { name: p.open ? 'chevron-down' : 'chevron-right', className: 'chev' }) : h('span', { className: 'spacer' }),
      h(Icon, { name: p.current ? 'check' : (p.icon || 'branch'), className: 'lead', stroke: p.current ? 2.5 : 2 }),
      h('span', { className: 'name', title: p.name }, p.name),
      h(SyncBadge, { ahead: p.ahead, behind: p.behind }),
      p.count !== undefined ? h(Count, { tone: 'quiet' }, p.count) : null);
  }

  function Island(p) {
    return h('section', { className: cx('ns-island', p.focused && 'focused'), style: p.style, 'aria-label': p.title },
      p.title || p.actions ? h('header', { className: 'ns-ihead' }, p.title ? h('span', { className: 'title' }, p.title) : null, p.subtitle ? h('span', { className: 'ns-meta' }, p.subtitle) : null, h('span', { className: 'grow' }), p.actions) : null,
      h('div', { className: 'ns-ibody', style: p.bodyStyle }, p.children));
  }

  var GLYPH_LABEL = { M: 'Modified', A: 'Added', D: 'Deleted', R: 'Renamed', C: 'Copied', U: 'Conflicted', '?': 'Untracked', '!': 'Ignored' };
  function StatusGlyph(p) {
    var s = p.status || 'M'; var cls = s === '?' ? 'Q' : s === '!' ? 'I' : s;
    return h('span', { className: cx('ns-glyph', cls), role: 'img', 'aria-label': GLYPH_LABEL[s], title: GLYPH_LABEL[s] }, s);
  }

  function RefChip(p) {
    var k = p.kind || 'local';
    var pair = !!p.upstream;
    var lead = k === 'tag' ? null : k === 'remote' ? h(Icon, { name: 'cloud', size: 'sm' }) : k === 'stash' ? h(Icon, { name: 'stash', size: 'sm' }) :
      h('span', { className: 'dot', style: { background: k === 'head' ? 'var(--pane)' : 'var(--lane-' + (p.lane || 1) + ')' } });
    return h('span', { className: cx('ns-ref', k, pair && 'pair'), title: p.title || (p.name + (pair ? ' ⟷ ' + p.upstream + '/' + p.name : '')) },
      lead, h('span', { className: 'nm' }, p.name),
      (p.ahead || p.behind) ? h(SyncBadge, { ahead: p.ahead, behind: p.behind }) : null,
      pair ? h('span', { className: 'up' }, h(Icon, { name: 'cloud', size: 'sm' }), p.upstream) : null);
  }

  var AV = ['1', '2', '6', '5', '7', '4', '3', '8'];
  function Avatar(p) {
    var n = p.name || '?'; var parts = n.split(/\s+/); var ini = (parts[0][0] + (parts.length > 1 ? parts[parts.length - 1][0] : '')).toUpperCase();
    var sum = 0; for (var i = 0; i < n.length; i++) sum += n.charCodeAt(i);
    var lane = p.lane || AV[sum % AV.length];
    return h('span', { className: cx('ns-avatar', p.size === 'lg' && 'lg'), style: { background: 'var(--lane-' + lane + ')' }, 'aria-hidden': 'true' }, ini);
  }

  var PITCH = 14, OFF = 9;
  function gx(c) { return OFF + c * PITCH; }
  function Graph(p) {
    var H = p.height || 28, cy = H / 2, W = OFF * 2 + ((p.cols || 1) - 1) * PITCH;
    var els = (p.segs || []).map(function (s, i) {
      var col = 'var(--lane-' + (s.lane || 1) + ')'; var d;
      if (s.t === 'v') d = 'M' + gx(s.c) + ' 0V' + H;
      else if (s.t === 'top') d = 'M' + gx(s.c) + ' 0V' + cy;
      else if (s.t === 'bot') d = 'M' + gx(s.c) + ' ' + cy + 'V' + H;
      else if (s.t === 'in') d = 'M' + gx(s.from) + ' 0C' + gx(s.from) + ' ' + cy + ' ' + gx(s.to) + ' 0 ' + gx(s.to) + ' ' + cy;
      else if (s.t === 'out') d = 'M' + gx(s.from) + ' ' + cy + 'C' + gx(s.from) + ' ' + H + ' ' + gx(s.to) + ' ' + cy + ' ' + gx(s.to) + ' ' + H;
      else if (s.t === 'x') d = 'M' + gx(s.from) + ' 0C' + gx(s.from) + ' ' + H + ' ' + gx(s.to) + ' 0 ' + gx(s.to) + ' ' + H;
      return h('path', { key: i, className: 'ln', d: d, style: { stroke: col, opacity: s.faint ? 0.3 : 1 } });
    });
    var n = p.node;
    if (n) {
      var nx = gx(n.c), col = 'var(--lane-' + (n.lane || 1) + ')';
      if (n.kind === 'head') {
        els.push(h('circle', { key: 'o', className: 'nd', cx: nx, cy: cy, r: 7, style: { stroke: col, strokeWidth: 1.5 } }));
        els.push(h('circle', { key: 'i', className: 'fill', cx: nx, cy: cy, r: 4, style: { fill: col } }));
      } else if (n.kind === 'merge') {
        els.push(h('circle', { key: 'o', className: 'nd', cx: nx, cy: cy, r: 4.5, style: { stroke: col } }));
        els.push(h('circle', { key: 'i', className: 'fill', cx: nx, cy: cy, r: 1.75, style: { fill: col } }));
      } else if (n.kind === 'stash' || n.kind === 'wip') {
        els.push(h('circle', { key: 'o', className: 'nd', cx: nx, cy: cy, r: 4.5, style: { stroke: n.kind === 'wip' ? 'var(--ink-muted)' : col, strokeDasharray: '2.2 2.2' } }));
      } else {
        els.push(h('circle', { key: 'o', className: 'nd', cx: nx, cy: cy, r: 4.5, style: { stroke: col } }));
      }
    }
    return h('svg', { className: 'ns-graph', width: W, height: H, viewBox: '0 0 ' + W + ' ' + H, 'aria-hidden': 'true' }, els);
  }

  function CommitRow(p) {
    var g = p.graph || {};
    return h('div', { role: 'row', 'aria-selected': p.state ? 'true' : undefined, tabIndex: -1, className: cx('ns-crow', p.state, p.wip && 'wip', p.dim && 'dim'), style: { '--gw': (p.graphWidth || 72) + 'px', '--aw': (p.authorWidth || 132) + 'px' } },
      h(Graph, Object.assign({ cols: 4 }, g)),
      h('span', { className: 'subj' }, p.refs && p.refs.length ? h('span', { className: 'ns-refs' }, p.refs.map(function (r, i) { return h(RefChip, Object.assign({ key: i }, r)); })) : null, h('span', { className: 't', title: p.subject }, p.subject)),
      h('span', { className: 'who' }, p.author ? h(Avatar, { name: p.author }) : null, p.author),
      h('span', { className: 'hash' }, p.hash),
      h('span', { className: 'when' }, p.when));
  }

  function FileRow(p) {
    var parts = (p.path || '').split('/'); var file = parts.pop(); var dir = parts.length ? parts.join('/') + '/' : '';
    return h('div', { role: 'row', tabIndex: -1, 'aria-selected': p.state ? 'true' : undefined, className: cx('ns-frow', p.state), style: p.depth ? { paddingLeft: 8 + p.depth * 14 } : undefined },
      h(StatusGlyph, { status: p.status }),
      h('span', { className: 'path', title: p.path }, p.flat === false ? null : h('span', { className: 'dir' }, dir), file),
      (p.add || p.del) ? h('span', { className: 'stat' }, p.add ? h('span', { className: 'a' }, '+' + p.add) : null, p.del ? h('span', { className: 'd' }, '−' + p.del) : null) : null,
      h('span', { className: 'acts' }, h(IconButton, { icon: p.staged ? 'unstage-all' : 'stage-all', label: p.staged ? 'Unstage' : 'Stage', size: 'sm' }), p.staged ? null : h(IconButton, { icon: 'undo', label: 'Discard changes', size: 'sm' })));
  }

  function marked(text) {
    var out = [], re = /⟦([\s\S]*?)⟧/g, last = 0, m, k = 0;
    while ((m = re.exec(text))) { if (m.index > last) out.push(text.slice(last, m.index)); out.push(h('mark', { key: k++ }, m[1])); last = re.lastIndex; }
    if (last < text.length) out.push(text.slice(last)); return out;
  }
  function DiffHunk(p) {
    return h('div', { className: 'ns-diff', role: 'table', 'aria-label': 'Hunk ' + p.range },
      h('div', { className: 'ns-hunk-h' }, h('span', { className: 'rng' }, p.range), p.context ? h('span', { className: 'ctx' }, p.context) : null, h('span', { className: 'grow' }),
        p.staged ? h(Button, { size: 'sm', variant: 'quiet', icon: 'unstage-all' }, 'Unstage hunk') : h(Fragment, null, h(Button, { size: 'sm', variant: 'danger-quiet', icon: 'undo' }, 'Discard'), h(Button, { size: 'sm', icon: 'stage-all' }, p.picked ? 'Stage lines' : 'Stage hunk'))),
      (p.lines || []).map(function (l, i) {
        var cls = l.t === '+' ? 'add' : l.t === '-' ? 'del' : '';
        return h('div', { key: i, role: 'row', className: cx('ns-dl', cls, l.picked && 'picked') },
          h('span', { className: 'n' }, l.o || ''), h('span', { className: 'n' }, l.n || ''), h('span', { className: 's' }, l.t === '+' ? '+' : l.t === '-' ? '−' : ''), h('span', { className: 'c' }, marked(l.text)));
      }));
  }

  var BANNER_ICON = { info: 'circle-alert', warning: 'triangle-alert', error: 'circle-x', conflict: 'git-merge' };
  function Banner(p) {
    var tone = p.tone || 'info';
    return h('div', { className: cx('ns-banner', tone), role: tone === 'error' ? 'alert' : 'status' },
      h(Icon, { name: p.icon || BANNER_ICON[tone] }),
      h('div', { className: 'body' }, p.title ? h('b', null, p.title + ' ') : null, p.children),
      p.actions ? h('div', { className: 'acts' }, p.actions) : null);
  }

  var LOG_ICON = { ok: 'check', warn: 'triangle-alert', fail: 'close', run: 'refresh', idle: 'minus' };
  function Logbook(p) {
    return h('div', { className: 'ns-logbook', role: 'log', 'aria-label': 'Logbook' },
      h('div', { className: 'top' }, h('span', { className: 'title' }, 'Logbook'), h(Segmented, { size: 'sm', options: [{ value: 'all', label: 'All' }, { value: 'mine', label: 'Mine' }, { value: 'bg', label: 'Background' }] }), h(IconButton, { icon: 'brush-cleaning', label: 'Clear finished', size: 'sm' })),
      (p.entries || []).map(function (e, i) {
        return h('div', { key: i, className: cx('ns-lrow', e.status) },
          h('span', { className: 'mk' }, e.status === 'run' ? h('span', { className: 'ns-spin', style: { width: 10, height: 10 } }) : h(Icon, { name: LOG_ICON[e.status] || 'minus', stroke: 3 })),
          h('div', { className: 'what' }, h('div', null, h('b', null, e.verb), e.target ? ' ' + e.target : ''), e.meta ? h('div', { className: 'meta' }, e.meta) : null),
          h('span', { className: 't' }, e.time),
          e.command || e.output ? h('div', { className: 'out' }, e.command ? h('div', { className: 'cmd' }, '$ ' + e.command) : null, e.output || null) : null);
      }));
  }

  function Composer(p) {
    var s = useState(p.subject || ''); var subj = s[0], set = s[1];
    var n = subj.length;
    return h('div', { className: 'ns-composer' },
      h('div', { className: 'subj' }, h('input', { value: subj, onChange: function (e) { set(e.target.value); }, placeholder: 'Summary (required)', 'aria-label': 'Commit summary' }), h('span', { className: cx('cnt', n > 72 ? 'over' : n > 50 ? 'warn' : '') }, n + '/50')),
      h('textarea', { defaultValue: p.body, placeholder: 'Description', 'aria-label': 'Commit description', rows: 3 }),
      h('div', { className: 'row' },
        h(Checkbox, { checked: p.amend }, 'Amend'),
        h('span', { className: 'meta' }, p.staged + ' files staged'),
        h('span', { className: 'grow' }),
        h(Button, { variant: 'secondary', kbd: ['⌘', '⇧', '↵'] }, 'Commit & push'),
        h(Button, { variant: 'primary', kbd: ['⌘', '↵'], disabled: n === 0 }, 'Commit to ' + (p.branch || 'main'))));
  }

  function Dialog(p) {
    return h('div', { className: 'ns-dialog', role: 'dialog', 'aria-modal': 'true', 'aria-label': p.title },
      h('h2', null, p.title), p.description ? h('p', { className: 'desc' }, p.description) : null, p.children,
      h('div', { className: 'foot' }, p.aside ? p.aside : null, h('span', { className: 'grow' }), p.actions));
  }

  function SettingsRow(p) {
    return h('div', { className: 'ns-srow2' }, h('div', { className: 'lbl' }, p.label), h('div', { className: 'ctl' }, p.children, p.help ? h('div', { className: 'help' }, p.help) : null));
  }
  function SettingsGroup(p) { return h('div', { className: 'ns-settings', style: p.style }, p.children); }

  function Palette(p) {
    var items = [];
    (p.groups || []).forEach(function (g) { items.push({ type: 'header', label: g.title }); g.items.forEach(function (it) { items.push(it); }); });
    return h('div', { className: 'ns-palette', role: 'dialog', 'aria-label': 'Command palette' },
      h('div', { className: 'q' }, h(Icon, { name: 'command' }), h('span', { className: 'typed' }, p.query, h('span', { className: 'caret' })), h(Kbd, { keys: ['esc'] })),
      h('div', { className: 'list' }, h(Menu, { items: items.map(function (it) { return it.type ? it : Object.assign({}, it, { label: it.label.indexOf('⟦') >= 0 ? h('span', null, marked(it.label)) : it.label }); }) })),
      h('div', { className: 'foot' }, h('span', null, h(Kbd, { keys: ['↑', '↓'] }), 'Move'), h('span', null, h(Kbd, { keys: ['↵'] }), 'Run'), h('span', null, h(Kbd, { keys: ['⌘', '↵'] }), 'Run in background'), h('span', null, h(Kbd, { keys: ['tab'] }), 'Scope')));
  }

  window.GitLama = {
    Icon: Icon, Kbd: Kbd, Count: Count, Button: Button, IconButton: IconButton, ToolbarButton: ToolbarButton,
    TextField: TextField, Segmented: Segmented, Checkbox: Checkbox, Switch: Switch, Select: Select, Menu: Menu,
    Compass: Compass, SyncBadge: SyncBadge, RepoTabs: RepoTabs, SidebarSection: SidebarSection, SidebarRow: SidebarRow,
    Island: Island, StatusGlyph: StatusGlyph, RefChip: RefChip, Avatar: Avatar, Graph: Graph, CommitRow: CommitRow,
    FileRow: FileRow, DiffHunk: DiffHunk, Banner: Banner, Logbook: Logbook, Composer: Composer, Dialog: Dialog,
    SettingsRow: SettingsRow, SettingsGroup: SettingsGroup, Palette: Palette
  };
})();

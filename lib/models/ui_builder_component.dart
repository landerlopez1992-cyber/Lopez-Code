import 'package:flutter/material.dart';

/// Componente arrastrable del UI Builder (HTML · estilo FlutterFlow).
class UiBuilderComponent {
  final String id;
  final String label;
  final String category;
  final IconData icon;
  final String htmlSnippet;

  const UiBuilderComponent({
    required this.id,
    required this.label,
    required this.category,
    required this.icon,
    required this.htmlSnippet,
  });

  /// Orden de categorías (FlutterFlow-like).
  static const List<String> categoryOrder = [
    'De uso frecuente',
    'Layout',
    'Base',
    'Página',
    'Formulario',
    'Media',
  ];

  /// Catálogo amplio — HTML equivalente a widgets FlutterFlow.
  static const List<UiBuilderComponent> catalog = [
    // ── De uso frecuente ──────────────────────────────────────────
    UiBuilderComponent(
      id: 'text',
      label: 'Text',
      category: 'De uso frecuente',
      icon: Icons.text_fields,
      htmlSnippet: '''
<p data-voryxel="text" style="margin:8px 0;font-family:system-ui,sans-serif;font-size:1rem;color:#111;line-height:1.5;">
  Texto
</p>''',
    ),
    UiBuilderComponent(
      id: 'column',
      label: 'Column',
      category: 'De uso frecuente',
      icon: Icons.view_agenda_outlined,
      htmlSnippet: '''
<div data-voryxel="column" data-voryxel-container="1"
  style="display:flex;flex-direction:column;align-items:stretch;gap:12px;margin:12px 0;padding:12px;
  border:1px dashed #94a3b8;border-radius:10px;min-height:72px;font-family:system-ui,sans-serif;">
  <p data-voryxel-placeholder="1" style="margin:0;color:#64748b;font-size:0.85rem;text-align:center;">Column — suelta elementos aquí</p>
</div>''',
    ),
    UiBuilderComponent(
      id: 'row',
      label: 'Row',
      category: 'De uso frecuente',
      icon: Icons.view_week_outlined,
      htmlSnippet: '''
<div data-voryxel="row" data-voryxel-container="1"
  style="display:flex;flex-direction:row;flex-wrap:wrap;align-items:center;justify-content:flex-start;gap:12px;margin:12px 0;padding:12px;
  border:1px dashed #94a3b8;border-radius:10px;min-height:56px;font-family:system-ui,sans-serif;">
  <span data-voryxel-placeholder="1" style="color:#64748b;font-size:0.85rem;">Row — suelta aquí</span>
</div>''',
    ),
    UiBuilderComponent(
      id: 'container',
      label: 'Container',
      category: 'De uso frecuente',
      icon: Icons.check_box_outline_blank,
      htmlSnippet: '''
<div data-voryxel="container" data-voryxel-container="1"
  style="display:flex;flex-direction:column;align-items:center;justify-content:center;gap:8px;margin:12px 0;padding:20px;
  border:2px dashed #94a3b8;border-radius:12px;min-height:88px;font-family:system-ui,sans-serif;color:#64748b;">
  <span data-voryxel-placeholder="1">Container</span>
</div>''',
    ),
    UiBuilderComponent(
      id: 'image',
      label: 'Image',
      category: 'De uso frecuente',
      icon: Icons.image_outlined,
      htmlSnippet: '''
<img data-voryxel="image" src="https://picsum.photos/640/360" alt="Image"
  style="display:block;width:100%;max-width:100%;height:auto;margin:0;border-radius:12px;object-fit:cover;" />''',
    ),
    UiBuilderComponent(
      id: 'button',
      label: 'Button',
      category: 'De uso frecuente',
      icon: Icons.smart_button,
      htmlSnippet: '''
<a data-voryxel="button" href="#"
  style="display:inline-block;margin:8px 0;padding:12px 20px;border:none;border-radius:8px;
  background:#2563eb;color:#fff;font-size:1rem;font-weight:600;cursor:pointer;
  font-family:system-ui,sans-serif;text-decoration:none;text-align:center;">
  Button
</a>''',
    ),

    // ── Layout ────────────────────────────────────────────────────
    UiBuilderComponent(
      id: 'layout_container',
      label: 'Container',
      category: 'Layout',
      icon: Icons.check_box_outline_blank,
      htmlSnippet: '''
<div data-voryxel="container" data-voryxel-container="1"
  style="display:flex;flex-direction:column;align-items:center;justify-content:center;gap:8px;margin:12px 0;padding:20px;
  border:2px dashed #94a3b8;border-radius:12px;min-height:88px;font-family:system-ui,sans-serif;color:#64748b;">
  <span data-voryxel-placeholder="1">Container</span>
</div>''',
    ),
    UiBuilderComponent(
      id: 'layout_row',
      label: 'Row',
      category: 'Layout',
      icon: Icons.view_week_outlined,
      htmlSnippet: '''
<div data-voryxel="row" data-voryxel-container="1"
  style="display:flex;flex-direction:row;flex-wrap:wrap;align-items:center;justify-content:flex-start;gap:12px;margin:12px 0;padding:12px;
  border:1px dashed #94a3b8;border-radius:10px;min-height:56px;font-family:system-ui,sans-serif;">
  <span data-voryxel-placeholder="1" style="color:#64748b;font-size:0.85rem;">Row — suelta aquí</span>
</div>''',
    ),
    UiBuilderComponent(
      id: 'layout_column',
      label: 'Column',
      category: 'Layout',
      icon: Icons.view_agenda_outlined,
      htmlSnippet: '''
<div data-voryxel="column" data-voryxel-container="1"
  style="display:flex;flex-direction:column;align-items:stretch;gap:12px;margin:12px 0;padding:12px;
  border:1px dashed #94a3b8;border-radius:10px;min-height:72px;font-family:system-ui,sans-serif;">
  <p data-voryxel-placeholder="1" style="margin:0;color:#64748b;font-size:0.85rem;text-align:center;">Column — suelta elementos aquí</p>
</div>''',
    ),
    UiBuilderComponent(
      id: 'stack',
      label: 'Stack',
      category: 'Layout',
      icon: Icons.layers_outlined,
      htmlSnippet: '''
<div data-voryxel="stack" data-voryxel-container="1"
  style="position:relative;display:block;margin:12px 0;min-height:140px;border-radius:12px;overflow:hidden;
  border:1px dashed #94a3b8;background:#f8fafc;font-family:system-ui,sans-serif;">
  <span data-voryxel-placeholder="1" style="position:absolute;inset:0;display:flex;align-items:center;justify-content:center;color:#64748b;font-size:0.85rem;">Stack — suelta aquí</span>
</div>''',
    ),
    UiBuilderComponent(
      id: 'card',
      label: 'Card',
      category: 'Layout',
      icon: Icons.crop_landscape,
      htmlSnippet: '''
<div data-voryxel="card" data-voryxel-container="1"
  style="display:flex;flex-direction:column;gap:10px;margin:16px 0;padding:20px;max-width:360px;width:100%;
  background:#fff;border:1px solid #e5e7eb;border-radius:12px;box-shadow:0 4px 14px rgba(0,0,0,0.08);
  font-family:system-ui,sans-serif;box-sizing:border-box;">
  <span data-voryxel-placeholder="1" style="color:#64748b;font-size:0.85rem;">Card — suelta elementos aquí</span>
</div>''',
    ),
    UiBuilderComponent(
      id: 'listview',
      label: 'ListView',
      category: 'Layout',
      icon: Icons.view_list,
      htmlSnippet: '''
<ul data-voryxel="listview" data-voryxel-container="1"
  style="list-style:none;margin:12px 0;padding:8px;min-height:64px;font-family:system-ui,sans-serif;
  border:1px dashed #94a3b8;border-radius:10px;overflow:hidden;">
  <li data-voryxel-placeholder="1" style="padding:12px 14px;color:#64748b;font-size:0.85rem;">ListView — suelta ítems aquí</li>
</ul>''',
    ),
    UiBuilderComponent(
      id: 'gridview',
      label: 'GridView',
      category: 'Layout',
      icon: Icons.grid_view,
      htmlSnippet: '''
<div data-voryxel="gridview" data-voryxel-container="1"
  style="display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px;margin:12px 0;padding:8px;
  min-height:96px;border:1px dashed #94a3b8;border-radius:10px;font-family:system-ui,sans-serif;">
  <span data-voryxel-placeholder="1" style="grid-column:1/-1;color:#64748b;font-size:0.85rem;text-align:center;padding:24px 0;">GridView — suelta aquí</span>
</div>''',
    ),
    UiBuilderComponent(
      id: 'spacer',
      label: 'Spacer',
      category: 'Layout',
      icon: Icons.swap_vert,
      htmlSnippet: '''
<div data-voryxel="spacer" style="flex:1;min-height:24px;height:32px;" aria-hidden="true"></div>''',
    ),
    UiBuilderComponent(
      id: 'divider',
      label: 'Divider',
      category: 'Layout',
      icon: Icons.horizontal_rule,
      htmlSnippet: '''
<hr data-voryxel="divider" style="border:none;border-top:1px solid #e5e7eb;margin:16px 0;width:100%;" />''',
    ),
    UiBuilderComponent(
      id: 'vertical_divider',
      label: 'V.Divider',
      category: 'Layout',
      icon: Icons.vertical_distribute,
      htmlSnippet: '''
<div data-voryxel="vertical_divider" style="display:inline-block;width:1px;align-self:stretch;min-height:40px;background:#e5e7eb;margin:0 12px;" aria-hidden="true"></div>''',
    ),
    UiBuilderComponent(
      id: 'wrap',
      label: 'Wrap',
      category: 'Layout',
      icon: Icons.wrap_text,
      htmlSnippet: '''
<div data-voryxel="wrap" data-voryxel-container="1"
  style="display:flex;flex-wrap:wrap;align-items:center;gap:8px;margin:12px 0;padding:12px;border:1px dashed #94a3b8;
  border-radius:10px;min-height:48px;font-family:system-ui,sans-serif;">
  <span data-voryxel-placeholder="1" style="color:#64748b;font-size:0.85rem;">Wrap — suelta aquí</span>
</div>''',
    ),
    UiBuilderComponent(
      id: 'expandable',
      label: 'Expandable',
      category: 'Layout',
      icon: Icons.open_in_full,
      htmlSnippet: '''
<details data-voryxel="expandable" data-voryxel-container="1"
  style="margin:12px 0;padding:12px 14px;border:1px solid #e5e7eb;border-radius:10px;font-family:system-ui,sans-serif;background:#fff;">
  <summary style="cursor:pointer;font-weight:600;color:#111;">Expandable</summary>
  <div data-voryxel-placeholder="1" style="margin:10px 0 0;color:#64748b;font-size:0.85rem;">Suelta contenido aquí</div>
</details>''',
    ),
    UiBuilderComponent(
      id: 'tabbar',
      label: 'TabBar',
      category: 'Layout',
      icon: Icons.tab,
      htmlSnippet: '''
<div data-voryxel="tabbar" data-voryxel-container="1" style="margin:12px 0;font-family:system-ui,sans-serif;">
  <div style="display:flex;gap:0;border-bottom:1px solid #e5e7eb;">
    <button type="button" style="padding:10px 16px;border:none;background:transparent;border-bottom:2px solid #2563eb;color:#2563eb;font-weight:600;cursor:pointer;">Tab 1</button>
    <button type="button" style="padding:10px 16px;border:none;background:transparent;color:#64748b;cursor:pointer;">Tab 2</button>
    <button type="button" style="padding:10px 16px;border:none;background:transparent;color:#64748b;cursor:pointer;">Tab 3</button>
  </div>
  <div data-voryxel-placeholder="1" style="padding:16px;color:#64748b;font-size:0.85rem;">Suelta contenido de pestaña aquí</div>
</div>''',
    ),
    UiBuilderComponent(
      id: 'pageview',
      label: 'PageView',
      category: 'Layout',
      icon: Icons.view_carousel_outlined,
      htmlSnippet: '''
<div data-voryxel="pageview" data-voryxel-container="1"
  style="margin:12px 0;display:flex;gap:12px;overflow-x:auto;scroll-snap-type:x mandatory;padding:8px;min-height:120px;
  border:1px dashed #94a3b8;border-radius:12px;font-family:system-ui,sans-serif;">
  <span data-voryxel-placeholder="1" style="color:#64748b;font-size:0.85rem;padding:28px;">PageView — suelta páginas aquí</span>
</div>''',
    ),
    UiBuilderComponent(
      id: 'carousel',
      label: 'Carousel',
      category: 'Layout',
      icon: Icons.view_carousel,
      htmlSnippet: '''
<div data-voryxel="carousel" data-voryxel-container="1"
  style="margin:12px 0;display:flex;gap:10px;overflow-x:auto;padding:8px;min-height:100px;
  border:1px dashed #94a3b8;border-radius:12px;font-family:system-ui,sans-serif;">
  <span data-voryxel-placeholder="1" style="color:#64748b;font-size:0.85rem;padding:24px;">Carousel — suelta imágenes aquí</span>
</div>''',
    ),

    // ── Base ──────────────────────────────────────────────────────
    UiBuilderComponent(
      id: 'base_text',
      label: 'Text',
      category: 'Base',
      icon: Icons.text_fields,
      htmlSnippet: '''
<p data-voryxel="text" style="margin:8px 0;font-family:system-ui,sans-serif;font-size:1rem;color:#111;line-height:1.5;">Texto</p>''',
    ),
    UiBuilderComponent(
      id: 'richtext',
      label: 'RichText',
      category: 'Base',
      icon: Icons.notes,
      htmlSnippet: '''
<p data-voryxel="richtext" style="margin:8px 0;font-family:system-ui,sans-serif;line-height:1.55;color:#333;">
  Texto con <strong>negrita</strong>, <em>cursiva</em> y <a href="#" style="color:#2563eb;">enlace</a>.
</p>''',
    ),
    UiBuilderComponent(
      id: 'heading',
      label: 'Heading',
      category: 'Base',
      icon: Icons.title,
      htmlSnippet: '''
<section data-voryxel="heading" style="margin:16px 0;font-family:system-ui,sans-serif;">
  <h1 style="margin:0;font-size:2rem;color:#111;">Título</h1>
  <p style="margin:8px 0 0;color:#555;">Subtítulo breve</p>
</section>''',
    ),
    UiBuilderComponent(
      id: 'base_image',
      label: 'Image',
      category: 'Base',
      icon: Icons.image_outlined,
      htmlSnippet: '''
<img data-voryxel="image" src="https://picsum.photos/640/360" alt="Image"
  style="display:block;max-width:100%;height:auto;margin:12px 0;border-radius:12px;" />''',
    ),
    UiBuilderComponent(
      id: 'circle_image',
      label: 'CircleImage',
      category: 'Base',
      icon: Icons.account_circle_outlined,
      htmlSnippet: '''
<img data-voryxel="circle_image" src="https://picsum.photos/120/120" alt="Avatar"
  style="display:block;width:72px;height:72px;border-radius:50%;object-fit:cover;margin:12px 0;" />''',
    ),
    UiBuilderComponent(
      id: 'icon',
      label: 'Icon',
      category: 'Base',
      icon: Icons.star_outline,
      htmlSnippet: '''
<span data-voryxel="icon" aria-hidden="true"
  style="display:inline-flex;align-items:center;justify-content:center;width:40px;height:40px;
  border-radius:10px;background:#e2e8f0;color:#0f172a;font-size:1.25rem;margin:8px 0;">★</span>''',
    ),
    UiBuilderComponent(
      id: 'base_button',
      label: 'Button',
      category: 'Base',
      icon: Icons.smart_button,
      htmlSnippet: '''
<a data-voryxel="button" href="#"
  style="display:inline-block;margin:8px 0;padding:12px 20px;border:none;border-radius:8px;
  background:#2563eb;color:#fff;font-size:1rem;font-weight:600;cursor:pointer;
  font-family:system-ui,sans-serif;text-decoration:none;">Button</a>''',
    ),
    UiBuilderComponent(
      id: 'icon_button',
      label: 'IconButton',
      category: 'Base',
      icon: Icons.add_box_outlined,
      htmlSnippet: '''
<button data-voryxel="icon_button" type="button" aria-label="Acción"
  style="display:inline-flex;align-items:center;justify-content:center;width:40px;height:40px;
  border:none;border-radius:10px;background:#2563eb;color:#fff;font-size:1.25rem;cursor:pointer;margin:8px 0;">+</button>''',
    ),
    UiBuilderComponent(
      id: 'list_tile',
      label: 'ListTile',
      category: 'Base',
      icon: Icons.list_alt,
      htmlSnippet: '''
<div data-voryxel="list_tile"
  style="display:flex;align-items:center;gap:12px;padding:12px 14px;margin:8px 0;border:1px solid #e5e7eb;
  border-radius:10px;background:#fff;font-family:system-ui,sans-serif;">
  <div style="width:40px;height:40px;border-radius:10px;background:#e2e8f0;"></div>
  <div style="flex:1;min-width:0;">
    <div style="font-weight:600;color:#111;">Título</div>
    <div style="font-size:0.85rem;color:#64748b;">Subtítulo</div>
  </div>
  <span style="color:#94a3b8;">›</span>
</div>''',
    ),
    UiBuilderComponent(
      id: 'link',
      label: 'Link',
      category: 'Base',
      icon: Icons.link,
      htmlSnippet: '''
<a data-voryxel="link" href="https://example.com" target="_blank" rel="noopener"
  style="color:#2563eb;font-family:system-ui,sans-serif;text-decoration:underline;">Enlace</a>''',
    ),
    UiBuilderComponent(
      id: 'badge',
      label: 'Badge',
      category: 'Base',
      icon: Icons.mark_chat_unread_outlined,
      htmlSnippet: '''
<span data-voryxel="badge"
  style="display:inline-block;padding:4px 10px;border-radius:999px;background:#dbeafe;color:#1d4ed8;
  font-size:0.75rem;font-weight:700;font-family:system-ui,sans-serif;">Badge</span>''',
    ),
    UiBuilderComponent(
      id: 'chip',
      label: 'Chip',
      category: 'Base',
      icon: Icons.label_outline,
      htmlSnippet: '''
<span data-voryxel="chip"
  style="display:inline-flex;align-items:center;gap:6px;padding:6px 12px;border-radius:999px;
  background:#f1f5f9;color:#0f172a;font-size:0.85rem;font-family:system-ui,sans-serif;">Chip</span>''',
    ),

    // ── Página ────────────────────────────────────────────────────
    UiBuilderComponent(
      id: 'navbar',
      label: 'AppBar',
      category: 'Página',
      icon: Icons.menu,
      htmlSnippet: '''
<nav data-voryxel="navbar"
  style="display:flex;align-items:center;justify-content:space-between;gap:16px;
  padding:14px 20px;margin:0 0 16px;background:#0f172a;color:#fff;border-radius:10px;
  font-family:system-ui,sans-serif;">
  <strong>Mi Sitio</strong>
  <div style="display:flex;gap:16px;font-size:0.95rem;">
    <a href="#" style="color:#cbd5e1;text-decoration:none;">Inicio</a>
    <a href="#" style="color:#cbd5e1;text-decoration:none;">Servicios</a>
    <a href="#" style="color:#cbd5e1;text-decoration:none;">Contacto</a>
  </div>
</nav>''',
    ),
    UiBuilderComponent(
      id: 'hero',
      label: 'Hero',
      category: 'Página',
      icon: Icons.view_agenda_outlined,
      htmlSnippet: '''
<section data-voryxel="hero"
  style="margin:0 0 24px;padding:48px 24px;border-radius:16px;text-align:center;
  background:linear-gradient(135deg,#0f172a,#1e3a8a);color:#fff;font-family:system-ui,sans-serif;">
  <h2 style="margin:0 0 12px;font-size:2rem;">Hero section</h2>
  <p style="margin:0 0 20px;opacity:0.9;">Sección destacada para tu landing.</p>
  <a href="#" style="display:inline-block;padding:12px 22px;border-radius:8px;background:#22c55e;color:#04140a;font-weight:700;text-decoration:none;">Call to action</a>
</section>''',
    ),
    UiBuilderComponent(
      id: 'bottom_nav',
      label: 'BottomNav',
      category: 'Página',
      icon: Icons.dock_outlined,
      htmlSnippet: '''
<nav data-voryxel="bottom_nav"
  style="display:flex;justify-content:space-around;align-items:center;padding:10px 8px;margin:16px 0 0;
  background:#0f172a;color:#cbd5e1;border-radius:14px;font-family:system-ui,sans-serif;font-size:0.75rem;">
  <a href="#" style="color:#fff;text-decoration:none;text-align:center;">Home</a>
  <a href="#" style="color:#94a3b8;text-decoration:none;text-align:center;">Search</a>
  <a href="#" style="color:#94a3b8;text-decoration:none;text-align:center;">Profile</a>
</nav>''',
    ),
    UiBuilderComponent(
      id: 'drawer',
      label: 'Drawer',
      category: 'Página',
      icon: Icons.menu_open,
      htmlSnippet: '''
<aside data-voryxel="drawer"
  style="width:100%;max-width:260px;padding:20px;margin:12px 0;background:#0f172a;color:#e2e8f0;
  border-radius:12px;font-family:system-ui,sans-serif;">
  <strong style="display:block;margin-bottom:16px;">Menú</strong>
  <a href="#" style="display:block;padding:8px 0;color:#cbd5e1;text-decoration:none;">Inicio</a>
  <a href="#" style="display:block;padding:8px 0;color:#cbd5e1;text-decoration:none;">Perfil</a>
  <a href="#" style="display:block;padding:8px 0;color:#cbd5e1;text-decoration:none;">Ajustes</a>
</aside>''',
    ),
    UiBuilderComponent(
      id: 'footer',
      label: 'Footer',
      category: 'Página',
      icon: Icons.horizontal_rule,
      htmlSnippet: '''
<footer data-voryxel="footer"
  style="margin:24px 0 0;padding:24px;border-radius:12px;background:#0f172a;color:#94a3b8;
  text-align:center;font-family:system-ui,sans-serif;font-size:0.9rem;">
  © 2026 Mi Sitio · Todos los derechos reservados
</footer>''',
    ),
    UiBuilderComponent(
      id: 'fab',
      label: 'FAB',
      category: 'Página',
      icon: Icons.add_circle_outline,
      htmlSnippet: '''
<button data-voryxel="fab" type="button" aria-label="Acción flotante"
  style="display:inline-flex;align-items:center;justify-content:center;width:56px;height:56px;
  border:none;border-radius:50%;background:#2563eb;color:#fff;font-size:1.5rem;cursor:pointer;
  box-shadow:0 8px 20px rgba(37,99,235,0.35);margin:12px 0;">+</button>''',
    ),

    // ── Formulario ────────────────────────────────────────────────
    UiBuilderComponent(
      id: 'input',
      label: 'TextField',
      category: 'Formulario',
      icon: Icons.input,
      htmlSnippet: '''
<label data-voryxel="input" style="display:block;margin:12px 0;font-family:system-ui,sans-serif;">
  <span style="display:block;margin-bottom:6px;color:#444;font-size:0.9rem;">Campo</span>
  <input type="text" placeholder="Escribe…"
    style="width:100%;max-width:320px;padding:10px 12px;border:1px solid #ccc;border-radius:8px;font-size:1rem;box-sizing:border-box;" />
</label>''',
    ),
    UiBuilderComponent(
      id: 'textarea',
      label: 'Textarea',
      category: 'Formulario',
      icon: Icons.notes,
      htmlSnippet: '''
<label data-voryxel="textarea" style="display:block;margin:12px 0;font-family:system-ui,sans-serif;">
  <span style="display:block;margin-bottom:6px;color:#444;font-size:0.9rem;">Mensaje</span>
  <textarea rows="4" placeholder="Tu mensaje…"
    style="width:100%;max-width:420px;padding:10px 12px;border:1px solid #ccc;border-radius:8px;font-size:1rem;box-sizing:border-box;"></textarea>
</label>''',
    ),
    UiBuilderComponent(
      id: 'checkbox',
      label: 'Checkbox',
      category: 'Formulario',
      icon: Icons.check_box_outlined,
      htmlSnippet: '''
<label data-voryxel="checkbox" style="display:flex;align-items:center;gap:8px;margin:10px 0;font-family:system-ui,sans-serif;color:#333;">
  <input type="checkbox" /> Acepto los términos
</label>''',
    ),
    UiBuilderComponent(
      id: 'switch',
      label: 'Switch',
      category: 'Formulario',
      icon: Icons.toggle_on_outlined,
      htmlSnippet: '''
<label data-voryxel="switch" style="display:flex;align-items:center;justify-content:space-between;gap:12px;max-width:280px;margin:12px 0;font-family:system-ui,sans-serif;color:#333;">
  <span>Activar</span>
  <input type="checkbox" role="switch" />
</label>''',
    ),
    UiBuilderComponent(
      id: 'dropdown',
      label: 'Dropdown',
      category: 'Formulario',
      icon: Icons.arrow_drop_down_circle_outlined,
      htmlSnippet: '''
<label data-voryxel="dropdown" style="display:block;margin:12px 0;font-family:system-ui,sans-serif;">
  <span style="display:block;margin-bottom:6px;color:#444;font-size:0.9rem;">Opción</span>
  <select style="width:100%;max-width:280px;padding:10px 12px;border:1px solid #ccc;border-radius:8px;font-size:1rem;background:#fff;">
    <option>Opción 1</option>
    <option>Opción 2</option>
    <option>Opción 3</option>
  </select>
</label>''',
    ),
    UiBuilderComponent(
      id: 'radio',
      label: 'Radio',
      category: 'Formulario',
      icon: Icons.radio_button_checked,
      htmlSnippet: '''
<fieldset data-voryxel="radio" style="margin:12px 0;padding:12px;border:1px solid #e5e7eb;border-radius:10px;font-family:system-ui,sans-serif;">
  <legend style="padding:0 6px;color:#444;font-size:0.9rem;">Elige</legend>
  <label style="display:flex;gap:8px;margin:6px 0;"><input type="radio" name="voryxel_radio" checked /> A</label>
  <label style="display:flex;gap:8px;margin:6px 0;"><input type="radio" name="voryxel_radio" /> B</label>
</fieldset>''',
    ),
    UiBuilderComponent(
      id: 'slider',
      label: 'Slider',
      category: 'Formulario',
      icon: Icons.tune,
      htmlSnippet: '''
<label data-voryxel="slider" style="display:block;margin:12px 0;font-family:system-ui,sans-serif;max-width:320px;">
  <span style="display:block;margin-bottom:6px;color:#444;font-size:0.9rem;">Valor</span>
  <input type="range" min="0" max="100" value="40" style="width:100%;" />
</label>''',
    ),
    UiBuilderComponent(
      id: 'date_picker',
      label: 'DatePicker',
      category: 'Formulario',
      icon: Icons.calendar_today_outlined,
      htmlSnippet: '''
<label data-voryxel="date_picker" style="display:block;margin:12px 0;font-family:system-ui,sans-serif;">
  <span style="display:block;margin-bottom:6px;color:#444;font-size:0.9rem;">Fecha</span>
  <input type="date" style="padding:10px 12px;border:1px solid #ccc;border-radius:8px;font-size:1rem;" />
</label>''',
    ),
    UiBuilderComponent(
      id: 'form',
      label: 'Form',
      category: 'Formulario',
      icon: Icons.dynamic_form_outlined,
      htmlSnippet: '''
<form data-voryxel="form" data-voryxel-container="1"
  style="margin:16px 0;padding:20px;border:1px solid #e5e7eb;border-radius:12px;max-width:420px;
  font-family:system-ui,sans-serif;background:#fff;">
  <label style="display:block;margin-bottom:12px;">
    <span style="display:block;margin-bottom:6px;font-size:0.9rem;color:#444;">Email</span>
    <input type="email" required placeholder="tú@email.com"
      style="width:100%;padding:10px 12px;border:1px solid #ccc;border-radius:8px;box-sizing:border-box;" />
  </label>
  <button type="submit"
    style="padding:12px 18px;border:none;border-radius:8px;background:#2563eb;color:#fff;font-weight:600;cursor:pointer;">
    Enviar
  </button>
</form>''',
    ),

    // ── Media ─────────────────────────────────────────────────────
    UiBuilderComponent(
      id: 'video',
      label: 'VideoPlayer',
      category: 'Media',
      icon: Icons.videocam_outlined,
      htmlSnippet: '''
<video data-voryxel="video" controls
  style="display:block;width:100%;max-width:640px;margin:12px 0;border-radius:12px;background:#000;"
  src="https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4">
  Tu navegador no soporta video.
</video>''',
    ),
    UiBuilderComponent(
      id: 'youtube',
      label: 'YouTube',
      category: 'Media',
      icon: Icons.play_circle_outline,
      htmlSnippet: '''
<div data-voryxel="youtube" style="position:relative;padding-bottom:56.25%;height:0;margin:12px 0;border-radius:12px;overflow:hidden;">
  <iframe title="YouTube"
    src="https://www.youtube.com/embed/dQw4w9WgXcQ"
    style="position:absolute;inset:0;width:100%;height:100%;border:0;"
    allow="accelerometer;autoplay;clipboard-write;encrypted-media;gyroscope;picture-in-picture"
    allowfullscreen></iframe>
</div>''',
    ),
    UiBuilderComponent(
      id: 'audio',
      label: 'AudioPlayer',
      category: 'Media',
      icon: Icons.graphic_eq,
      htmlSnippet: '''
<audio data-voryxel="audio" controls
  style="display:block;width:100%;max-width:420px;margin:12px 0;"
  src="https://interactive-examples.mdn.mozilla.net/media/cc0-audio/t-rex-roar.mp3">
  Tu navegador no soporta audio.
</audio>''',
    ),
    UiBuilderComponent(
      id: 'webview',
      label: 'WebView',
      category: 'Media',
      icon: Icons.web_asset,
      htmlSnippet: '''
<iframe data-voryxel="webview" title="WebView"
  src="https://example.com"
  style="display:block;width:100%;height:280px;margin:12px 0;border:1px solid #e5e7eb;border-radius:12px;"></iframe>''',
    ),
    UiBuilderComponent(
      id: 'map',
      label: 'Map',
      category: 'Media',
      icon: Icons.map_outlined,
      htmlSnippet: '''
<div data-voryxel="map"
  style="margin:12px 0;height:220px;border-radius:12px;overflow:hidden;border:1px solid #e5e7eb;background:#e2e8f0;
  display:flex;align-items:center;justify-content:center;font-family:system-ui,sans-serif;color:#475569;">
  📍 Mapa (sustituye por embed de Google Maps)
</div>''',
    ),
    UiBuilderComponent(
      id: 'lottie_placeholder',
      label: 'Lottie',
      category: 'Media',
      icon: Icons.animation,
      htmlSnippet: '''
<div data-voryxel="lottie"
  style="margin:12px 0;padding:32px;border-radius:12px;border:1px dashed #94a3b8;text-align:center;
  font-family:system-ui,sans-serif;color:#64748b;">
  Animación Lottie — pega aquí tu JSON / player
</div>''',
    ),
    UiBuilderComponent(
      id: 'pdf',
      label: 'PdfViewer',
      category: 'Media',
      icon: Icons.picture_as_pdf_outlined,
      htmlSnippet: '''
<a data-voryxel="pdf" href="#"
  style="display:inline-flex;align-items:center;gap:8px;margin:12px 0;padding:12px 16px;border-radius:10px;
  background:#fef2f2;color:#b91c1c;font-family:system-ui,sans-serif;font-weight:600;text-decoration:none;">
  📄 Ver PDF
</a>''',
    ),
  ];
}

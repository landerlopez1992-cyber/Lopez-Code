import 'package:flutter/material.dart';

/// Componente arrastrable del UI Builder (Nivel 1 — HTML).
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

  /// Catálogo MVP (~15 piezas básicas).
  static const List<UiBuilderComponent> catalog = [
    UiBuilderComponent(
      id: 'heading',
      label: 'Título',
      category: 'Texto',
      icon: Icons.title,
      htmlSnippet: '''
<section data-voryxel="heading" style="margin:16px 0;font-family:system-ui,sans-serif;">
  <h1 style="margin:0;font-size:2rem;color:#111;">Nuevo título</h1>
  <p style="margin:8px 0 0;color:#555;">Subtítulo o descripción breve.</p>
</section>''',
    ),
    UiBuilderComponent(
      id: 'paragraph',
      label: 'Párrafo',
      category: 'Texto',
      icon: Icons.notes,
      htmlSnippet: '''
<p data-voryxel="paragraph" style="margin:12px 0;font-family:system-ui,sans-serif;line-height:1.5;color:#333;">
  Escribe aquí tu texto. Puedes editarlo en la pestaña Code.
</p>''',
    ),
    UiBuilderComponent(
      id: 'button',
      label: 'Botón',
      category: 'Acciones',
      icon: Icons.smart_button,
      htmlSnippet: '''
<a data-voryxel="button" href="#"
  style="display:inline-block;margin:8px 0;padding:12px 20px;border:none;border-radius:8px;
  background:#2563eb;color:#fff;font-size:1rem;font-weight:600;cursor:pointer;font-family:system-ui,sans-serif;text-decoration:none;">
  Botón
</a>''',
    ),
    UiBuilderComponent(
      id: 'link',
      label: 'Enlace',
      category: 'Acciones',
      icon: Icons.link,
      htmlSnippet: '''
<a data-voryxel="link" href="https://example.com" target="_blank" rel="noopener"
  style="color:#2563eb;font-family:system-ui,sans-serif;text-decoration:underline;">
  Enlace
</a>''',
    ),
    UiBuilderComponent(
      id: 'input',
      label: 'Input',
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
      icon: Icons.wrap_text,
      htmlSnippet: '''
<label data-voryxel="textarea" style="display:block;margin:12px 0;font-family:system-ui,sans-serif;">
  <span style="display:block;margin-bottom:6px;color:#444;font-size:0.9rem;">Mensaje</span>
  <textarea rows="4" placeholder="Tu mensaje…"
    style="width:100%;max-width:420px;padding:10px 12px;border:1px solid #ccc;border-radius:8px;font-size:1rem;box-sizing:border-box;"></textarea>
</label>''',
    ),
    UiBuilderComponent(
      id: 'image',
      label: 'Imagen',
      category: 'Media',
      icon: Icons.image_outlined,
      htmlSnippet: '''
<img data-voryxel="image"
  src="https://picsum.photos/640/360"
  alt="Imagen"
  style="display:block;max-width:100%;height:auto;margin:12px 0;border-radius:12px;" />''',
    ),
    UiBuilderComponent(
      id: 'card',
      label: 'Card',
      category: 'Layout',
      icon: Icons.crop_square,
      htmlSnippet: '''
<div data-voryxel="card"
  style="margin:16px 0;padding:20px;max-width:360px;background:#fff;border:1px solid #e5e7eb;
  border-radius:12px;box-shadow:0 4px 14px rgba(0,0,0,0.08);font-family:system-ui,sans-serif;">
  <h3 style="margin:0 0 8px;font-size:1.15rem;color:#111;">Card</h3>
  <p style="margin:0;color:#555;line-height:1.45;">Contenido de la tarjeta. Edítalo en Code.</p>
</div>''',
    ),
    UiBuilderComponent(
      id: 'container',
      label: 'Contenedor',
      category: 'Layout',
      icon: Icons.check_box_outline_blank,
      htmlSnippet: '''
<div data-voryxel="container"
  style="margin:16px 0;padding:24px;border:2px dashed #94a3b8;border-radius:12px;
  min-height:80px;font-family:system-ui,sans-serif;color:#64748b;">
  Contenedor — suelta más elementos cerca o edita en Code.
</div>''',
    ),
    UiBuilderComponent(
      id: 'hero',
      label: 'Hero',
      category: 'Secciones',
      icon: Icons.view_agenda_outlined,
      htmlSnippet: '''
<section data-voryxel="hero"
  style="margin:0 0 24px;padding:48px 24px;border-radius:16px;text-align:center;
  background:linear-gradient(135deg,#0f172a,#1e3a8a);color:#fff;font-family:system-ui,sans-serif;">
  <h2 style="margin:0 0 12px;font-size:2rem;">Hero section</h2>
  <p style="margin:0 0 20px;opacity:0.9;">Una sección destacada para tu landing.</p>
  <button type="button" style="padding:12px 22px;border:none;border-radius:8px;background:#22c55e;color:#04140a;font-weight:700;cursor:pointer;">
    Call to action
  </button>
</section>''',
    ),
    UiBuilderComponent(
      id: 'navbar',
      label: 'Navbar',
      category: 'Secciones',
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
      id: 'divider',
      label: 'Separador',
      category: 'Layout',
      icon: Icons.horizontal_rule,
      htmlSnippet: '''
<hr data-voryxel="divider" style="border:none;border-top:1px solid #e5e7eb;margin:24px 0;" />''',
    ),
    UiBuilderComponent(
      id: 'spacer',
      label: 'Espacio',
      category: 'Layout',
      icon: Icons.space_bar,
      htmlSnippet: '''
<div data-voryxel="spacer" style="height:32px;" aria-hidden="true"></div>''',
    ),
    UiBuilderComponent(
      id: 'list',
      label: 'Lista',
      category: 'Texto',
      icon: Icons.format_list_bulleted,
      htmlSnippet: '''
<ul data-voryxel="list" style="margin:12px 0;padding-left:22px;font-family:system-ui,sans-serif;color:#333;line-height:1.6;">
  <li>Primer ítem</li>
  <li>Segundo ítem</li>
  <li>Tercer ítem</li>
</ul>''',
    ),
    UiBuilderComponent(
      id: 'video',
      label: 'Video',
      category: 'Media',
      icon: Icons.videocam_outlined,
      htmlSnippet: '''
<video data-voryxel="video" controls
  style="display:block;width:100%;max-width:640px;margin:12px 0;border-radius:12px;background:#000;"
  src="https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4">
  Tu navegador no soporta video.
</video>''',
    ),
  ];
}

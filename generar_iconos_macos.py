#!/usr/bin/env python3
"""
Script para generar iconos de macOS con dimensiones correctas y esquinas redondeadas.
Los iconos de macOS deben tener esquinas redondeadas (radio ~20-22%) y padding interno.
"""

from PIL import Image, ImageDraw
import os
import sys

def crear_icono_con_esquinas_redondeadas(tamaño, logo_path, output_path, padding_percent=0.25, corner_radius_percent=0.20):
    """
    Crea un icono con esquinas redondeadas y padding interno.
    
    Args:
        tamaño: Tamaño del icono (ej: 1024)
        logo_path: Ruta al logo original
        output_path: Ruta donde guardar el icono
        padding_percent: Porcentaje de padding interno (default: 15%)
        corner_radius_percent: Porcentaje del radio de esquinas (default: 22%)
    """
    # Crear imagen base transparente
    icono = Image.new('RGBA', (tamaño, tamaño), (0, 0, 0, 0))
    
    # Calcular radio de esquinas
    corner_radius = int(tamaño * corner_radius_percent)
    
    # Crear máscara con esquinas redondeadas
    mask = Image.new('L', (tamaño, tamaño), 0)
    draw_mask = ImageDraw.Draw(mask)
    
    # Dibujar rectángulo redondeado
    draw_mask.rounded_rectangle(
        [(0, 0), (tamaño, tamaño)],
        radius=corner_radius,
        fill=255
    )
    
    # Calcular padding interno (más compacto para que el icono se vea del tamaño correcto)
    padding = int(tamaño * padding_percent)
    area_logo = tamaño - (padding * 2)
    
    # Asegurar que el área del logo sea par para mejor renderizado
    if area_logo % 2 != 0:
        area_logo -= 1
        padding = (tamaño - area_logo) // 2
    
    # Cargar y redimensionar el logo
    try:
        logo = Image.open(logo_path)
        # Convertir a RGBA si no lo es
        if logo.mode != 'RGBA':
            logo = logo.convert('RGBA')
        
        # Redimensionar manteniendo aspecto
        logo.thumbnail((area_logo, area_logo), Image.Resampling.LANCZOS)
        
        # Crear imagen del logo con fondo transparente del tamaño correcto
        logo_final = Image.new('RGBA', (area_logo, area_logo), (0, 0, 0, 0))
        
        # Centrar el logo
        x_offset = (area_logo - logo.width) // 2
        y_offset = (area_logo - logo.height) // 2
        logo_final.paste(logo, (x_offset, y_offset), logo)
        
        # Pegar el logo en el icono con padding
        icono.paste(logo_final, (padding, padding), logo_final)
        
    except Exception as e:
        print(f"Error al procesar logo: {e}")
        # Si hay error, crear un icono simple con el logo básico
        draw = ImageDraw.Draw(icono)
        # Dibujar un fondo azul con chevrones
        draw.rounded_rectangle(
            [(0, 0), (tamaño, tamaño)],
            radius=corner_radius,
            fill=(0, 122, 255, 255)  # Azul primario
        )
    
    # Aplicar máscara de esquinas redondeadas
    icono.putalpha(mask)
    
    # Guardar el icono
    icono.save(output_path, 'PNG', optimize=True)
    print(f"✅ Icono generado: {output_path} ({tamaño}x{tamaño})")

def main():
    # Rutas
    script_dir = os.path.dirname(os.path.abspath(__file__))
    logo_path = os.path.join(script_dir, 'logo.png')
    iconos_dir = os.path.join(script_dir, 'macos', 'Runner', 'Assets.xcassets', 'AppIcon.appiconset')
    
    # Verificar que existe el logo
    if not os.path.exists(logo_path):
        print(f"❌ Error: No se encuentra el logo en {logo_path}")
        sys.exit(1)
    
    # Crear directorio si no existe
    os.makedirs(iconos_dir, exist_ok=True)
    
    # Tamaños de iconos para macOS (según Contents.json)
    # Nota: Los tamaños @2x son el doble del tamaño base
    iconos = [
        (16, 'app_icon_16.png'),      # 16x16 @1x
        (32, 'app_icon_32.png'),      # 16x16 @2x y 32x32 @1x
        (64, 'app_icon_64.png'),      # 32x32 @2x
        (128, 'app_icon_128.png'),    # 128x128 @1x
        (256, 'app_icon_256.png'),    # 128x128 @2x y 256x256 @1x
        (512, 'app_icon_512.png'),    # 256x256 @2x y 512x512 @1x
        (1024, 'app_icon_1024.png'),  # 512x512 @2x
    ]
    
    print("🎨 Generando iconos de macOS con esquinas redondeadas...")
    print(f"📁 Logo fuente: {logo_path}")
    print(f"📁 Directorio destino: {iconos_dir}\n")
    
    for tamaño, nombre_archivo in iconos:
        output_path = os.path.join(iconos_dir, nombre_archivo)
        crear_icono_con_esquinas_redondeadas(tamaño, logo_path, output_path)
    
    print("\n✅ ¡Todos los iconos han sido generados correctamente!")
    print("💡 Nota: Es posible que necesites reconstruir la app para ver los cambios en el dock.")

if __name__ == '__main__':
    main()

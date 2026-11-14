import 'package:flutter/material.dart';

import 'cursor_theme.dart';

/// Logo oficial de Voryxel Code (icono limpio + wordmark).
class VoryxelBrandLogo extends StatelessWidget {
  final double iconSize;
  final double fontSize;
  final bool showWordmark;
  final bool showSubtitle;
  final String subtitle;
  final MainAxisAlignment alignment;
  /// `tile` = icono con fondo (App Icon). `mark` = solo la V en transparente.
  final VoryxelLogoStyle style;

  const VoryxelBrandLogo({
    super.key,
    this.iconSize = 72,
    this.fontSize = 24,
    this.showWordmark = true,
    this.showSubtitle = true,
    this.subtitle = 'Pro · Settings',
    this.alignment = MainAxisAlignment.center,
    this.style = VoryxelLogoStyle.tile,
  });

  static const assetTile = 'assets/branding/voryxel_app_icon.png';
  static const assetMark = 'assets/branding/voryxel_logo_mark.png';

  @override
  Widget build(BuildContext context) {
    final asset =
        style == VoryxelLogoStyle.mark ? assetMark : assetTile;
    final radius = style == VoryxelLogoStyle.tile
        ? BorderRadius.circular(iconSize * 0.22)
        : BorderRadius.zero;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ClipRRect(
          borderRadius: radius,
          child: Image.asset(
            asset,
            width: iconSize,
            height: iconSize,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, __, ___) => Icon(
              Icons.code,
              size: iconSize * 0.7,
              color: CursorTheme.primary,
            ),
          ),
        ),
        if (showWordmark) ...[
          SizedBox(height: iconSize * 0.16),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              'VORYXEL CODE',
              maxLines: 1,
              softWrap: false,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: CursorTheme.textPrimary,
                fontSize: fontSize,
                fontWeight: FontWeight.w700,
                letterSpacing: fontSize * 0.04,
                height: 1.1,
              ),
            ),
          ),
        ],
        if (showSubtitle) ...[
          const SizedBox(height: 6),
          Text(
            subtitle,
            maxLines: 1,
            softWrap: false,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: CursorTheme.textSecondary,
              fontSize: (fontSize * 0.5).clamp(11, 14),
              height: 1.2,
            ),
          ),
        ],
      ],
    );
  }
}

enum VoryxelLogoStyle { tile, mark }
